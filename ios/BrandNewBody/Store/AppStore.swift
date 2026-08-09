import Foundation
import Observation
import SwiftData
import CoreData

/// The single door between SwiftData and everything else.
///
/// Views never touch a `ModelContext`. They read `store.state` — one immutable
/// `LogState` value — and call methods here to change it. That keeps the whole
/// `Core` layer pure and testable, and it means a CloudKit push that arrives
/// mid-workout re-materialises one struct rather than invalidating a hundred
/// `@Query` results underneath a half-typed set.
@Observable
@MainActor
final class AppStore {

    private(set) var state: LogState
    private let context: ModelContext

    /// Set when the container fell back to a local-only store — the app still
    /// works, but Setup needs to say that iCloud isn't carrying the data.
    let cloudStatus: CloudStatus

    enum CloudStatus: Equatable {
        case syncing
        case localOnly(reason: String)
    }

    init(context: ModelContext, cloudStatus: CloudStatus = .syncing) {
        self.context = context
        self.cloudStatus = cloudStatus
        self.state = LogState()
        reload()
        seedIfNeeded()
        observeRemoteChanges()
    }

    // MARK: - Reading

    /// Rebuilds the snapshot from the store.
    ///
    /// A full re-read on every write is O(everything), which sounds careless
    /// until you count: a year of daily use is a few thousand small rows, and
    /// the alternative — mutating the snapshot in place and hoping it stays in
    /// step with the database — is exactly the class of bug that is invisible
    /// until someone's Tuesday goes missing.
    func reload() {
        var next = LogState(today: DateKit.todayKey)

        let settings = fetchSettings()
        next.startDate = settings.startDate.isEmpty ? next.today : settings.startDate
        next.pyramidCap = settings.pyramidCap
        next.vestKg = settings.vestKg
        next.vestPhase = settings.vestPhase
        next.barKg = settings.barKg
        next.calAdjust = settings.calAdjust
        next.heightCm = settings.heightCm
        next.birthYear = settings.birthYear
        next.deloadSnooze = settings.deloadSnooze
        next.mindStartDate = settings.mindStartDate
        next.mindUnlocked = settings.mindUnlocked
        next.mindTargets = settings.mindTargets
        next.mindLadderCap = settings.mindLadderCap
        next.charismaIx = settings.charismaIx
        next.charismaSince = settings.charismaSince

        next.weights = fetch(WeightEntry.self).map {
            WeightRecord(date: $0.date, kg: $0.kg, seed: $0.seed)
        }
        next.waist = fetch(WaistEntry.self).map {
            WaistRecord(date: $0.date, cm: $0.cm)
        }
        for day in fetch(DayEntry.self) where !day.isEmpty {
            next.logs[day.date] = day.record
        }
        for lift in fetch(LiftEntry.self) where !lift.sets.isEmpty {
            next.lifts[lift.liftID, default: []].append(LiftRecord(date: lift.date, sets: lift.sets))
        }
        for entry in fetch(PyramidEntry.self) {
            next.pyramidLog[entry.date] = PyramidRecord(cap: entry.cap, vestKg: entry.vestKg)
        }
        next.deloadLog = Set(fetch(DeloadEntry.self).map(\.date))
        for entry in fetch(OffDayEntry.self) {
            next.off[entry.date] = entry.kind
        }
        for entry in fetch(RecoveryEntry.self) where !entry.record.isEmpty {
            next.recovery[entry.date] = entry.record
        }
        for day in fetch(MindDayEntry.self) where !day.isEmpty {
            next.mindLogs[day.date] = day.record
        }
        next.mindLadderLog = Set(fetch(LadderEntry.self).map(\.date))

        state = next
    }

    /// Advances the day and applies the progressions that happen on their own.
    ///
    /// An installed app is resumed, not relaunched — it can sit in the app
    /// switcher across midnight for days. Every write path reads `state.today`,
    /// so if that never moves, everything typed after midnight silently lands
    /// on yesterday.
    func refresh() {
        if state.today != DateKit.todayKey { reload() }
        bumpMindTargets()
        advanceCharismaIfEarned()
    }

