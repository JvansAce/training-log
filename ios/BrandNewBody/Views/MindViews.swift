import SwiftUI

// MARK: - Today

struct MindTodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(RestTimer.self) private var timer

    private var state: LogState { store.state }

    var body: some View {
        if state.mindStartDate == nil {
            Panel(title: "Brand New Mind", tag: "not started") {
                Note("""
                    The other half. Same idea as the training side — a fixed thing to do today, a load that \
                    climbs, and a Saturday session that is the hard one. The difference is it does not \
                    start with everything switched on: you begin with one practice, and the next of the \
                    \(MindPlan.practices.count) arrives when that one is sticking.
                    """)
                Note("""
                    First up is \(MindPlan.practices[0].name) — \(MindPlan.practices[0].why.lowercased()) \
                    Five minutes. A \(MindPlan.ladder.count)-rung ladder on Saturdays from day one, \
                    starting with eye contact and a smile.
                    """)
                ActionButton(title: "Start the programme", prominent: true) { store.startMind() }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                Panel(title: "Today",
                      tag: "\(Plan.dayNames[state.todayDow] ?? "") · week \(Mind.weeksIn(state) + 1)") {
                    Note(intro)
                    ForEach(Mind.activePractices(state)) { practice in
                        PracticeRow(practice: practice)
                    }
                }

                if Mind.isLadderDay(state) { LadderPanel() }
                if Mind.activePractices(state).contains(where: { $0.kind == .drill }) {
                    CharismaPanel()
                }
                UnlockPanel()
            }
        }
    }

    private var intro: String {
        let active = Mind.activePractices(state)
        if let kind = TimeOff.today(state) {
            return """
                Marked \(kind.rawValue) — none of this is owed today. Reading and journalling survive a \
                fever and a departure lounge better than squats do, so the list is still here if you want \
                it. Today is out of the adherence window either way: it will not count against you, and it \
                will not count for you.
                """
        }
        if active.count == 1 {
            return "One practice. Do it every day until it is boring, then the next one arrives."
        }
        return "\(active.count) practices. Tick what you did — a missed day is a missed day, not a reason to stop."
    }
}

private struct PracticeRow: View {
    var practice: MindPlan.Practice
    @Environment(AppStore.self) private var store
    @Environment(RestTimer.self) private var timer
    @Environment(\.scenePhase) private var scenePhase

    @State private var minutes = ""
    @State private var journal = ""
    @State private var loaded = false
    // Mind has no back-fill — every write here targets `state.today` — so
    // unlike the Body side's LiftRow and note field, these two debouncers
    // don't need to track which day a pending edit belongs to, only whether
    // there is one.
    @State private var minutesDebouncer = Debouncer()
    @State private var journalDebouncer = Debouncer()
    // Set only inside each field's own onChange, so flushing on disappear or
    // backgrounding — which happens on every visit, touched or not — doesn't
    // write back the exact value that was just loaded and call that a
    // mutation.
    @State private var minutesDirty = false
    @State private var journalDirty = false

    private var state: LogState { store.state }
    private var log: MindDayRecord { state.mindDay(state.today) }

