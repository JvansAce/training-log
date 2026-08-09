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

    public struct Signal: Equatable, Sendable {
        public var mean: Int
        public var reds: Int
        public var days: Int
        public var reason: String
    }

    /// Scored recovery for the days before today, newest first.
    static func recoveryDays(_ state: LogState, _ count: Int) -> [(date: String, value: Int)] {
        var out: [(String, Int)] = []
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
        guard days.count >= minimumDays else { return nil }
        let mean = Int((Double(days.reduce(0) { $0 + $1.value }) / Double(days.count)).rounded())
        let reds = days.filter { $0.value < redRecovery }.count

        if mean < meanThreshold {
            return Signal(mean: mean, reds: reds, days: days.count,
                          reason: "Recovery has averaged \(mean)% over the last \(days.count) days.")
        }
        if reds >= redDaysThreshold {
            return Signal(mean: mean, reds: reds, days: days.count,
                          reason: "\(reds) red days in the last \(days.count), at a \(mean)% average.")
        }
        return nil
    }
}
