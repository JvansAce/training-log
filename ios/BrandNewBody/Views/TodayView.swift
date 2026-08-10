import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(RestTimer.self) private var timer

    /// Which weekday's plan is on screen. Following today unless the user taps
    /// another rib.
    @State private var viewing: Int? = nil
    /// Set to a past date to back-fill a day that was never logged, instead of
    /// losing it.
    @State private var editingDate: String? = nil
    @State private var showBackfillPicker = false
    @State private var backfillDate = Date()

    private var state: LogState { store.state }
    private var viewingDow: Int { viewing ?? state.todayDow }
    /// Only today, or an explicitly back-filled day, can be written to.
    private var canEdit: Bool { editingDate != nil || viewingDow == state.todayDow }
    private var activeDate: String { editingDate ?? state.today }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            Spine(state: state, viewing: viewingDow) { viewing = $0; editingDate = nil }

            backfillRow

            if canEdit && editingDate == nil {
                WeighRow(state: state) { store.logWeight(kg: $0, on: state.today) }
            }

            OffPanel(state: state, editing: editingDate != nil)
            DeloadPanel(state: state, editing: editingDate != nil)
            RecoveryPanel(state: state)

            SessionPanel(state: state, dow: viewingDow, canEdit: canEdit,
                         activeDate: activeDate, editingDate: editingDate,
                         onBackToToday: { viewing = nil; editingDate = nil })

            WeightPanel(state: state)
            FuelPanel(state: state, dow: viewingDow, canEdit: canEdit, activeDate: activeDate)
            MobilityPanel(state: state, canEdit: canEdit, activeDate: activeDate)

            if editingDate == nil && TimeOff.today(state) == nil {
                OffControl(state: state)
            }
        }
    }

    @ViewBuilder
    private var backfillRow: some View {
        if let editing = editingDate {
            HStack {
                PTag("editing \(editing)", tint: Theme.amber)
                Spacer()
                ActionButton(title: "Back to today") { editingDate = nil; viewing = nil }
            }
        } else {
            HStack {
                ActionButton(title: "Forgot to log a day?") { showBackfillPicker = true }
                Spacer()
            }
            .sheet(isPresented: $showBackfillPicker) {
                BackfillSheet(selection: $backfillDate) { date in
                    editingDate = DateKit.key(date)
                    viewing = DateKit.dow(date)
                    showBackfillPicker = false
                }
                .presentationDetents([.height(360)])
            }
        }
    }
}

// MARK: - Spine

/// The seven ribs. The current day carries a fill showing how much of it is
/// ticked, which is the only progress indicator the app has and the reason the
/// spine is at the top rather than the plan.
private struct Spine: View {
    var state: LogState
    var viewing: Int
    var onSelect: (Int) -> Void