    private func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private func fetchSettings() -> AppSettings {
        let existing = fetch(AppSettings.self).sorted { $0.createdAt < $1.createdAt }
        if let first = existing.first {
            // Two devices racing on first launch can each create a row. Keep
            // the oldest and drop the rest, rather than showing the user two
            // sets of settings that disagree.
            for extra in existing.dropFirst() { context.delete(extra) }
            if existing.count > 1 { save() }
            return first
        }
        let created = AppSettings(startDate: DateKit.todayKey)
        context.insert(created)
        save()
        return created
    }

    private func save() {
        do { try context.save() }
        catch { assertionFailure("Could not save: \(error)") }
    }

    /// Runs a mutation and republishes the snapshot.
    private func mutate(_ body: (AppSettings) -> Void) {
        body(fetchSettings())
        save()
        reload()
    }

    // MARK: - Seeding

    /// A log with no weigh-ins still has to render a chart, a trend and a
    /// calorie target, all of which read a bodyweight. So there is a starting
    /// placeholder — marked, because without the mark the weigh-in row at the
    /// top of Today told a brand-new user they had already logged 79 kg this
    /// morning. Logging for real replaces the record and the flag goes with it.
    private func seedIfNeeded() {
        guard state.weights.isEmpty else { return }
        context.insert(WeightEntry(date: state.today, kg: 79, seed: true))
        save()
        reload()
    }

    // MARK: - Remote changes

