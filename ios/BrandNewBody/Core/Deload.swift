import Foundation

/// The programme is six days a week with one rest day and a pyramid whose
/// volume grows with the square of the cap, and it had no mechanism at all for
/// backing off. The evidence for a FIXED deload every Nth week is genuinely
/// mixed, so this does not impose one — it watches the recovery data already
/// being collected and says something when that data says to.
///
/// The thresholds are WHOOP's own bands, which is where the readings
/// originally came from: under 34% is red, 67%+ is green. Two independent
/// triggers, because a week can go wrong in two shapes — a grinding low
/// average, or a handful of genuinely bad days inside an otherwise normal
/// week.
public enum Deload {

    public static let window = 7
    public static let meanThreshold = 50      // 7-day mean recovery below this
    public static let redDaysThreshold = 3    // or this many red days in the window
    public static let redRecovery = 34
    public static let minimumDays = 5         // don't judge a week off two readings
    public static let cooldownDays = 28       // never suggest another inside a month
    public static let snoozeDays = 5          // days of quiet after "Not now"
    /// The calendar backstop: a deload is due by here regardless of what
    /// recovery data says, or whether there's any recovery data at all.
    /// Every week of the programme adds load or volume with nothing that
    /// ever explicitly backs off, and someone without WHOOP or manual
    /// recovery entries would otherwise never see a deload signal — the
    /// recovery-based checks below need readings to fire, and this one
    /// doesn't. Sits at the top of the plan's own 4–6 week block window.
    public static let blockWeeks = 6
    /// How many of a session's lifts, trained in each of the last three
    /// sessions, need to show two straight sessions of a worse best set at
    /// the same prescription before that alone reads as fatigue outrunning
    /// recovery — the early trigger, ahead of the calendar or a bad
    /// recovery average.
    public static let performanceDeclineShare = 0.5

    public enum SignalKind: Equatable, Sendable {
        case recovery, performance, calendar
    }

    public struct Signal: Equatable, Sendable {
        public var mean: Int
        public var reds: Int
        public var days: Int
        public var reason: String
        public var kind: SignalKind
    }

    /// Scored recovery for the days before today, newest first.
    static func recoveryDays(_ state: LogState, _ count: Int) -> [(date: String, value: Int)] {
        // Labelled to match the return type: Swift will not convert
        // `[(String, Int)]` to `[(date: String, value: Int)]`, because tuple
        // labels are part of the element type and Array is invariant in it.
        var out: [(date: String, value: Int)] = []
        for i in 1...count {
            let date = DateKit.adding(-i, to: state.today)
            // A fever tanks recovery for days, and that is the illness, not
            // training fatigue. Counting those days would have the app
            // prescribe a deload — and spend the 28-day cooldown — for work
            // you did not do.
            if TimeOff.isOff(state, date) { continue }
            if let value = state.recovery[date]?.recovery { out.append((date, value)) }
        }
        return out
    }

    /// Ignores anything dated in the future — a device with a fast clock, or a
    /// record synced from one, would otherwise pin the app into a deload week
    /// that counts UP instead of down and never ends.
    public static func lastDeload(_ state: LogState) -> String? {
        state.deloadLog.filter { $0 <= state.today }.max()
    }

    static func daysSince(_ state: LogState, _ date: String?) -> Int {
        guard let date, let n = DateKit.days(from: date, to: state.today) else { return .max }
        return n
    }

    /// A deload is a week, not a day: the logged date is when it started.
    public static func inDeloadWeek(_ state: LogState) -> Bool {
        let n = daysSince(state, lastDeload(state))
        return n >= 0 && n < 7
    }

    public static func daysLeft(_ state: LogState) -> Int {
        max(0, 7 - daysSince(state, lastDeload(state)))
    }

    /// Whole weeks since the last deload — or, if there has never been one,
    /// since the programme started. The block's own calendar clock,
    /// independent of any recovery reading.
    public static func weeksSinceLastDeload(_ state: LogState) -> Int {
        let since = lastDeload(state) ?? state.startDate
        return max(0, (DateKit.days(from: since, to: state.today) ?? 0) / 7)
    }

    /// True if at least half of the lifts with three or more logged sessions
    /// show a worse best set in each of their last two sessions than the one
    /// before that — the same prescription producing less each time, which
    /// is fatigue outrunning recovery rather than a plateau (`Lifts.stall`
    /// is the flat-line version of this same idea).
    static func performanceDeclining(_ state: LogState) -> Bool {
        let scored = Plan.liftIDs.compactMap { id -> Bool? in
            let history = state.liftHistory(id).filter { !$0.sets.isEmpty }
            guard history.count >= 3 else { return nil }
            let scores = history.suffix(3).compactMap { Lifts.bestE1rm($0) }
            guard scores.count == 3 else { return nil }
            return scores[2] < scores[1] && scores[1] < scores[0]
        }
        guard scored.count >= 3 else { return false }
        return Double(scored.filter { $0 }.count) / Double(scored.count) >= performanceDeclineShare
    }

    public static func signal(_ state: LogState) -> Signal? {
        if inDeloadWeek(state) { return nil }
        // Nothing to deload from while you are off, and the first days back
        // are the ramp's business. `minimumDays` then holds the signal until
        // there are enough ordinary days in the window to mean anything.
        if TimeOff.today(state) != nil || TimeOff.returnRamp(state) != nil { return nil }
        if daysSince(state, lastDeload(state)) < cooldownDays { return nil }
        // The signal is a rolling window, so without a snooze "Not now" would
        // be undone by the very next render and the panel would nag on every
        // tap.
        if daysSince(state, state.deloadSnooze) < snoozeDays { return nil }

        let days = recoveryDays(state, window)
        if days.count >= minimumDays {
            let mean = Int((Double(days.reduce(0) { $0 + $1.value }) / Double(days.count)).rounded())
            let reds = days.filter { $0.value < redRecovery }.count

            if mean < meanThreshold {
                return Signal(mean: mean, reds: reds, days: days.count,
                              reason: "Recovery has averaged \(mean)% over the last \(days.count) days.",
                              kind: .recovery)
            }
            if reds >= redDaysThreshold {
                return Signal(mean: mean, reds: reds, days: days.count,
                              reason: "\(reds) red days in the last \(days.count), at a \(mean)% average.",
                              kind: .recovery)
            }
        }

        if performanceDeclining(state) {
            return Signal(mean: 0, reds: 0, days: 0,
                          reason: "Two sessions running of falling numbers at the same prescription, across half or more of what you're currently training.",
                          kind: .performance)
        }

        let weeks = weeksSinceLastDeload(state)
        if weeks >= blockWeeks {
            return Signal(mean: 0, reds: 0, days: weeks,
                          reason: "\(weeks) weeks since your last deload — due on the calendar alone, recovery data or not.",
                          kind: .calendar)
        }

        return nil
    }
}
