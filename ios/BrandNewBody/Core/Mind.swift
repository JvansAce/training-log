import Foundation

/// Derived numbers for Brand New Mind: what is unlocked, what counts as done,
/// where the minute targets are, and the one sentence that says the unwelcome
/// thing.
public enum Mind {

    public static let adherenceWindow = 14
    public static let unlockRate = 0.7
    /// Hit the target this many sessions running and the target goes up —
    /// the same rule the barbell uses.
    public static let progressHits = 3

    public static func weeksIn(_ state: LogState) -> Int {
        guard let start = state.mindStartDate,
              let n = DateKit.days(from: start, to: state.today) else { return 0 }
        return max(0, n / 7)
    }

    public static func activePractices(_ state: LogState) -> [MindPlan.Practice] {
        let count = min(MindPlan.practices.count, max(1, state.mindUnlocked))
        return Array(MindPlan.practices.prefix(count))
    }

    public static func nextPractice(_ state: LogState) -> MindPlan.Practice? {
        let index = min(MindPlan.practices.count, max(1, state.mindUnlocked))
        guard index < MindPlan.practices.count else { return nil }
        return MindPlan.practices[index]
    }

    /// Target minutes for a practice: whatever progression has raised it to,
    /// or the starting load.
    public static func target(_ state: LogState, _ p: MindPlan.Practice) -> Int? {
        guard p.kind == .minutes, let start = p.start, let ceiling = p.max else { return nil }
        return min(ceiling, max(start, state.mindTargets[p.key] ?? start))
    }

    /// Did this practice happen on this date?
    ///
    /// A minutes practice needs the minutes to have actually reached the
    /// target — logging 3 minutes of a 20-minute sit is not a session, and
    /// counting it would let the streak and the unlock gate both drift away
    /// from reality.
    public static func didPractice(_ state: LogState, _ p: MindPlan.Practice, on date: String) -> Bool {
        guard let log = state.mindLogs[date] else { return false }
        switch p.kind {
        case .minutes:
            guard let target = target(state, p), let logged = log.mins[p.key] else { return false }
            return logged >= target
        case .text:
            return !log.journal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .drill:
            // Drills are logged under the specific drill that was current that
            // day (chr0, chr1, …), so the history says which technique you
            // were on, not just that you did something. Any of them counts as
            // the practice done.
            return log.done.contains { $0.hasPrefix("chr") && Int($0.dropFirst(3)) != nil }
        case .tick:
            return log.done.contains(p.key)
        }
    }

    // MARK: - Charisma

    /// The index is monotonic and never wrapped, so each lap through the list
    /// gets its own keys and a second pass at "Follow-up questions" does not
    /// inherit the first pass's tally.
    public static func charismaKey(_ state: LogState) -> String {
        "chr\(state.charismaIx)"
    }

    public static func charismaDrill(_ state: LogState) -> MindPlan.Drill {
        MindPlan.charisma[state.charismaIx % MindPlan.charisma.count]
    }

    public static func charismaLap(_ state: LogState) -> Int {
        state.charismaIx / MindPlan.charisma.count + 1
    }

    public static func charismaUses(_ state: LogState) -> Int {
        let key = charismaKey(state)
        let since = state.charismaSince
        return state.mindLogs.filter { date, log in
            (since == nil || date >= since!) && log.done.contains(key)
        }.count
    }

    /// True when the drill is finished and the caller should advance. Advances
    /// on use, not on the calendar — a drill you have not practised is not one
    /// you are finished with.
    public static func charismaReady(_ state: LogState) -> Bool {
        charismaUses(state) >= MindPlan.charismaUsesNeeded
    }

    // MARK: - Adherence and unlocking

    public struct Adherence: Equatable, Sendable {
        public var rate: Double
        public var days: Int
        public var skipped: Int
    }

    /// Share of the last fortnight on which everything currently unlocked was
    /// done. Only counts days since the mind programme actually started, so a
    /// fresh install is not immediately judged against two weeks of blanks.
    public static func adherence(_ state: LogState, window: Int = adherenceWindow) -> Adherence? {
        let active = activePractices(state)
        guard let start = state.mindStartDate, !active.isEmpty else { return nil }
        var days = 0
        var hits = 0.0
        var skipped = 0
        for i in 0..<window {
            let date = DateKit.adding(-i, to: state.today)
            if date < start || date == state.today { continue }   // today is still in progress
            // Out of the denominator, not scored as a miss. A fortnight away
            // would otherwise empty the whole window and hold the next unlock
            // for a month after you got back — punishing the holiday twice.
            if TimeOff.isOff(state, date) { skipped += 1; continue }
            days += 1
            let done = active.filter { didPractice(state, $0, on: date) }.count
            hits += Double(done) / Double(active.count)
        }
        guard days > 0 else { return nil }
        return Adherence(rate: hits / Double(days), days: days, skipped: skipped)
    }

    public struct Unlock: Equatable, Sendable {
        public var next: MindPlan.Practice
        public var ready: Bool
        public var reason: String
        public var adherence: Adherence?
    }