    private func observeRemoteChanges() {
        // CloudKit hands SwiftData changes through the Core Data coordinator,
        // which posts this. Belt and braces with the foreground refresh in the
        // scene phase handler: the notification is best-effort, and a phone
        // that was asleep during the push gets nothing.
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: nil
        ) { _ in
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    // MARK: - Session ticks

    func toggleItem(_ key: String, on date: String) {
        let entry = dayEntry(date)
        var record = entry.record
        if record.done.contains(key) { record.done.remove(key) } else { record.done.insert(key) }
        entry.apply(record)
        // Ticking the pyramid records what it actually was that week, so the
        // history says "cap 6 + 5 kg" rather than just "done".
        if key == "sa-pyramid" {
            if record.done.contains(key) {
                upsertPyramid(date: date, cap: state.pyramidCap,
                              vestKg: Pyramid.isVestWeek(state) ? Pyramid.vestKg(state) : nil)
            } else {
                deletePyramid(date: date)
            }
        }
        commit(entry)
    }

    func toggleFuel(on date: String) {
        let entry = dayEntry(date)
        entry.fuelHit.toggle()
        commit(entry)
    }

    func toggleMobility(_ index: Int, on date: String) {
        let entry = dayEntry(date)
        var record = entry.record
        if record.mobility.contains(index) { record.mobility.remove(index) } else { record.mobility.insert(index) }
        entry.apply(record)
        commit(entry)
    }

    func setNote(_ note: String, on date: String) {
        let entry = dayEntry(date)
        entry.note = note
        commit(entry)
    }

    private func dayEntry(_ date: String) -> DayEntry {
        if let found = fetch(DayEntry.self).first(where: { $0.date == date }) { return found }
        let created = DayEntry(date: date)
        context.insert(created)
        return created
    }

    /// Empty days are deleted rather than kept as blanks — otherwise merely
    /// opening a past day would write a row that syncs to every device.
    private func commit(_ entry: DayEntry) {
        if entry.isEmpty { context.delete(entry) }
        save()
        reload()
    }

    // MARK: - Weigh-ins and waist

    func logWeight(kg: Double, on date: String) {
        // The seed placeholder is replaced, not added to.
        for existing in fetch(WeightEntry.self) where existing.date == date {
            context.delete(existing)
        }
        context.insert(WeightEntry(date: date, kg: kg, seed: false))
        save()
        reload()
    }

    func deleteWeight(on date: String) {
        for existing in fetch(WeightEntry.self) where existing.date == date {
            context.delete(existing)
        }
        save()
        reload()
    }

    func logWaist(cm: Double, on date: String) {
        for existing in fetch(WaistEntry.self) where existing.date == date {
            context.delete(existing)
        }
        context.insert(WaistEntry(date: date, cm: cm))
        save()
        reload()
    }

    // MARK: - Lifts

    func setSets(_ sets: [LiftSet], liftID: String, on date: String) {
        // A set with no reps is an empty input box, not a set that happened.
        let usable = sets.filter { $0.reps > 0 }
        let existing = fetch(LiftEntry.self).first { $0.liftID == liftID && $0.date == date }
        if usable.isEmpty {
            if let existing { context.delete(existing) }
        } else if let existing {
            existing.sets = usable
        } else {
            context.insert(LiftEntry(liftID: liftID, date: date, sets: usable))
        }
        save()
        reload()
    }

    // MARK: - Pyramid

    func adjustPyramidCap(by delta: Int) {
        mutate { $0.pyramidCap = min(Pyramid.maxCap, max(1, $0.pyramidCap + delta)) }
    }

    func adjustVest(by delta: Double) {
        let current = Pyramid.vestKg(state) ?? 0
        mutate { $0.vestKg = max(0, ((current + delta) * 2).rounded() / 2) }
    }

    /// Back to tracking bodyweight.
    func resetVestToAuto() {
        mutate { $0.vestKg = nil }
    }

    /// Flips which parity of week carries the vest, for when the real schedule
    /// has drifted out of step with the counter.
    func swapVestWeek() {
        mutate { $0.vestPhase = ($0.vestPhase + 1) % 2 }
    }

    private func upsertPyramid(date: String, cap: Int, vestKg: Double?) {
        if let existing = fetch(PyramidEntry.self).first(where: { $0.date == date }) {
            existing.cap = cap
            existing.vestKg = vestKg
        } else {
            context.insert(PyramidEntry(date: date, cap: cap, vestKg: vestKg))
        }
    }

    private func deletePyramid(date: String) {
        for existing in fetch(PyramidEntry.self) where existing.date == date {
            context.delete(existing)
        }
    }

    // MARK: - Deload

    func startDeload() {
        guard !state.deloadLog.contains(state.today) else { return }
        context.insert(DeloadEntry(date: state.today))
        save()
        reload()
    }

    func endDeloadEarly() {
        guard let last = Deload.lastDeload(state) else { return }
        for entry in fetch(DeloadEntry.self) where entry.date == last {
            context.delete(entry)
        }
        save()
        reload()
    }

    func snoozeDeload() {
        mutate { $0.deloadSnooze = self.state.today }
    }

    func setRecovery(_ percent: Int?, on date: String) {
        let entry: RecoveryEntry
        if let found = fetch(RecoveryEntry.self).first(where: { $0.date == date }) {
            entry = found
        } else {
            entry = RecoveryEntry(date: date)
            context.insert(entry)
        }
        entry.recovery = percent.map { min(100, max(0, $0)) }
        if entry.record.isEmpty { context.delete(entry) }
        save()
        reload()
    }

    // MARK: - Time off

    func setOff(_ kind: OffKind?, on date: String) {
        for existing in fetch(OffDayEntry.self) where existing.date == date {
            context.delete(existing)
        }
        if let kind { context.insert(OffDayEntry(date: date, kind: kind)) }
        save()
        reload()
    }

    /// Inclusive on both ends, and capped so a mis-typed year cannot write
    /// thousands of records into a database that syncs on every change.
    @discardableResult
    func setOffRange(from: String, to: String, kind: OffKind?) -> Int {
        let days = Array(DateKit.range(from: from, to: to).prefix(TimeOff.maxSpan))
        guard !days.isEmpty else { return 0 }
        let wanted = Set(days)
        for existing in fetch(OffDayEntry.self) where wanted.contains(existing.date) {
            context.delete(existing)
        }
        if let kind {
            for day in days { context.insert(OffDayEntry(date: day, kind: kind)) }
        }
        save()
        reload()
        return days.count
    }

    /// "Better — back today". Ends the current run at yesterday.
    func endTimeOffToday() {
        setOff(nil, on: state.today)
    }

    // MARK: - Settings

    func setHeight(_ cm: Int) { mutate { $0.heightCm = cm } }
    func setBirthYear(_ year: Int) { mutate { $0.birthYear = year } }
    func setStartDate(_ date: String) { mutate { $0.startDate = date } }
    func setBarKg(_ kg: Double) { mutate { $0.barKg = kg } }

    func adjustCalories(by delta: Int) {
        mutate { $0.calAdjust += delta }
    }

    // MARK: - Mind

    /// Started on first interaction rather than at install, so a mode you
    /// opened once out of curiosity three months ago does not report week 14.
    func startMind() {
        guard state.mindStartDate == nil else { return }
        mutate { $0.mindStartDate = self.state.today }
    }

    func toggleMindPractice(_ practice: MindPlan.Practice, on date: String) {
        let key = practice.kind == .drill ? Mind.charismaKey(state) : practice.key
        toggleMindKey(key, on: date)
    }

    func toggleMindKey(_ key: String, on date: String) {
        let entry = mindEntry(date)
        var record = entry.record
        if record.done.contains(key) { record.done.remove(key) } else { record.done.insert(key) }
        entry.apply(record)
        commitMind(entry, date: date)
    }

    func setMindMinutes(_ minutes: Int?, practice: String, on date: String) {
        let entry = mindEntry(date)
        var record = entry.record
        if let minutes, minutes > 0 { record.mins[practice] = minutes } else { record.mins[practice] = nil }
        entry.apply(record)
        commitMind(entry, date: date)
    }

    func setJournal(_ text: String, on date: String) {
        let entry = mindEntry(date)
        entry.journal = String(text.prefix(MindPlan.journalMax))
        commitMind(entry, date: date)
    }

    private func mindEntry(_ date: String) -> MindDayEntry {
        if let found = fetch(MindDayEntry.self).first(where: { $0.date == date }) { return found }
        let created = MindDayEntry(date: date)
        context.insert(created)
        return created
    }

    private func commitMind(_ entry: MindDayEntry, date: String) {
        if entry.isEmpty { context.delete(entry) }
        save()
        reload()
        recordLadderIfCleared(on: date)
    }

    func unlockNextPractice() {
        guard state.mindUnlocked < MindPlan.practices.count else { return }
        mutate { $0.mindUnlocked += 1 }
    }

    func adjustLadderCap(by delta: Int) {
        mutate { $0.mindLadderCap = max(1, min(MindPlan.ladder.count, $0.mindLadderCap + delta)) }
    }

    /// A cleared ladder is what the Mind verdict counts, so it is recorded the
    /// moment the last rung goes on — and taken back off if a rung is unticked,
    /// because a week half-climbed is not a week climbed.
    private func recordLadderIfCleared(on date: String) {
        guard DateKit.dow(key: date) == 6 else { return }
        let rungs = Mind.ladderRungs(cap: state.mindLadderCap)
        let done = state.mindDay(date).done
        let cleared = rungs.indices.allSatisfy { done.contains("rung\($0 + 1)") }
        let existing = fetch(LadderEntry.self).first { $0.date == date }
        if cleared, existing == nil {
            context.insert(LadderEntry(date: date))
        } else if !cleared, let existing {
            context.delete(existing)
        } else {
            return
        }
        save()
        reload()
    }

    /// Skip to the next drill — for one that genuinely doesn't apply to you.
    func skipCharismaDrill() {
        mutate {
            $0.charismaIx += 1
            $0.charismaSince = self.state.today
        }
    }

    /// Advances on use, not on the calendar: a drill you have not practised is
    /// not one you are finished with. Called on every refresh rather than on
    /// the tick itself, so the new drill arrives the next time you open the
    /// app rather than replacing the row under your thumb.
    private func advanceCharismaIfEarned() {
        guard Mind.charismaReady(state) else { return }
        mutate {
            $0.charismaIx += 1
            $0.charismaSince = self.state.today
        }
    }

    /// Same rule the barbell uses: hit the target three sessions running and
    /// the target goes up.
    private func bumpMindTargets() {
        var raised: [String: Int] = [:]
        for practice in Mind.activePractices(state) where practice.kind == .minutes {
            guard let next = Mind.nextTarget(state, practice), next.ready, next.next > next.at else { continue }
            raised[practice.key] = next.next
        }
        guard !raised.isEmpty else { return }
        mutate { settings in
            var targets = settings.mindTargets
            for (key, value) in raised { targets[key] = value }
            settings.mindTargets = targets
        }
    }

    // MARK: - Backup and reset

    /// The JSON backup. iCloud carries the log between the user's own devices;
    /// this is for everything else — moving to an Android phone, keeping a
    /// copy outside Apple's estate, or undoing an afternoon with the delete
    /// button, which no amount of syncing protects you from.
    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }

    /// Replaces everything. Additive merging is what CloudKit does between
    /// your own devices; a restore from file is an explicit "this is the
    /// truth now", and pretending otherwise leaves the user unable to undo a
    /// bad import.
    func importData(_ data: Data) throws {
        let incoming = try JSONDecoder().decode(LogState.self, from: data)
        deleteAllRecords()
        apply(incoming)
        save()
        reload()
    }

    func deleteAllData() {
        deleteAllRecords()
        for settings in fetch(AppSettings.self) { context.delete(settings) }
        save()
        reload()
        seedIfNeeded()
    }

    private func deleteAllRecords() {
        for entry in fetch(WeightEntry.self) { context.delete(entry) }
        for entry in fetch(WaistEntry.self) { context.delete(entry) }
        for entry in fetch(DayEntry.self) { context.delete(entry) }
        for entry in fetch(LiftEntry.self) { context.delete(entry) }
        for entry in fetch(PyramidEntry.self) { context.delete(entry) }
        for entry in fetch(DeloadEntry.self) { context.delete(entry) }
        for entry in fetch(OffDayEntry.self) { context.delete(entry) }
        for entry in fetch(RecoveryEntry.self) { context.delete(entry) }
        for entry in fetch(MindDayEntry.self) { context.delete(entry) }
        for entry in fetch(LadderEntry.self) { context.delete(entry) }
    }

