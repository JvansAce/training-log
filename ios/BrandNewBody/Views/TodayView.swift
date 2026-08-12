import SwiftUI
import UIKit

/// Reordered around one question: what does opening this screen at 6am in
/// the gym actually need to happen fast?
///
/// The old order was housekeeping first — a weigh-in field, a recovery
/// panel, a full weight chart with its own waist input — and the actual
/// session, the reason the app is open at all, sixth. It's second now.
/// Weight and recovery collapse into one glanceable strip instead of two
/// full panels each with their own header and chrome, and the full weight
/// story — the chart, the trend explanation, editing old weigh-ins — lives
/// on Progress now and only there; Today shows the one line of it that's
/// actionable this morning (the verdict) and nothing else, because
/// re-litigating the whole trend on every single visit was the single
/// biggest thing standing between opening the app and starting the workout.
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
    @AppStorage(TodaySectionOrderStore.key) private var sectionOrderRaw = TodaySectionOrderStore.defaultRaw

    private var state: LogState { store.state }
    private var sectionOrder: [TodaySection] { TodaySectionOrderStore.load(from: sectionOrderRaw) }
    private var viewingDow: Int { viewing ?? state.todayDow }
    /// Only today, or an explicitly back-filled day, can be written to.
    private var canEdit: Bool { editingDate != nil || viewingDow == state.todayDow }
    private var activeDate: String { editingDate ?? state.today }
    private var isViewingToday: Bool { editingDate == nil && viewing == nil }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            TodayHero(state: state, viewing: viewingDow) { viewing = $0; editingDate = nil }

            backfillRow

            OffPanel(state: state, editing: editingDate != nil)
            DeloadPanel(state: state, editing: editingDate != nil)

            // Vitals, the session, Fuel and Mobility render in whatever
            // order Setup → Today's order last saved — see
            // TodaySectionOrder.swift. Nothing else on the page is
            // reorderable: the hero, the backfill row and the time-off/
            // deload banners are contextual chrome, not content someone
            // would want to drag around.
            ForEach(sectionOrder) { section in
                sectionView(section)
            }

            if editingDate == nil && TimeOff.today(state) == nil {
                OffControl(state: state)
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: TodaySection) -> some View {
        switch section {
        case .vitals:
            if isViewingToday { VitalsRow(state: state) }
        case .session:
            SessionPanel(state: state, dow: viewingDow, canEdit: canEdit,
                         activeDate: activeDate, editingDate: editingDate,
                         showWorkoutBanner: isViewingToday,
                         onBackToToday: { viewing = nil; editingDate = nil })
        case .fuel:
            FuelPanel(state: state, dow: viewingDow, canEdit: canEdit, activeDate: activeDate)
        case .mobility:
            MobilityPanel(state: state, canEdit: canEdit, activeDate: activeDate, dow: viewingDow)
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
                BackfillSheet(selection: $backfillDate,
                              note: "Edits that day's checklist and lifts directly, instead of losing the session.") { date in
                    editingDate = DateKit.key(date)
                    viewing = DateKit.dow(date)
                    showBackfillPicker = false
                }
                // A fixed 360pt used to clip this: the title, note and
                // "Edit that day" button all got pushed out of the visible
                // sheet by the graphical calendar alone, which wants more
                // than that on its own — leaving no way to confirm a date.
                // `.medium`/`.large` size to the actual content instead.
                .presentationDetents([.medium, .large])
            }
        }
    }
}

// MARK: - Hero

/// Today's actual headline: how much of it is done, not a subtle fill
/// creeping up inside a small rib that was easy to miss entirely. The
/// weekday strip is secondary now — navigation, not the main event — so it's
/// smaller and plainer than the number above it.
private struct TodayHero: View {
    var state: LogState
    var viewing: Int
    var onSelect: (Int) -> Void