    var body: some View {
        TickRow(title: practice.name,
                subtitle: subtitle,
                isOn: Mind.didPractice(state, practice, on: state.today),
                toggle: { store.toggleMindPractice(practice, on: state.today) }) {
            switch practice.kind {
            case .minutes:
                minutesDetail
            case .text:
                TextEditorField(text: $journal, placeholder: "Write it here — a few lines is plenty.")
                    .onChange(of: journal) { _, _ in
                        guard loaded else { return }
                        journalDirty = true
                        journalDebouncer.schedule { commitJournal() }
                    }
            default:
                EmptyView()
            }
        }
        .onAppear(perform: load)
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            minutesDebouncer.flush { commitMinutes() }
            journalDebouncer.flush { commitJournal() }
        }
        .onDisappear {
            minutesDebouncer.flush { commitMinutes() }
            journalDebouncer.flush { commitJournal() }
        }
    }

    private func commitMinutes() {
        guard minutesDirty else { return }
        minutesDirty = false
        store.setMindMinutes(Int(minutes), practice: practice.key, on: state.today)
    }

    private func commitJournal() {
        guard journalDirty else { return }
        journalDirty = false
        store.setJournal(journal, on: state.today)
    }

    @ViewBuilder
    private var minutesDetail: some View {
        let target = Mind.target(state, practice) ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("min", text: $minutes)
                    .keyboardType(.numberPad)
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.bone)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 70)
                    .padding(.vertical, 8)
                    .background(Theme.raise, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                    .onChange(of: minutes) { _, _ in
                        guard loaded else { return }
                        minutesDirty = true
                        minutesDebouncer.schedule { commitMinutes() }
                    }
                Text("of \(target)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
                if practice.hasTimer {
                    ActionButton(title: "Timer") { timer.start(seconds: target * 60) }
                }
            }
            if let next = Mind.nextTarget(state, practice) {
                Text(progressText(next))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func progressText(_ next: Mind.NextTarget) -> String {
        if next.capped { return "At the ceiling for this one. Hold it." }
        if next.ready { return "Earned it — next session goes to \(next.next) min" }
        if next.run > 0 {
            return "\(next.run)/\(next.need) sessions at \(next.at) min — \(next.need - next.run) more and it goes to \(next.next) min"
        }
        return "\(next.need) sessions at \(next.at) min and it goes to \(next.next) min"
    }

    private var subtitle: String {
        switch practice.kind {
        case .minutes:
            return "\(Mind.target(state, practice) ?? 0) min"
        case .text:
            return Mind.prompt(state)
        case .drill:
            let drill = Mind.charismaDrill(state)
            return "\(drill.name) — \(drill.how)"
        case .tick:
            return practice.key == "social" ? MindPlan.socialRep(dow: state.todayDow) : practice.why
        }
    }

    private func load() {
        guard !loaded else { return }
        minutes = log.mins[practice.key].map(String.init) ?? ""
        journal = log.journal
        loaded = true
    }
}

private struct LadderPanel: View {
    @Environment(AppStore.self) private var store
    private var state: LogState { store.state }

    var body: some View {
        let cap = state.mindLadderCap
        let rungs = Mind.ladderRungs(cap: cap)
        let done = state.mindDay(state.today).done
        let doneCount = rungs.indices.filter { done.contains("rung\($0 + 1)") }.count
        let atTop = cap >= MindPlan.ladder.count

        Panel(title: "The ladder", tag: "rungs 1–\(cap) · \(doneCount)/\(rungs.count)") {
            Note("""
                Saturday's session. Climb from the bottom every week — rung one is meant to be trivial, and \
                doing it first is what makes rung four possible. The cap goes up when you clear the whole \
                thing.
                """)
            ForEach(rungs.indices, id: \.self) { index in
                TickRow(title: "\(index + 1). \(rungs[index])",
                        isOn: done.contains("rung\(index + 1)"),
                        toggle: { store.toggleMindKey("rung\(index + 1)", on: state.today) })
            }
            HStack {
                ActionButton(title: "– rung", enabled: cap > 1) { store.adjustLadderCap(by: -1) }
                ActionButton(title: "+ rung", enabled: !atTop) { store.adjustLadderCap(by: 1) }
                PTag(atTop ? "top of the ladder" : "next: \(MindPlan.ladder[cap])")
            }
            if doneCount == rungs.count && !atTop {
                HStack {
                    PTag("cleared the whole ladder", tint: Theme.green)
                    ActionButton(title: "Add rung \(cap + 1)", prominent: true) {
                        store.adjustLadderCap(by: 1)
                    }
                }
            }
        }
    }
}

private struct CharismaPanel: View {
    @Environment(AppStore.self) private var store
    private var state: LogState { store.state }

    var body: some View {
        let drill = Mind.charismaDrill(state)
        let used = Mind.charismaUses(state)
        let index = state.charismaIx % MindPlan.charisma.count
        let lap = Mind.charismaLap(state)

        Panel(title: "Charisma",
              tag: "drill \(index + 1) of \(MindPlan.charisma.count)\(lap > 1 ? " · lap \(lap)" : "")") {
            StatRow {
                Text(drill.name)
                    .font(Theme.body(14, weight: .bold))
                    .foregroundStyle(Theme.bone)
            } trailing: {
                HStack(spacing: 4) {
                    Text("\(used)/\(MindPlan.charismaUsesNeeded)")
                        .font(Theme.mono(13, weight: .bold))
                        .foregroundStyle(Theme.bone)
                    if used >= MindPlan.charismaUsesNeeded {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.green)
                    }
                }
            }
            Note(drill.source)
            Note(used >= MindPlan.charismaUsesNeeded
                ? "Done with this one. The next drill is waiting next time you open the app."
                : "\(MindPlan.charismaUsesNeeded - used) more day\(MindPlan.charismaUsesNeeded - used == 1 ? "" : "s") using it and the next drill arrives. Tick it on the Today list when you actually used it — not when you meant to.")

            Reveal(title: "Why this works") {
                Note("""
                    It is trainable — that is a finding, not a slogan. Randomised trials taught people a \
                    fixed set of tactics and had observers rate them; the trained group's ratings for \
                    charisma and leadership went up around 60%. The catch is that trying to remember twelve \
                    techniques mid-conversation leaves you present for none of them. So: one at a time.
                    """)
            }
            Reveal(title: "The whole list") {
                VStack(spacing: 0) {
                    Note("""
                        Conversational first, then how you carry it, then the platform ones. After the \
                        last, it laps — these are drills, not achievements, and they fade.
                        """)
                    ForEach(Array(MindPlan.charisma.enumerated()), id: \.element.id) { position, item in
                        let isNow = position == index
                        let isDone = position < index || lap > 1
                        StatRow(dimmed: !isNow && !isDone) {
                            Text("\(position + 1). \(item.name)")
                                .font(Theme.body(13, weight: .semibold))
                                .foregroundStyle(Theme.bone)
                            Text(item.how)
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        } trailing: {
                            if isNow {
                                PTag("now", tint: Theme.green)
                            } else if isDone {
                                Text("done").font(Theme.mono(9.5)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
            HStack {
                ActionButton(title: "Skip to next drill") { store.skipCharismaDrill() }
                PTag("if this one does not apply to you")
            }
        }
    }
}

private struct UnlockPanel: View {
    @Environment(AppStore.self) private var store
    private var state: LogState { store.state }

    var body: some View {
        let active = Mind.activePractices(state)
        let weeks = Mind.weeksIn(state)

        if let next = Mind.nextPractice(state) {
            let due = Mind.unlockDue(state)
            Panel(title: "The programme",
                  tag: "\(active.count) of \(MindPlan.practices.count) · week \(weeks + 1)") {
                Note("""
                    One at a time, on purpose. \(MindPlan.practices.count) new habits starting the same \
                    Monday is how you end up with none of them.
                    """)
                StatRow {
                    Text("Next up: \(next.name)")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.bone)
                    Text(next.why)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } trailing: {
                    if weeks < next.week {
                        Text("earliest week \(next.week + 1)")
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.muted)
                    } else if due?.ready == true {
                        PTag("ready", tint: Theme.green)
                    } else {
                        Text("not yet").font(Theme.mono(9.5)).foregroundStyle(Theme.muted)
                    }
                }
                Note(unlockCopy(next: next, due: due, active: active.count, weeks: weeks))
                HStack {
                    ActionButton(title: "Add \(next.name) now", prominent: due?.ready == true) {
                        store.unlockNextPractice()
                    }
                    PTag(due?.ready == true ? "recommended" : "your call")
                }
            }
        } else {
            Panel(title: "The programme", tag: "all \(MindPlan.practices.count) running") {
                Note("""
                    Every practice is in. From here the load climbs rather than the list growing\
                    \(weeks >= MindPlan.addInWeek ? ", and the add-in pool below is open" : ", and the add-in pool opens at week \(MindPlan.addInWeek + 1)").
                    """)
                if weeks >= MindPlan.addInWeek {
                    Reveal(title: "Add-in pool") {
                        VStack(alignment: .leading, spacing: 8) {
                            Note("""
                                Pull one in when the core gets boring. Not tracked — deliberately. These \
                                are things to do, not more boxes to fail to tick.
                                """)
                            FlowChips(items: MindPlan.addIns, highlighted: nil)
                        }
                    }
                }
            }
        }
    }

    private func unlockCopy(next: MindPlan.Practice, due: Mind.Unlock?, active: Int, weeks: Int) -> String {
        guard let adherence = due?.adherence else {
            return "Log a few days and this will start tracking whether you are ready for the next one."
        }
        let percent = Int((adherence.rate * 100).rounded())
        let tail: String
        if weeks < next.week {
            tail = "\(next.name) unlocks from week \(next.week + 1) if that holds."
        } else if due?.ready == true {
            tail = "That is enough — add the next one when you want it."
        } else {
            tail = "\(Int(Mind.unlockRate * 100))% is the bar for adding another."
        }
        return "You are hitting \(percent)% of the \(active == 1 ? "practice" : "practices") you already have, over \(adherence.days) days. \(tail)"
    }
}

// MARK: - Week

struct MindWeekView: View {
    @Environment(AppStore.self) private var store
    private var state: LogState { store.state }

    var body: some View {
        let active = Mind.activePractices(state)

        LazyVStack(alignment: .leading, spacing: 14) {
            Panel(title: "The week", tag: "last 7 days") {
                ForEach(Plan.order, id: \.self) { dow in
                    let date = DateKit.adding(-((state.todayDow - dow + 7) % 7), to: state.today)
                    let hit = active.filter { Mind.didPractice(state, $0, on: date) }.count
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(hit == active.count && !active.isEmpty ? Theme.green
                                      : hit > 0 ? Theme.amber : Theme.line)
                                .frame(width: 7, height: 7)
                            Text(Plan.day(dow).label)
                                .font(Theme.body(13, weight: .bold))
                                .foregroundStyle(Theme.bone)
                            Spacer()
                            PTag("\(date == state.today ? "today" : String(date.dropFirst(5))) · \(hit)/\(active.count)")
                        }
                        Text(dow == 6
                             ? "Ladder day — rungs 1–\(state.mindLadderCap)"
                             : MindPlan.socialRep(dow: dow))
                            .font(Theme.body(12.5))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }

            Panel(title: "The practices", tag: "in unlock order") {
                ForEach(Array(MindPlan.practices.enumerated()), id: \.element.id) { index, practice in
                    let unlocked = index < active.count
                    StatRow(dimmed: !unlocked) {
                        Text(practice.name)
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.bone)
                        Text("\(practice.group) · \(practice.why)")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    } trailing: {
                        if unlocked {
                            if practice.kind == .minutes {
                                Text("\(Mind.target(state, practice) ?? 0) min")
                                    .font(Theme.mono(11, weight: .bold))
                                    .foregroundStyle(Theme.bone)
                            } else {
                                PTag("active", tint: Theme.green)
                            }
                        } else {
                            Text("week \(practice.week + 1)")
                                .font(Theme.mono(9.5))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Progress

struct MindProgressView: View {
    @Environment(AppStore.self) private var store
    private var state: LogState { store.state }

    var body: some View {
        let active = Mind.activePractices(state)
        let adherence = Mind.adherence(state, window: 28)
        let streaks = Mind.streaks(state)
        let journalDays = Mind.journalDays(state)

        LazyVStack(alignment: .leading, spacing: 14) {
            Panel(title: "Consistency", tag: "last 28 days") {
                MacroGrid(items: [
                    .init(value: adherence.map { "\(Int(($0.rate * 100).rounded()))" } ?? "–",
                          label: "done", suffix: "%"),
                    .init(value: "\(active.count)", label: "practices"),
                    .init(value: "\(journalDays)", label: "entries"),
                    .init(value: "\(state.mindLadderCap)", label: "ladder cap"),
                ])
                Note(Mind.reading(state))
            }

            Panel(title: "Streaks", tag: "days running") {
                ForEach(streaks) { streak in
                    StatRow {
                        Text(streak.practice.name)
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.bone)
                        if streak.practice.kind == .minutes {
                            Text("target \(Mind.target(state, streak.practice) ?? 0) min")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.muted)
                        }
                    } trailing: {
                        HStack(spacing: 4) {
                            Text("\(streak.days)")
                                .font(Theme.mono(14, weight: .bold))
                                .foregroundStyle(Theme.bone)
                            Text(streak.days == 1 ? "day" : "days")
                                .font(Theme.mono(9.5))
                                .foregroundStyle(Theme.muted)
                            if streak.days >= 7 {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.amber)
                            }
                        }
                    }
                }
                if active.contains(where: { $0.kind == .minutes }) {
                    Note("""
                        A minutes practice only counts on a day it hit the target. Three at target in a row \
                        and the target goes up.
                        """)
                }
            }

            if journalDays > 0 {
                Panel(title: "Journal", tag: "\(journalDays) entries") {
                    ForEach(journalEntries, id: \.date) { entry in
                        StatRow {
                            Text(entry.date)
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.muted)
                            Text(entry.excerpt)
                                .font(Theme.body(12.5))
                                .foregroundStyle(Theme.bone)
                                .fixedSize(horizontal: false, vertical: true)
                        } trailing: {
                            EmptyView()
                        }
                    }
                    Note("""
                        Stored with the rest of your log — mirrored to your own iCloud account, included in \
                        the backup file, and wiped by Delete all data.
                        """)
                }
            }
        }
    }

    private struct JournalEntry { var date: String; var excerpt: String }

    private var journalEntries: [JournalEntry] {
        state.mindLogs
            .filter { !$0.value.journal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.key > $1.key }
            .prefix(10)
            .map { date, log in
                let text = log.journal.trimmingCharacters(in: .whitespacesAndNewlines)
                let excerpt = text.count > 180 ? String(text.prefix(180)) + "…" : text
                return JournalEntry(date: date, excerpt: excerpt)
            }
    }
}
