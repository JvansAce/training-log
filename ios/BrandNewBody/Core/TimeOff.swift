import Foundation

/// Illness and holidays are not adherence failures, but every derived number
/// in this app treated them as one. A week of flu broke a sixteen-week green
/// streak. Recovery sat red for four days and the app prescribed a deload —
/// burning the 28-day cooldown on fatigue that was viral, not training. Worst
/// of all, the scale: glycogen carries about 3 g of water per gram, and Olsson
/// & Saltin measured a 2.4 kg bodyweight swing over four days of carbohydrate
/// loading. Stop eating for three days with a fever and the same thing runs
/// backwards. The 28-day least-squares trend read that as a real loss and
/// offered a one-tap +200 kcal; the refill on the way back read as a real gain
/// and told you to hold. Both were water.
///
/// So days off are recorded, and the derived numbers are told to look away.
/// Nothing here changes what the scale says — the weight is the weight. It
/// changes what the app is willing to conclude from it.
public enum TimeOff {

    /// Capped so a mis-typed year can't write thousands of days into a record
    /// that syncs on every change.
    public static let maxSpan = 90

    // Layoff thresholds come from the detraining literature rather than
    // instinct: strength is close to unchanged across two weeks off, and
    // losses only become meaningful after roughly three to four weeks of
    // complete inactivity. So a short break earns a lighter first session
    // back, not a lighter bar; a long one earns both.
    public static let rampMinimum = 4     // days off below this need no ramp at all
    public static let longBreak = 14      // at or beyond this, back off the load too
    public static let rampDays = 7        // how long the ramp advice stays up
    public static let weighHold = 4       // days after a break during which weigh-ins are water

    public struct Run: Equatable, Sendable {
        public var kind: OffKind
        public var days: Int
        /// First day of the run.
        public var since: String
    }

    public struct Ended: Equatable, Sendable {
        public var kind: OffKind
        public var days: Int
        /// Last day off.
        public var end: String
        /// Days between that and today.
        public var daysSince: Int
    }

    public struct Ramp: Equatable, Sendable {
        public var kind: OffKind
        public var days: Int
        public var daysSince: Int
        /// Past a fortnight the losses are real, so the load comes off too.
        public var long: Bool
    }

    public static func kind(_ state: LogState, on date: String) -> OffKind? {
        state.off[date]
    }

    public static func isOff(_ state: LogState, _ date: String) -> Bool {
        state.off[date] != nil
    }

    public static func today(_ state: LogState) -> OffKind? {
        state.off[state.today]
    }

    /// The current unbroken run of off days ending today, or nil.
    ///
    /// Walks back from today rather than reading a stored range, so a run
    /// assembled a day at a time and one marked as a block behave identically.
    public static func current(_ state: LogState) -> Run? {
        guard today(state) != nil else { return nil }
        var count = 0
        var cursor = state.today
        var start = state.today
        var kind = state.off[state.today]!
        while let k = state.off[cursor], count < maxSpan {
            start = cursor
            kind = k            // the earliest day of the run names it
            count += 1
            cursor = DateKit.adding(-1, to: cursor)
        }
        return Run(kind: kind, days: count, since: start)
    }

    /// The last day off, and how long ago it ended. Drives the return ramp.
    public static func last(_ state: LogState) -> Ended? {
        let past = state.off.keys.filter { $0 <= state.today }.sorted()
        guard let end = past.last, let kind = state.off[end] else { return nil }
        // Length of the run that ends there, so "back after 3 days" and "back
        // after three weeks" can be told apart.
        var count = 0
        var cursor = end
        while state.off[cursor] != nil, count < maxSpan {
            count += 1
            cursor = DateKit.adding(-1, to: cursor)
        }
        let since = DateKit.days(from: end, to: state.today) ?? 0
        return Ended(kind: kind, days: count, end: end, daysSince: since)
    }

    public static func daysOff(_ state: LogState, from: String, to: String) -> Int {
        state.off.keys.filter { $0 >= from && $0 <= to }.count
    }

    /// Weigh-ins the trend must not draw a line through: the days off
    /// themselves, and the refill afterwards. Four days is Olsson & Saltin's
    /// loading window — the period over which the water actually comes back.
    public static func skipsWeighIn(_ state: LogState, _ date: String) -> Bool {
        if isOff(state, date) { return true }
        for i in 1...weighHold where isOff(state, DateKit.adding(-i, to: date)) {
            return true
        }
        return false
    }

    /// The advice shown on the way back, or nil on an ordinary day.
    public static func returnRamp(_ state: LogState) -> Ramp? {
        guard today(state) == nil, let l = last(state) else { return nil }
        guard l.days >= rampMinimum else { return nil }
        guard l.daysSince >= 1, l.daysSince <= rampDays else { return nil }
        return Ramp(kind: l.kind, days: l.days, daysSince: l.daysSince, long: l.days >= longBreak)
    }
}