    private func apply(_ incoming: LogState) {
        let settings = fetchSettings()
        settings.startDate = incoming.startDate
        settings.pyramidCap = incoming.pyramidCap
        settings.vestKg = incoming.vestKg
        settings.vestPhase = incoming.vestPhase
        settings.barKg = incoming.barKg
        settings.calAdjust = incoming.calAdjust
        settings.heightCm = incoming.heightCm
        settings.birthYear = incoming.birthYear
        settings.deloadSnooze = incoming.deloadSnooze
        settings.mindStartDate = incoming.mindStartDate
        settings.mindUnlocked = incoming.mindUnlocked
        settings.mindTargets = incoming.mindTargets
        settings.mindLadderCap = incoming.mindLadderCap
        settings.charismaIx = incoming.charismaIx
        settings.charismaSince = incoming.charismaSince

        for record in incoming.weights {
            context.insert(WeightEntry(date: record.date, kg: record.kg, seed: record.seed))
        }
        for record in incoming.waist {
            context.insert(WaistEntry(date: record.date, cm: record.cm))
        }
        for (date, record) in incoming.logs {
            let entry = DayEntry(date: date)
            entry.apply(record)
            context.insert(entry)
        }
        for (id, records) in incoming.lifts {
            for record in records {
                context.insert(LiftEntry(liftID: id, date: record.date, sets: record.sets))
            }
        }
        for (date, record) in incoming.pyramidLog {
            context.insert(PyramidEntry(date: date, cap: record.cap, vestKg: record.vestKg))
        }
        for date in incoming.deloadLog {
            context.insert(DeloadEntry(date: date))
        }
        for (date, kind) in incoming.off {
            context.insert(OffDayEntry(date: date, kind: kind))
        }
        for (date, record) in incoming.recovery {
            let entry = RecoveryEntry(date: date)
            entry.apply(record)
            context.insert(entry)
        }
        for (date, record) in incoming.mindLogs {
            let entry = MindDayEntry(date: date)
            entry.apply(record)
            context.insert(entry)
        }
        for date in incoming.mindLadderLog {
            context.insert(LadderEntry(date: date))
        }
    }

    // MARK: - CSV

    /// One-way, for poking at the numbers in a spreadsheet. Only the JSON can
    /// be imported back, and Setup says so.
    func weightsCSV() -> String {
        var lines = ["date,kg"]
        for record in state.sortedWeights where !record.seed {
            lines.append("\(record.date),\(record.kg)")
        }
        return lines.joined(separator: "\n")
    }

    func liftsCSV() -> String {
        var lines = ["date,lift,set,kg,reps"]
        for id in state.lifts.keys.sorted() {
            for record in state.liftHistory(id) {
                for (index, set) in record.sets.enumerated() {
                    let kg = set.kg.map { Lifts.fmt($0) } ?? ""
                    lines.append("\(record.date),\(id),\(index + 1),\(kg),\(set.reps)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