    private var todayItems: [Exercise] { Plan.day(state.todayDow).items }
    private var doneCount: Int { min(state.day(state.today).done.count, todayItems.count) }
    private var totalCount: Int { todayItems.count }
    private var fraction: Double { totalCount > 0 ? Double(doneCount) / Double(totalCount) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(doneCount)")
                    .font(Theme.display(44))
                    .foregroundStyle(Theme.bone)
                Text("of \(totalCount) done today")
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }

            Capsule()
                .fill(Theme.raise)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(Theme.red)
                            .frame(width: geo.size.width * fraction)
                    }
                }

            HStack(spacing: 4) {
                ForEach(Plan.order, id: \.self) { dow in
                    let day = Plan.day(dow)
                    let isToday = dow == state.todayDow
                    let isViewing = dow == viewing
                    Button { onSelect(dow) } label: {
                        VStack(spacing: 5) {
                            Text(day.label)
                                .font(Theme.mono(10, weight: isToday ? .bold : .regular))
                                .foregroundStyle(isViewing ? Theme.bone : Theme.muted)
                            Circle()
                                .fill(day.color.opacity(isViewing ? 1 : 0.4))
                                .frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isViewing ? Theme.raise : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.label), \(day.title)")
                    .accessibilityAddTraits(isViewing ? [.isSelected] : [])
                }
            }
        }
    }
}

// MARK: - Vitals

/// Weight and recovery, merged into one glanceable strip instead of two full
/// panels. Both used to be a whole `Panel` each — header, chrome, an
/// always-visible input field with its own button — stacked one above the
/// other before the actual workout ever appeared on screen. This is the
/// two numbers that matter for a two-second glance, with everything else —
/// the actual entry fields, WHOOP's fuller breakdown — one tap away rather
/// than permanently on screen.
private struct VitalsRow: View {
    var state: LogState
    @Environment(AppStore.self) private var store
    @Environment(WhoopClient.self) private var whoop

    private var todayWeight: WeightRecord? {
        state.weights.first { $0.date == state.today && !$0.seed }
    }
    private var recovery: RecoveryRecord? { state.recovery[state.today] }
    private var isWhoopConnected: Bool { whoop.status == .connected }
    private var recoveryValue: Int? { recovery?.recovery }

    var body: some View {
        Panel(title: "Vitals", tag: nil) {
            HStack(spacing: 0) {
                stat(value: todayWeight.map { String(format: "%.1f", $0.kg) } ?? "–",
                     unit: "kg", label: "weight",
                     tint: todayWeight != nil ? Theme.bone : Theme.muted)
                Rectangle().fill(Theme.line).frame(width: 1, height: 32)
                stat(value: recoveryValue.map(String.init) ?? "–",
                     unit: "%", label: "recovery", tint: recoveryTint)
            }

            VerdictLine(text: Trend.verdictText(state), tone: Trend.verdict(state))
            Sparkline(values: state.sortedWeights.suffix(30).map(\.kg))

            if let recoveryValue, recoveryValue < Deload.redRecovery {
                Note("""
                    Recovery is red today. If today's session has any give in it — Thursday's cardio, the \
                    pyramid — this is the day to take it.
                    """)
            }

            if isWhoopConnected, whoop.today != nil {
                Reveal(title: "Strain, sleep, HRV") {
                    HStack(spacing: 18) {
                        miniStat(recovery?.strain.map { String(format: "%.1f", $0) } ?? "–", "strain")
                        miniStat(recovery?.sleepPct.map { "\($0)%" } ?? "–", "sleep")
                        miniStat(recovery?.hrvMs.map { "\(Int($0.rounded()))" } ?? "–", "hrv ms")
                        miniStat(recovery?.restingHR.map { "\($0)" } ?? "–", "rhr")
                    }
                }
            }

            Reveal(title: "Log today's numbers") {
                VStack(alignment: .leading, spacing: 10) {
                    EntryField(
                        placeholder: todayWeight == nil ? "this morning, kg" : "change this morning, kg",
                        buttonTitle: todayWeight == nil ? "Log" : "Update",
                        prominent: todayWeight == nil
                    ) { text in
                        guard let kg = Double(text.replacingOccurrences(of: ",", with: ".")),
                              kg >= 40, kg <= 200 else { return false }
                        store.logWeight(kg: kg, on: state.today)
                        return true
                    }
                    if !isWhoopConnected {
                        EntryField(placeholder: "recovery %, if you don't", buttonTitle: "Log",
                                   prominent: false, keyboard: .numberPad) { text in
                            guard let value = Int(text), (0...100).contains(value) else { return false }
                            store.setRecovery(value, on: state.today)
                            return true
                        }
                        if let recoveryValue {
                            HStack {
                                PTag("logged \(recoveryValue)%")
                                ActionButton(title: "Clear") { store.setRecovery(nil, on: state.today) }
                            }
                        }
                    }
                    EntryField(placeholder: "waist, cm (weekly)", buttonTitle: "Log", prominent: false) { text in
                        guard let cm = Double(text.replacingOccurrences(of: ",", with: ".")),
                              cm >= 50, cm <= 150 else { return false }
                        store.logWaist(cm: cm, on: state.today)
                        return true
                    }
                    if !isWhoopConnected {
                        if case .notConnected(let reason) = whoop.status, let reason {
                            Note(reason, dimmed: true)
                        }
                        ActionButton(title: "Connect WHOOP") { whoop.connect() }
                    }
                }
            }
        }
    }