    /// Unlocking is monotonic — a bad fortnight never takes a practice away,
    /// because hiding something you have been logging looks like data loss. It
    /// only ever gates the NEXT one.
    public static func unlockDue(_ state: LogState) -> Unlock? {
        guard let next = nextPractice(state), weeksIn(state) >= next.week else { return nil }
        guard let a = adherence(state), a.days >= 7 else {
            return Unlock(next: next, ready: false,
                          reason: "needs a full week of history first",
                          adherence: adherence(state))
        }
        return Unlock(next: next, ready: a.rate >= unlockRate,
                      reason: "\(Int((a.rate * 100).rounded()))% of the last \(a.days) days — \(Int(unlockRate * 100))% unlocks the next one",
                      adherence: a)
    }

    // MARK: - Minute progression

    public struct NextTarget: Equatable, Sendable {
        public var at: Int
        public var run: Int
        public var need: Int
        public var ready: Bool
        public var next: Int
        public var capped: Bool
    }

    public static func nextTarget(_ state: LogState, _ p: MindPlan.Practice) -> NextTarget? {
        guard p.kind == .minutes, let current = target(state, p),
              let step = p.step, let ceiling = p.max else { return nil }
        if current >= ceiling {
            return NextTarget(at: ceiling, run: 0, need: progressHits, ready: false,
                              next: ceiling, capped: true)
        }
        let dates = state.mindLogs.keys.filter { $0 <= state.today }.sorted(by: >)
        var run = 0
        for date in dates {
            // A day it was not attempted breaks nothing.
            guard let value = state.mindLogs[date]?.mins[p.key] else { continue }
            if value >= current { run += 1 } else { break }
            if run >= progressHits { break }
        }
        return NextTarget(at: current, run: run, need: progressHits,
                          ready: run >= progressHits,
                          next: min(ceiling, current + step), capped: false)
    }

    // MARK: - Today's content

    public static func promptTier(_ state: LogState) -> Int {
        let weeks = weeksIn(state)
        return weeks >= 12 ? 2 : weeks >= 4 ? 1 : 0
    }

    /// Indexed by the day itself so the same date always shows the same prompt
    /// — re-rendering after a tick must not shuffle the question out from
    /// under someone halfway through answering it.
    public static func prompt(_ state: LogState, on date: String? = nil) -> String {
        let tier = MindPlan.prompts[promptTier(state)]
        let key = date ?? state.today
        guard let d = DateKit.date(key) else { return tier[0] }
        let days = Int((d.timeIntervalSince1970 / 86_400).rounded())
        return tier[((days % tier.count) + tier.count) % tier.count]
    }

    public static func ladderRungs(cap: Int) -> [String] {
        Array(MindPlan.ladder.prefix(max(1, min(MindPlan.ladder.count, cap))))
    }

    public static func isLadderDay(_ state: LogState) -> Bool {
        state.todayDow == 6
    }

    // MARK: - Streaks and the verdict

    public struct Streak: Identifiable, Equatable, Sendable {
        public var id: String { practice.key }
        public var practice: MindPlan.Practice
        public var days: Int
    }

    public static func streaks(_ state: LogState) -> [Streak] {
        activePractices(state).map { p in
            var n = 0
            for i in 1..<400 {
                if didPractice(state, p, on: DateKit.adding(-i, to: state.today)) { n += 1 } else { break }
            }
            // Today counts if it's already done, but not having done it yet by
            // lunchtime must not read as a broken streak.
            return Streak(practice: p, days: n + (didPractice(state, p, on: state.today) ? 1 : 0))
        }
    }

    public static func journalDays(_ state: LogState) -> Int {
        state.mindLogs.values.filter {
            !$0.journal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    /// Same job as the body side's verdict: say the unwelcome thing.
    public static func reading(_ state: LogState) -> String {
        let a = adherence(state, window: 28)
        guard let a, a.days >= 5 else {
            return "Not enough logged yet to say anything useful. Give it a week."
        }
        let percent = Int((a.rate * 100).rounded())
        let ordered = streaks(state).sorted { $0.days < $1.days }
        let ladderWeeks = state.mindLadderLog.count

        if a.rate >= 0.85 {
            return "\(percent)% over \(a.days) days. That is the boring consistency that actually does the work — the next practice is earned, not a reward."
        }
        if a.rate < 0.4 {
            return "\(percent)% over \(a.days) days. That is not a discipline problem, it is too much at once — drop back to the practices you actually do and rebuild from there."
        }
        if let weakest = ordered.first, let strongest = ordered.last,
           strongest.days - weakest.days >= 5 {
            return "\(strongest.practice.name) is running at \(strongest.days) days while \(weakest.practice.name) is at \(weakest.days). One habit is carrying the average. Fix the weak one before adding anything."
        }
        if ladderWeeks == 0 {
            return "\(percent)% on the dailies and no ladder logged yet. The Saturday work is the part that changes how you are with people — the rest is preparation for it."
        }
        return "\(percent)% over \(a.days) days. Steady. \(Int(unlockRate * 100))% is the bar for taking on the next practice."
    }
}