    static let ribHeight: CGFloat = 48

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Plan.order, id: \.self) { dow in
                let day = Plan.day(dow)
                let isToday = dow == state.todayDow
                Button { onSelect(dow) } label: {
                    ZStack(alignment: .bottom) {
                        Theme.slate
                        // How much of today is ticked, rising from the foot of
                        // the rib. A fixed height rather than a GeometryReader
                        // because a reader inside a ZStack claims all the space
                        // it is offered and would size the whole row.
                        if isToday {
                            Rectangle()
                                .fill(Theme.red.opacity(0.22))
                                .frame(height: Self.ribHeight * completion)
                        }
                        VStack(spacing: 6) {
                            Circle().fill(day.color).frame(width: 7, height: 7)
                            Text(day.label)
                                .font(Theme.mono(10, weight: isToday ? .bold : .regular))
                                .foregroundStyle(dow == viewing ? Theme.bone : Theme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.ribHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(dow == viewing ? Theme.bone.opacity(0.6) : Theme.line, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.label), \(day.title)")
            }
        }
    }

    private var completion: Double {
        let items = Plan.day(state.todayDow).items
        guard !items.isEmpty else { return 0 }
        return Double(state.day(state.today).done.count) / Double(items.count)
    }
}

// MARK: - Weigh-in

private struct WeighRow: View {
    var state: LogState
    var onLog: (Double) -> Void

    private var todayEntry: WeightRecord? {
        state.weights.first { $0.date == state.today && !$0.seed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EntryField(
                placeholder: todayEntry == nil ? "this morning, kg" : "change this morning, kg",
                buttonTitle: todayEntry == nil ? "Log" : "Update",
                prominent: todayEntry == nil
            ) { text in
                guard let kg = Double(text.replacingOccurrences(of: ",", with: ".")),
                      kg >= 40, kg <= 200 else { return false }
                onLog(kg)
                return true
            }
            if let todayEntry {
                PTag("logged \(String(format: "%.1f", todayEntry.kg)) kg", tint: Theme.green)
            }
        }
    }
}

// MARK: - Time off

private struct OffPanel: View {
    var state: LogState
    var editing: Bool
    @Environment(AppStore.self) private var store

    var body: some View {
        if !editing {
            if let run = TimeOff.current(state) {
                Panel(title: run.kind.label, tag: "day \(run.days)") {
                    if run.kind == .ill {
                        Note("""
                            Above the neck — runny nose, sore throat, sneezing — easy movement is fine. \
                            Below it — fever, chest, aching, gut — do not train. The reason is not softness: \
                            exercising through a febrile illness is how myocarditis happens. Fever-free for \
                            24 hours without paracetamol before you count yourself back, then ease in.
                            """)
                    } else {
                        Note("""
                            Nothing here is owed while you are away. Train if there is a gym and you feel \
                            like it — tick what you do and it counts. Skip the lot and the streak waits for \
                            you rather than resetting.
                            """)
                    }
                    Note("""
                        The scale, the trend and the deload prompt are all ignoring these days. Weigh in if \
                        you want the record; \(run.kind == .ill
                            ? "a fever will take a kilo or two of water off you and it is not fat"
                            : "travel food and salt will put a kilo or two on and it is not fat"), so nothing \
                        is drawn from it until \(TimeOff.weighHold) ordinary days have passed.
                        """)
                    HStack {
                        ActionButton(title: run.kind == .ill ? "Better — back today" : "Back today",
                                     prominent: true) { store.endTimeOffToday() }
                        PTag("since \(run.since)")
                    }
                }
            } else if let ramp = TimeOff.returnRamp(state) {
                Panel(title: "First week back",
                      tag: "\(ramp.days) day\(ramp.days == 1 ? "" : "s") \(ramp.kind == .ill ? "ill" : "away")") {
                    Note(ramp.long
                        ? """
                          Two-thirds of the sets, ninety percent of the weight, for about a week. Past a \
                          fortnight off the losses are real but small, and they come back far faster than \
                          they went — the thing that actually derails people here is a first session hard \
                          enough to leave them too sore to do the second.
                          """
                        : """
                          Same weights, drop the last set of each lift for two sessions. Strength barely \
                          moves across a break this short; what you have lost is the tolerance for the \
                          volume, and that is what to rebuild first.
                          """)
                    Note("The lift rows are suggesting a repeat instead of a jump until the gap closes\(ramp.days >= 7 ? ", and the vest week may have drifted while you were away — swap on the pyramid panel puts it back in step." : ".")")
                }
            }
        }
    }
}

private struct OffControl: View {
    var state: LogState
    @Environment(AppStore.self) private var store
    @State private var from = Date()
    @State private var to = Date()

    var body: some View {
        Panel(title: "Sick or away?", tag: "not a failure") {
            Reveal(title: "Mark time off") {
                VStack(alignment: .leading, spacing: 12) {
                    Note("""
                        Marking a day takes it out of the streak, the adherence chart, the weight trend and \
                        the deload signal. It does not hide anything — tick a session on an off day and it \
                        still counts.
                        """)
                    HStack {
                        ActionButton(title: "Ill today") { store.setOff(.ill, on: state.today) }
                        ActionButton(title: "Away today") { store.setOff(.away, on: state.today) }
                    }
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("To", selection: $to, displayedComponents: .date)
                    HStack {
                        ActionButton(title: "Mark ill") { apply(.ill) }
                        ActionButton(title: "Mark away") { apply(.away) }
                        ActionButton(title: "Clear") { apply(nil) }
                    }
                    Note("""
                        A range works forwards as well as back — book the holiday now and the app will \
                        already know. Up to \(TimeOff.maxSpan) days at a time.
                        """)
                }
                .font(Theme.body(13))
                .foregroundStyle(Theme.bone)
            }
        }
    }

    private func apply(_ kind: OffKind?) {
        store.setOffRange(from: DateKit.key(from), to: DateKit.key(to), kind: kind)
    }
}

// MARK: - Deload

private struct DeloadPanel: View {
    var state: LogState
    var editing: Bool
    @Environment(AppStore.self) private var store

    var body: some View {
        // Back-filling last Tuesday is not the moment to be asked about this
        // week — and "Start a deload week" would stamp today regardless, which
        // reads as a bug even though it is what you would want.
        if !editing {
            if Deload.inDeloadWeek(state) {
                let left = Deload.daysLeft(state)
                Panel(title: "Deload week", tag: "\(left) day\(left == 1 ? "" : "s") left") {
                    Note("""
                        Halve the sets. Keep the weight. Skip the pyramid. Same exercises, same loads, \
                        roughly half the work — cutting volume rather than intensity is what keeps the \
                        strength while the fatigue clears. Tennis and the Thursday walk are fine.
                        """)
                    HStack {
                        ActionButton(title: "End it early") { store.endDeloadEarly() }
                        if let started = Deload.lastDeload(state) { PTag("started \(started)") }
                    }
                }
            } else if let signal = Deload.signal(state) {
                Panel(title: "Take a deload", tag: "recovery is asking") {
                    VerdictLine(text: "\(signal.reason) That is the signal to back off for a week — not because a calendar says so, but because your own data does.",
                                tone: .fast)
                    Note("""
                        A deload here is half the sets at the same weight, and no pyramid. It is one week. \
                        The alternative is grinding through it and losing the next three.
                        """)
                    HStack {
                        ActionButton(title: "Start a deload week", prominent: true) { store.startDeload() }
                        ActionButton(title: "Not now") { store.snoozeDeload() }
                    }
                }
            }
        }
    }
}

// MARK: - Recovery

/// In the web app these readings came from WHOOP over an OAuth flow that
/// needed a server. This version has no server, so the number is typed —
/// everything downstream (the deload signal, the Progress chart) is unchanged,
/// because it only ever read a percentage out of the record.
/// Recovery, however it got there.
///
/// `AppStore` is the single source of truth for the numbers themselves —
/// `WhoopClient` only ever reaches this screen indirectly, by writing into
/// `state.recovery` through `applyWhoopReading`. What this panel reads
/// `WhoopClient` for directly is the two things that never get persisted:
/// whether a connection exists at all, and today's detected workouts, which
/// the app deliberately never ticks on its own — WHOOP knows you trained, it
/// doesn't know which items on the checklist you actually did.
private struct RecoveryPanel: View {
    var state: LogState
    @Environment(AppStore.self) private var store
    @Environment(WhoopClient.self) private var whoop

    private var reading: RecoveryRecord? { state.recovery[state.today] }
    private var isConnected: Bool { whoop.status == .connected }

    var body: some View {
        Panel(title: "Recovery", tag: tag) {
            if isConnected {
                connectedContent
            } else {
                disconnectedContent
            }
        }
    }

    private var tag: String {
        if let value = reading?.recovery { return "\(value)%" }
        return isConnected ? "no data yet today" : "not connected"
    }

    @ViewBuilder
    private var connectedContent: some View {
        HStack(spacing: 18) {
            statColumn(reading?.strain.map { String(format: "%.1f", $0) } ?? "–", label: "strain")
            statColumn(reading?.sleepPct.map { "\($0)%" } ?? "–", label: "sleep")
            statColumn(reading?.hrvMs.map { "\(Int($0.rounded()))" } ?? "–", label: "hrv ms")
            statColumn(reading?.restingHR.map { "\($0)" } ?? "–", label: "rhr")
        }

        if let workouts = whoop.today?.workouts, !workouts.isEmpty {
            let complete = state.day(state.today).done.count >= Plan.day(state.todayDow).items.count
            VStack(alignment: .leading, spacing: 6) {
                Text("WHOOP recorded " + workouts.map {
                    ($0.sport ?? "a workout")
                        + ($0.minutes.map { " · \($0) min" } ?? "")
                        + ($0.strain.map { " · \(String(format: "%.1f", $0)) strain" } ?? "")
                }.joined(separator: ", ") + " today.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                if !complete {
                    ActionButton(title: "Tick this session") { markTodayComplete() }
                }
            }
        }

        if let value = reading?.recovery, value < Deload.redRecovery {
            Note("""
                Recovery is red today. If today's session has any give in it — Thursday's cardio, the \
                pyramid — this is the day to take it.
                """)
        }
    }

    private func statColumn(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.mono(15, weight: .bold)).foregroundStyle(Theme.bone)
            Text(label).font(Theme.mono(9)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func markTodayComplete() {
        // Explicit tap rather than auto-ticking on detection, matching the
        // web app's reasoning exactly: WHOOP knows you trained, it doesn't
        // know which items on the checklist you actually did.
        for item in Plan.day(state.todayDow).items where !state.day(state.today).done.contains(item.key) {
            store.toggleItem(item.key, on: state.today)
        }
    }

    @ViewBuilder
    private var disconnectedContent: some View {
        if case .notConnected(let reason) = whoop.status, let reason {
            Note(reason, dimmed: true)
        }
        ActionButton(title: "Connect WHOOP", prominent: true) { whoop.connect() }

        EntryField(placeholder: "recovery %, if you don't", buttonTitle: "Log", prominent: false,
                   keyboard: .numberPad) { text in
            guard let value = Int(text), (0...100).contains(value) else { return false }
            store.setRecovery(value, on: state.today)
            return true
        }
        if let value = reading?.recovery {
            HStack {
                PTag("logged \(value)%")
                ActionButton(title: "Clear") { store.setRecovery(nil, on: state.today) }
            }
        }
        Note("""
            Connect WHOOP for this automatically, including the flag on days recovery is low. Or type it \
            by hand each morning if you wear a different strap — either way, it's what lets the app notice \
            a bad week and prescribe a deload off your own data rather than off a calendar.
            """)
    }
}

// MARK: - Session

private struct SessionPanel: View {
    var state: LogState
    var dow: Int
    var canEdit: Bool
    var activeDate: String
    var editingDate: String?
    var onBackToToday: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(RestTimer.self) private var timer
    @Environment(\.scenePhase) private var scenePhase
    @State private var note = ""
    @State private var noteLoaded = false
    @State private var noteLoadedFor = ""
    @State private var debouncer = Debouncer()

    private var day: TrainingDay { Plan.day(dow) }
    private var log: DayRecord { state.day(activeDate) }

    var body: some View {
        Panel(title: day.title, tag: tag) {
            Note(day.note)

            ForEach(day.items) { item in
                let isPyramid = item.key == "sa-pyramid"
                TickRow(
                    title: isPyramid ? Pyramid.itemName(state, on: activeDate) : item.name,
                    subtitle: isPyramid ? Pyramid.itemPrescription : item.prescription,
                    rir: item.rir,
                    isOn: canEdit && log.done.contains(item.key),
                    enabled: canEdit,
                    toggle: { store.toggleItem(item.key, on: activeDate) }
                ) {
                    if let liftID = item.liftID, liftID != "pyramid" {
                        LiftRow(liftID: liftID, item: item, canEdit: canEdit, activeDate: activeDate)
                    }
                }
            }

            if dow == 6 { PyramidPanel(state: state) }

            if let rest = day.restSeconds, canEdit {
                ActionButton(title: "Start rest timer · \(RestTimer.format(rest))") {
                    timer.start(seconds: rest)
                }
            }

            if canEdit {
                TextEditorField(text: $note, placeholder: "Notes for this session (optional)")
                    .onChange(of: note) { _, _ in
                        guard noteLoaded else { return }
                        scheduleNoteCommit()
                    }
            } else if !log.note.isEmpty {
                Note("Note: \(log.note)")
            }

            if dow != state.todayDow && editingDate == nil {
                ActionButton(title: "Back to today", action: onBackToToday)
            }
        }
        .onAppear { load() }
        .onChange(of: activeDate) { old, _ in
            debouncer.flush { flushNote(for: old) }
            load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { debouncer.flush { flushNote(for: activeDate) } }
        }
        .onDisappear { debouncer.flush { flushNote(for: activeDate) } }
    }

    private func load() {
        noteLoaded = false
        note = state.day(activeDate).note
        noteLoadedFor = activeDate
        noteLoaded = true
    }

    private func scheduleNoteCommit() {
        let date = activeDate
        debouncer.schedule { flushNote(for: date) }
    }

    private func flushNote(for date: String) {
        guard noteLoadedFor == date else { return }
        store.setNote(note, on: date)
    }

    private var tag: String {
        if let editingDate { return String(editingDate.dropFirst(5)) }
        if canEdit { return "today · \(day.tag)" }
        return "\(day.label) · preview"
    }
}

/// The per-set inputs under a lift.
///
/// The text fields bind to local state rather than straight through to the
/// store: a CloudKit push landing mid-set re-materialises the whole snapshot,
/// and a field bound to that would lose what is half-typed in it.
private struct LiftRow: View {
    var liftID: String
    var item: Exercise
    var canEdit: Bool
    var activeDate: String

    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var drafts: [DraftSet] = []
    @State private var loadedFor = ""
    @State private var debouncer = Debouncer()

    struct DraftSet: Identifiable, Equatable {
        let id = UUID()
        var kg = ""
        var reps = ""
    }

    private var state: LogState { store.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canEdit {
                ForEach(drafts.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 12)
                        numberField("kg", text: $drafts[index].kg)
                        Text("×").foregroundStyle(Theme.muted)
                        numberField("reps", text: $drafts[index].reps)
                    }
                }
                if drafts.count < Lifts.maxSets {
                    Button { drafts.append(DraftSet()) } label: {
                        Text("+ set")
                            .font(Theme.mono(10, weight: .bold))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }

                if let target = Lifts.nextTarget(state, id: liftID, on: activeDate,
                                                 prescription: item.prescription) {
                    Text("→ \(target.text)")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.amber)
                    if item.isBarbell, let plates = platesText(target) {
                        Text(plates)
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }

            Text(Lifts.reference(state, id: liftID, on: activeDate))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { load() }
        .onChange(of: activeDate) { old, _ in
            // Whatever was pending for the day being left has to land before
            // switching — `flush`'s own `loadedFor == date` guard would
            // otherwise silently drop it, since `activeDate` here is already
            // the new value by the time this fires, which is exactly why the
            // old one is passed in explicitly rather than read fresh.
            debouncer.flush { flush(for: old) }
            load()
        }
        .onChange(of: drafts) { _, _ in scheduleCommit() }
        .onChange(of: scenePhase) { _, phase in
            // A rep count typed and immediately followed by backgrounding the
            // app — switching to a stopwatch mid-set is a real gym habit, not
            // an edge case — must not lose the debounce window it was sitting
            // in when the app was suspended.
            if phase != .active { debouncer.flush { flush(for: activeDate) } }
        }
        .onDisappear { debouncer.flush { flush(for: activeDate) } }
    }

    private func numberField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(placeholder == "kg" ? .decimalPad : .numberPad)
            .font(Theme.mono(14))
            .foregroundStyle(Theme.bone)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 74)
            .padding(.vertical, 8)
            .background(Theme.raise, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
    }

    private func platesText(_ target: Lifts.Target) -> String? {
        let working = drafts.compactMap { Double($0.kg.replacingOccurrences(of: ",", with: ".")) }.first
            ?? target.kg
        guard let working, let plates = Lifts.platesFor(total: working, bar: state.barKg) else { return nil }
        return "\(Lifts.fmt(working)) kg = \(Lifts.fmt(state.barKg)) bar + \(plates) per side"
    }

    private func load() {
        guard loadedFor != activeDate else { return }
        loadedFor = activeDate
        let existing = state.liftHistory(liftID).first { $0.date == activeDate }?.sets ?? []
        drafts = existing.isEmpty
            ? [DraftSet()]
            : existing.map { DraftSet(kg: $0.kg.map(Lifts.fmt) ?? "", reps: String($0.reps)) }
    }

    /// Local `drafts` already updated the instant the keystroke landed —
    /// this only delays when that becomes a store mutation, so typing stays
    /// responsive while the expensive part happens once per pause rather
    /// than once per key.
    private func scheduleCommit() {
        let date = activeDate
        debouncer.schedule { flush(for: date) }
    }

    /// The actual write, for a specific date rather than reading `activeDate`
    /// fresh — the caller may be flushing a day that's no longer the active
    /// one (switching away, or the app backgrounding) and has to name which
    /// day's edit it's rescuing.
    private func flush(for date: String) {
        guard loadedFor == date else { return }
        let sets = drafts.compactMap { draft -> LiftSet? in
            guard let reps = Int(draft.reps), reps > 0 else { return nil }
            let kg = Double(draft.kg.replacingOccurrences(of: ",", with: "."))
            return LiftSet(kg: (kg ?? 0) > 0 ? kg : nil, reps: reps)
        }
        store.setSets(sets, liftID: liftID, on: date)
    }
}

// MARK: - Pyramid

private struct PyramidPanel: View {
    var state: LogState
    @Environment(AppStore.self) private var store

    var body: some View {
        let cap = state.pyramidCap
        let totals = Pyramid.totals(cap: cap)
        let climbing = cap < Pyramid.vestFromCap
        let vestWeek = Pyramid.isVestWeek(state)
        let vest = Pyramid.vestKg(state)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ActionButton(title: "– round") { store.adjustPyramidCap(by: -1) }
                ActionButton(title: "+ round") { store.adjustPyramidCap(by: 1) }
                PTag("cap \(cap)")
            }

            Note("Rounds 1–\(cap) adds up to " +
                 totals.parts.map { "\($0.reps) \($0.name)" }.joined(separator: " · ") +
                 " — \(totals.total) reps." +
                 (cap < Pyramid.maxCap ? " One more round makes it \(Pyramid.totals(cap: cap + 1).total)." : ""))

            HStack {
                PTag(climbing ? "climbing" : vestWeek ? "vest week" : "bodyweight week",
                     tint: vestWeek ? Theme.amber : Theme.muted)
                if climbing {
                    PTag("vest starts at cap \(Pyramid.vestFromCap)")
                } else if vestWeek {
                    ActionButton(title: "–") { store.adjustVest(by: -0.5) }
                    Text(vest.map { String(format: "%.1f kg", $0) } ?? "– kg")
                        .font(Theme.mono(13, weight: .bold))
                        .foregroundStyle(Theme.bone)
                    ActionButton(title: "+") { store.adjustVest(by: 0.5) }
                    if state.vestKg != nil {
                        ActionButton(title: "auto") { store.resetVestToAuto() }
                    }
                } else {
                    PTag("next week: \(vest.map { String(format: "%.1f kg", $0) } ?? "–")")
                }
                if !climbing {
                    ActionButton(title: "swap") { store.swapVestWeek() }
                }
            }

            Note(climbing
                ? "Set the cap to the round you can actually finish — that is what it is for, not a target you are failing. Add a round once \(cap) goes through cleanly. The vest stays off until cap \(Pyramid.vestFromCap), because until then adding a round is the cheaper way to progress."
                : vestWeek
                ? "Same \(cap) rounds as last week, wearing the vest — that is this week's progression. Add the round next week instead. Use swap if the vest lands on the wrong week."
                : "Add a round if last week's \(cap) moved well. Next week is the same cap with the vest on. Use swap if the vest lands on the wrong week.")

            if !state.pyramidLog.isEmpty {
                Note("Recent pyramids: " + state.pyramidLog.keys.sorted().suffix(6).reversed()
                    .map { date in
                        let entry = state.pyramidLog[date]
                        return "\(String(date.dropFirst(5))) cap \(entry?.cap ?? 0)" +
                            ((entry?.vestKg).map { " +\(Lifts.fmt($0))kg" } ?? "")
                    }
                    .joined(separator: " · "))
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Body weight

private struct WeightPanel: View {
    var state: LogState
    @Environment(AppStore.self) private var store

    var body: some View {
        Panel(title: "Body weight", tag: "7-day average") {
            BigStat(value: state.latestAverage.map { String(format: "%.1f", $0) } ?? "–", unit: "kg")
            VerdictLine(text: Trend.verdictText(state), tone: Trend.verdict(state))
            Sparkline(values: state.sortedWeights.suffix(30).map(\.kg))
            EntryField(placeholder: "waist, cm (weekly)", buttonTitle: "Log", prominent: false) { text in
                guard let cm = Double(text.replacingOccurrences(of: ",", with: ".")),
                      cm >= 50, cm <= 150 else { return false }
                store.logWaist(cm: cm, on: state.today)
                return true
            }
            Note("""
                Weigh in every morning, same conditions. Judge the weekly average, never a single day. \
                Waist once a week, relaxed, at the navel — scale up with the waist flat is the bulk \
                working; both climbing together means trim the surplus.
                """)
        }
    }
}

// MARK: - Fuel

private struct FuelPanel: View {
    var state: LogState
    var dow: Int
    var canEdit: Bool
    var activeDate: String
    @Environment(AppStore.self) private var store

    var body: some View {
        let fuel = Fuel.targets(state, dow: dow)
        Panel(title: "Fuel", tag: fuel.isRestDay ? "rest day" : "training day") {
            MacroGrid(items: [
                .init(value: "\(fuel.calories)", label: "kcal"),
                .init(value: "\(fuel.protein)", label: "protein"),
                .init(value: "\(fuel.carbs)", label: "carbs"),
                .init(value: "\(fuel.fat)", label: "fat"),
            ])

            if canEdit {
                TickRow(title: "Hit calories and protein today",
                        subtitle: "90% of days beats a perfect plan you drop in October",
                        isOn: state.day(activeDate).fuelHit,
                        toggle: { store.toggleFuel(on: activeDate) })
            }

            Reveal(title: "Meal template") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Plan.meals) { meal in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(meal.heading)
                                    .font(Theme.body(13, weight: .bold))
                                    .foregroundStyle(Theme.bone)
                                Text(meal.kcal)
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.muted)
                            }
                            Note(meal.detail)
                        }
                    }
                    Note("Magerquark: 500g tub ≈ 60g protein for about €1.")
                }
            }

            Reveal(title: "Where this number comes from") {
                if let bmr = fuel.basis.bmr, let tdee = fuel.basis.tdee,
                   let kg = fuel.basis.kg, let cm = fuel.basis.cm, let age = fuel.basis.age,
                   let multiplier = fuel.basis.multiplier {
                    Note("""
                        Resting burn \(Int(bmr.rounded())) kcal (Mifflin-St Jeor from \
                        \(String(format: "%.1f", kg)) kg, \(cm) cm, age \(age)) × \(Lifts.fmt(multiplier)) for \
                        \(fuel.isRestDay ? "a rest day" : "a training day") = \(tdee) kcal maintenance. Plus \
                        \(Fuel.surplus) kcal of surplus\(state.calAdjust != 0 ? ", plus your \(state.calAdjust > 0 ? "+" : "")\(state.calAdjust) adjustment" : "").
                        """)
                    Note("""
                        Every formula for this is roughly ±10% — wider than the surplus itself. Treat it as \
                        the opening bid and let the 28-day trend settle the argument.
                        """)
                } else {
                    Note("""
                        Using the plan's default targets. Set your height and year of birth in Setup and this \
                        is calculated from your bodyweight instead, so it keeps up as you gain.
                        """)
                }
            }

            HStack {
                ActionButton(title: "– 100 kcal") { store.adjustCalories(by: -100) }
                ActionButton(title: "+ 100 kcal") { store.adjustCalories(by: 100) }
                PTag("adjust \(state.calAdjust > 0 ? "+" : "")\(state.calAdjust)")
            }

            if let kind = TimeOff.today(state) {
                Note(kind == .ill
                    ? "Appetite goes first when you are ill and forcing the surplus back down is not the win here. Protein and fluids are what matter; the number can wait until you are eating normally again."
                    : "Eat like you are on holiday. A week of it moves the 28-day average by less than one bad weigh-in day, and none of these days are being scored anyway.",
                     dimmed: true)
            } else if Trend.verdict(state) == .slow {
                HStack {
                    PTag("trend is below target", tint: Theme.amber)
                    ActionButton(title: "Apply + \(Fuel.calorieStep) kcal", prominent: true) {
                        store.adjustCalories(by: Fuel.calorieStep)
                    }
                }
            }
        }
    }
}

// MARK: - Mobility

private struct MobilityPanel: View {
    var state: LogState
    var canEdit: Bool
    var activeDate: String
    @Environment(AppStore.self) private var store

    var body: some View {
        Panel(title: "Mobility", tag: "daily · 5–10 min") {
            ForEach(Plan.mobility) { drill in
                TickRow(title: drill.name,
                        subtitle: drill.prescription,
                        isOn: canEdit && state.day(activeDate).mobility.contains(drill.key),
                        enabled: canEdit,
                        toggle: { store.toggleMobility(drill.key, on: activeDate) })
            }
        }
    }
}

// MARK: - Shared bits

/// A multiline note field that looks like the rest of the inputs.
struct TextEditorField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(Theme.body(13))
                .foregroundStyle(Theme.bone)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minHeight: 64)
        }
        .background(Theme.raise, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
    }
}

private struct BackfillSheet: View {
    @Binding var selection: Date
    var onPick: (Date) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Back-fill a past day")
                .font(Theme.display(22))
                .foregroundStyle(Theme.bone)
            Note("Edits that day's checklist and lifts directly, instead of losing the session.")
            DatePicker("", selection: $selection, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
            ActionButton(title: "Edit that day", prominent: true) { onPick(selection) }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.ink)
    }
}