    private var recoveryTint: Color {
        guard let recoveryValue else { return Theme.muted }
        return recoveryValue < Deload.redRecovery ? Theme.red : Theme.bone
    }

    private func stat(value: String, unit: String, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(Theme.display(26)).foregroundStyle(tint)
                Text(unit).font(Theme.mono(11)).foregroundStyle(Theme.muted)
            }
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            Text(label.uppercased())
                .font(Theme.mono(9)).tracking(1).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.mono(14, weight: .bold)).foregroundStyle(Theme.bone)
            Text(label).font(Theme.mono(9)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
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
                        Halve the sets. Keep the weight. Stop every set 3–4 reps short of failure. Same \
                        exercises, same loads, roughly half the work and none of it taken close to the \
                        limit — cutting volume and effort rather than intensity is what keeps the strength \
                        while the fatigue clears. The pyramid drops one round and skips the vest this week \
                        rather than being skipped outright — it's conditioning, and it scales down with \
                        everything else instead of dropping to zero. Tennis and the Thursday walk are fine.
                        """)
                    HStack {
                        ActionButton(title: "End it early") { store.endDeloadEarly() }
                        if let started = Deload.lastDeload(state) { PTag("started \(started)") }
                    }
                }
            } else if let signal = Deload.signal(state) {
                Panel(title: "Take a deload", tag: deloadTag(signal.kind)) {
                    VerdictLine(text: "\(signal.reason) That's the signal to back off for a week.",
                                tone: .fast)
                    Note("""
                        A deload here is half the sets at the same weight, stopped 3–4 reps short, and the \
                        pyramid a round lighter with no vest. It is one week. The alternative is grinding \
                        through it and losing the next three.
                        """)
                    HStack {
                        ActionButton(title: "Start a deload week", prominent: true) { store.startDeload() }
                        ActionButton(title: "Not now") { store.snoozeDeload() }
                    }
                }
            }
        }
    }

    private func deloadTag(_ kind: Deload.SignalKind) -> String {
        switch kind {
        case .recovery: return "recovery is asking"
        case .performance: return "numbers are slipping"
        case .calendar: return "due on the calendar"
        }
    }
}

// MARK: - Session

private struct SessionPanel: View {
    var state: LogState
    var dow: Int
    var canEdit: Bool
    var activeDate: String
    var editingDate: String?
    /// Only true when this panel is showing today's own session, not a
    /// preview of another weekday or a back-filled past one — a detected
    /// workout is inherently today's, so the banner only ever makes sense
    /// here.
    var showWorkoutBanner: Bool
    var onBackToToday: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(RestTimer.self) private var timer
    @Environment(WhoopClient.self) private var whoop
    @Environment(\.scenePhase) private var scenePhase
    @State private var note = ""
    @State private var noteLoaded = false
    @State private var noteLoadedFor = ""
    @State private var debouncer = Debouncer()
    /// Whether the checklist is tidied away behind its "all ticked" summary.
    /// Decided once per date rather than tracked live — see `syncCollapse`.
    @State private var collapsed = false
    @State private var collapsedFor = ""
    /// Transient — just long enough to confirm the copy landed.
    @State private var copiedExport = false

    private var day: TrainingDay { Plan.day(dow) }
    private var log: DayRecord { state.day(activeDate) }

    /// Counted over *this* day's own keys, never `log.done.count`. A Tuesday
    /// with eight ticks previewing Friday's six items would otherwise read as
    /// complete, because the count would be comparing today's tally against a
    /// different day's list.
    private var doneCount: Int { day.items.filter { log.done.contains($0.key) }.count }
    private var isComplete: Bool { !day.items.isEmpty && doneCount == day.items.count }

    var body: some View {
        Panel(title: day.title, tag: tag) {
            Note(day.note)

            if showWorkoutBanner, let workouts = whoop.today?.workouts, !workouts.isEmpty {
                workoutBanner(workouts)
            }

            if collapsed {
                completedSummary
            } else {
                ForEach(day.items) { item in
                    let isPyramid = item.key == "sa-pyramid"
                    TickRow(
                        title: isPyramid ? Pyramid.itemName(state, on: activeDate) : item.displayName(state),
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

                // Offered only once it's all ticked, so it never reads as a way
                // to hide work still to do.
                if isComplete, canEdit {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { collapsed = true }
                    } label: {
                        Text("Tidy this away")
                            .font(Theme.mono(10, weight: .bold))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Outside the collapse branch on purpose: it summarises the whole
            // session, so it stays reachable once the checklist is tidied away.
            // Only offered on a day you could edit — in a preview of another
            // weekday `activeDate` is still today, and a Copy button sitting
            // under Friday's plan that copies Tuesday's lifts is a trap.
            if canEdit, let export = SessionExport.text(state, on: activeDate) {
                ActionButton(title: copiedExport ? "Copied ✓" : "Copy for WHOOP") {
                    UIPasteboard.general.string = export
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    copiedExport = true
                    // Explicitly main-actor: this touches `@State` after an
                    // await, and a bare Task inherits no isolation.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1600))
                        copiedExport = false
                    }
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
        .onAppear { load(); syncCollapse() }
        .onChange(of: activeDate) { old, _ in
            debouncer.flush { flushNote(for: old) }
            load()
            syncCollapse()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { debouncer.flush { flushNote(for: activeDate) } }
        }
        .onDisappear { debouncer.flush { flushNote(for: activeDate) } }
    }

    /// The soft lock. Nothing is disabled and nothing is hidden that can't be
    /// got back in one tap — a finished session simply stops occupying the
    /// screen it was occupying while you were still working through it. The
    /// row is the tap target, and it says "edit" rather than showing a lock,
    /// because that is what tapping it does.
    private var completedSummary: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { collapsed = false }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All \(day.items.count) ticked")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.bone)
                    Text("logged sets and notes are kept")
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Text("EDIT")
                    .font(Theme.mono(9.5))
                    .tracking(1.2)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Session complete, all \(day.items.count) items ticked. Activate to edit.")
    }

    /// Collapsed state is decided when the day is opened, never live off
    /// `isComplete`. Ticking the last box mid-session must not fold the
    /// checklist away underneath you — the sets for that last exercise are
    /// usually typed *after* its box goes green. So finishing a session leaves
    /// it open, and it is tidy the next time you come back to it.
    private func syncCollapse() {
        guard collapsedFor != activeDate else { return }
        collapsedFor = activeDate
        collapsed = isComplete
    }

    private func workoutBanner(_ workouts: [DetectedWorkout]) -> some View {
        let complete = isComplete
        return VStack(alignment: .leading, spacing: 8) {
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
        .padding(10)
        .background(Theme.raise, in: RoundedRectangle(cornerRadius: 10))
    }

    private func markTodayComplete() {
        // Explicit tap rather than auto-ticking on detection, matching the
        // web app's reasoning exactly: WHOOP knows you trained, it doesn't
        // know which items on the checklist you actually did.
        for item in day.items where !log.done.contains(item.key) {
            store.toggleItem(item.key, on: activeDate)
        }
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
        if let editingDate {
            return String(editingDate.dropFirst(5)) + (isComplete ? " · complete" : "")
        }
        // "complete" replaces the rest-time hint rather than joining it: the
        // hint is guidance for work still to do, and `day.tag` is long enough
        // that appending to it would wrap the panel header.
        if canEdit { return isComplete ? "today · complete" : "today · \(day.tag)" }
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

    /// The most recent session that isn't the one being edited — what "last
    /// time" means, per set position.
    private var previousSets: [LiftSet] {
        state.liftHistory(liftID).last { $0.date != activeDate }?.sets ?? []
    }

    /// How many rows to put on screen before anything has been typed.
    ///
    /// The prescription is the source of truth it already is everywhere else:
    /// "4 × 4–6" means four rows standing ready, not one row and three taps
    /// of "+ set" between sets with a bar in your hands. Reads the set count
    /// via `prescribedSets` rather than `parseScheme`, so "3 × max reps" —
    /// which has no rep range to parse and so no progression target — still
    /// correctly stands up three rows. Anything that names no count at all
    /// falls back to however many sets the last session actually had.
    private var targetRowCount: Int {
        let prescribed = Lifts.prescribedSets(item.prescription)
        let fallback = previousSets.isEmpty ? 1 : previousSets.count
        return min(Lifts.maxSets, max(1, prescribed ?? fallback))
    }

    private func previousKg(_ index: Int) -> String? {
        guard index < previousSets.count, let kg = previousSets[index].kg, kg != 0 else { return nil }
        return Lifts.fmt(kg)
    }

    private func previousReps(_ index: Int) -> String? {
        guard index < previousSets.count else { return nil }
        return String(previousSets[index].reps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canEdit {
                ForEach(drafts.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 12)
                        numberField("kg", text: $drafts[index].kg, hint: previousKg(index))
                        if item.isBodyweight { signToggle(index) }
                        Text("×").foregroundStyle(Theme.muted)
                        numberField("reps", text: $drafts[index].reps, hint: previousReps(index))
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
                // Nobody guesses that a weight field takes a negative, so say
                // it once — on the lifts where it applies, and only until
                // there is history proving it landed.
                if item.isBodyweight, state.liftHistory(liftID).isEmpty {
                    Text("band or machine helping? tap ± and log the help as a minus")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
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

    /// `hint` is last session's number for this set position, shown as the
    /// field's own placeholder rather than as a separate label beside it: it
    /// costs no width, it sits exactly where the thumb and the eye already
    /// are, and it clears itself the moment you type — so a row you've
    /// filled reads as your number and an empty one reads as the number to
    /// beat. `kind` still decides the keypad, which is why it stays separate
    /// from whatever ends up displayed.
    private func numberField(_ kind: String, text: Binding<String>, hint: String?) -> some View {
        TextField(hint ?? kind, text: text)
            .keyboardType(kind == "kg" ? .decimalPad : .numberPad)
            .font(Theme.mono(14))
            .foregroundStyle(Theme.bone)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 74)
            .padding(.vertical, 8)
            .background(Theme.raise, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
    }

    /// The decimal keypad has no minus key, so assistance needs a way in of
    /// its own. This flips the sign of whatever is in the field — including an
    /// empty one, so it can be tapped first and the number typed after.
    private func signToggle(_ index: Int) -> some View {
        let negative = drafts[index].kg.hasPrefix("-")
        return Button {
            if negative { drafts[index].kg.removeFirst() }
            else { drafts[index].kg = "-" + drafts[index].kg }
        } label: {
            Text("±")
                .font(Theme.mono(13, weight: .bold))
                .foregroundStyle(negative ? Theme.amber : Theme.muted)
                .frame(width: 30, height: 34)
                .background(Theme.raise, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(negative ? Theme.amber : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(negative ? "Assisted, tap for added weight" : "Added weight, tap for assistance")
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
        var rows = existing.map { DraftSet(kg: $0.kg.map(Lifts.fmt) ?? "", reps: String($0.reps)) }
        // Pad out to the prescribed count so every set is already on screen.
        // Blank rows never become logged sets: `flush` drops any position that
        // doesn't parse and has nothing already saved behind it, which is the
        // same guard that stops a half-retyped rep count from deleting a set.
        // Never truncates either — five sets logged against a prescription of
        // three keeps all five.
        while rows.count < targetRowCount { rows.append(DraftSet()) }
        drafts = rows
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
    ///
    /// `setSets` fully replaces whatever was stored, so reconstructing the
    /// array straight from `drafts` would delete a set the moment its reps
    /// field is momentarily blank — which is exactly what backspacing to
    /// retype a number looks like mid-keystroke. A forced flush (backgrounding,
    /// switching days) can land in that exact gap, and the debounce alone
    /// doesn't protect against it since it's bypassed on purpose for those
    /// cases. Falling back to whatever this position already held keeps a
    /// half-retyped set intact instead of silently dropping it; only a
    /// position with nothing behind it yet — a fresh, still-blank `+ set` row —
    /// is safe to drop, because there is nothing there to lose.
    private func flush(for date: String) {
        guard loadedFor == date else { return }
        let existing = state.liftHistory(liftID).first { $0.date == date }?.sets ?? []
        let sets = drafts.enumerated().compactMap { index, draft -> LiftSet? in
            if let reps = Int(draft.reps), reps > 0 {
                // Zero and nil both mean bodyweight — a stored 0 would read as
                // "0 kg × 8" and drag a meaningless point through the e1RM
                // maths. A negative is assistance, and only means anything on
                // a lift whose base load is the body.
                let typed = Double(draft.kg.replacingOccurrences(of: ",", with: ".")) ?? 0
                let load = item.isBodyweight ? typed : max(typed, 0)
                return LiftSet(kg: load == 0 ? nil : load, reps: reps)
            }
            return index < existing.count ? existing[index] : nil
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

            // Past a certain cap the pyramid is quietly supplying more pull and
            // push volume than the upper days prescribe, and every round added
            // raises it again. Reported as exact rep counts with the trade
            // named, rather than silently adjusting Tuesday and Friday: the
            // conversion from circuit reps to equivalent working sets is a
            // number nobody can defend, and a set removed without a visible
            // reason is worse than one you chose to remove.
            if cap >= Pyramid.overlapFromCap {
                Note("At cap \(cap) the pyramid alone adds " +
                     Pyramid.overlap(cap: cap).map { "\($0.reps) \($0.name)" }.joined(separator: " · ") +
                     " to the week, on top of everything Tuesday and Friday already prescribe. If pressing or pulling goes stale before the next round feels easy, take a set off dips or the row before you take a round off here — the pyramid is the part that is meant to keep climbing.")
            }

            // The +/– buttons above still move the persisted, climbing cap —
            // that's what they're for, and it has to keep working even
            // mid-deload so a back-fill later this week isn't stuck editing
            // the wrong number. What actually gets logged today is one round
            // lighter regardless; this just says so, since the ticked
            // checklist line already shows the reduced number without
            // explaining why it doesn't match the cap set here.
            if Pyramid.isDeloadedToday(state) {
                Note("""
                    Deload week: today's own pyramid logs at rounds 1–\(Pyramid.effectiveCap(state)) with no \
                    vest, regardless of the cap above — the climb picks back up where it left off once the \
                    week off ends.
                    """, dimmed: true)
            }
        }
        .padding(.top, 6)
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
    var dow: Int
    @Environment(AppStore.self) private var store

    /// Same soft lock as the session panel, and for the same reason: rows
    /// that are all ticked are rows of nothing left to do.
    @State private var collapsed = false
    @State private var collapsedFor = ""

    /// The fixed baseline plus, on a day whose lifting calls for it, one
    /// more — see `Plan.mobilityFocus`. Additive, so a day with no focus
    /// drill just falls back to exactly the baseline everyone always runs.
    private var drills: [Plan.Mobility] {
        guard let focus = Plan.mobilityFocus(dow: dow) else { return Plan.mobility }
        return Plan.mobility + [focus]
    }

    /// Gated on `canEdit` exactly as the rows are. Keyed by drill, not by
    /// count, so unlike the session panel this can't rely on a different
    /// weekday's keys being absent: previewing Friday on a Tuesday whose
    /// mobility is done would otherwise collapse to "all done" above rows
    /// that render unticked, because that is what a non-editable day shows.
    private var done: Set<String> { canEdit ? state.day(activeDate).mobility : [] }
    private var doneCount: Int { drills.filter { done.contains($0.key) }.count }
    private var isComplete: Bool { doneCount == drills.count }

    var body: some View {
        // Widened again with the balance drill and the ankle drill's
        // 5×30s/side dose — that one alone runs ~5 minutes on squat days, on
        // top of a now-five-item baseline, so the old "5–10" and even "5–12"
        // stopped being true on Wed/Sat specifically.
        Panel(title: "Mobility", tag: isComplete ? "all \(doneCount) done" : "daily · 8–15 min") {
            if collapsed {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { collapsed = false }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.green)
                        Text("All \(drills.count) drills done")
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.bone)
                        Spacer(minLength: 8)
                        Text("EDIT")
                            .font(Theme.mono(9.5))
                            .tracking(1.2)
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mobility complete, all \(drills.count) drills done. Activate to edit.")
            } else {
                // The last row is the day-specific one whenever there is
                // one, so it reads as "plus today" rather than being
                // shuffled in among the fixed baseline.
                ForEach(drills) { drill in
                    TickRow(title: drill.name,
                            subtitle: drill.prescription,
                            isOn: canEdit && done.contains(drill.key),
                            enabled: canEdit,
                            toggle: { store.toggleMobility(drill.key, on: activeDate) })
                }
                // Held stretches past ~60s/side measurably blunt the next
                // set's power output — real, dose-dependent, replicated —
                // so this reads better as a cooldown than a warm-up on a
                // lifting day. Daily isn't shown to beat 3–4×/week for
                // range of motion either; it just doesn't cost anything.
                Note("Best after training, not right before — a long held stretch can blunt the next set. Daily is fine, not required.")
                if drills.count > Plan.mobility.count {
                    Note("Today's extra drill matches what the day above demands — rotation on the tennis day, extension on the press days, ankle range on the squat days.")
                }
                if isComplete, canEdit {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { collapsed = true }
                    } label: {
                        Text("Tidy this away")
                            .font(Theme.mono(10, weight: .bold))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear(perform: syncCollapse)
        .onChange(of: activeDate) { _, _ in syncCollapse() }
    }

    /// Decided on entry, never live — ticking the last drill must not make
    /// the panel fold up under the thumb that just tapped it.
    private func syncCollapse() {
        guard collapsedFor != activeDate else { return }
        collapsedFor = activeDate
        collapsed = isComplete
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

/// Shared by both Body and Mind's "forgot to log a day?" flow — the picker
/// itself doesn't know which programme it's back-filling, only `note` does.
struct BackfillSheet: View {
    @Binding var selection: Date
    var note: String
    var onPick: (Date) -> Void

    var body: some View {
        // Scrollable so the confirm button below the calendar is always
        // reachable, even on a smaller screen or a `.medium` detent that
        // still can't fit everything at once — the fixed-height sheet this
        // replaced could clip it out entirely with no way to get to it.
        ScrollView {
            VStack(spacing: 16) {
                Text("Back-fill a past day")
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.bone)
                Note(note)
                DatePicker("", selection: $selection, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                ActionButton(title: "Edit that day", prominent: true) { onPick(selection) }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ink)
    }
}
