import Foundation

/// Sessions, weeks, the green streak and the weekly review.
public enum Consistency {

    /// The "four green weeks in a row" the Progress copy calls the real win.
    public static let greenWeek = 4

    /// How many ticks make a session. Thursday (cardio) and Sunday (rest) only
    /// have two items, so a flat 3 would make them impossible to ever
    /// complete.
    public static func sessionNeed(dow: Int) -> Int {
        min(3, Plan.day(dow).items.count)
    }

    public static func didSession(_ state: LogState, on date: String) -> Bool {
        guard let dow = DateKit.dow(key: date) else { return false }
        return state.day(date).done.count >= sessionNeed(dow: dow)
    }

    public static func sessions(_ state: LogState, from: String, to: String) -> Int {
        DateKit.range(from: from, to: to).filter { didSession(state, on: $0) }.count
    }

    /// Earliest day this log knows about.
    ///
    /// Weigh-ins alone are the wrong marker: a device restored from a partial
    /// backup, or someone who logged sessions for weeks before their first
    /// weigh-in, would otherwise have the streak cut off at whatever date that
    /// first weigh-in happens to carry.
    public static func logStart(_ state: LogState) -> String? {
        var dates = Array(state.logs.keys)
        if let first = state.sortedWeights.first { dates.append(first.date) }
        dates.append(state.startDate)
        return dates.min()
    }

    /// Did a deload week start inside this calendar week? Used by the streak,
    /// which must not punish a week the app itself prescribed.
    public static func deloadedWeek(_ state: LogState, from: String, to: String) -> Bool {
        state.deloadLog.contains { $0 >= from && $0 <= to }
    }

    /// How many sessions a week has to contain to count, given the days of it
    /// you were ill or away. Six trainable days normally, four of them
    /// sessions; away for three of those days and the bar is two. A week with
    /// nothing left in it returns 0, which the streak reads as "skip, do not
    /// judge".
    public static func greenNeed(_ state: LogState, from: String, to: String) -> Int {
        let off = TimeOff.daysOff(state, from: from, to: to)
        guard off > 0 else { return greenWeek }
        return max(0, Int((Double(greenWeek * (7 - off)) / 7).rounded()))
    }

    public static func greenStreak(_ state: LogState) -> Int {
        guard let from = logStart(state), let today = DateKit.date(state.today) else { return 0 }
        var streak = 0
        // Start from last week: the current one is still in progress and would
        // read as a broken streak every Monday morning.
        for k in 1...52 {
            let start = DateKit.adding(-7 * k, to: DateKit.weekStart(today))
            let end = DateKit.adding(6, to: start)
            let startKey = DateKit.key(start)
            let endKey = DateKit.key(end)
            // Weeks from before this log existed aren't failures, just absent.
            if endKey < from { break }
            // A week you deliberately deloaded is not a week you fell off. The
            // app asks you to train less and then counted it against the
            // streak it rewards — telling you off for doing what it just told
            // you to do.
            if deloadedWeek(state, from: startKey, to: endKey) {
                streak += 1
                continue
            }
            // A week you were ill or away is neither a green week nor a broken
            // one. Bridging it — rather than counting it, the way a deload is
            // counted — keeps the number honest: a fortnight in Spain does not
            // earn two green weeks, and it does not cost the fourteen you
            // already had.
            let need = greenNeed(state, from: startKey, to: endKey)
            if need <= 0 { continue }
            if sessions(state, from: startKey, to: endKey) >= need { streak += 1 } else { break }
        }
        return streak
    }

    public struct WeeklyReview: Equatable, Sendable {
        public var done: Int
        public var target: Int
        /// Change in average bodyweight against last week, nil without weigh-ins
        /// on both sides.
        public var delta: Double?
        /// Lift ids beaten this week.
        public var improved: [String]
        public var streak: Int
        public var daysOff: Int
        public var label: String
    }

    public static func weeklyReview(_ state: LogState) -> WeeklyReview {
        guard let today = DateKit.date(state.today) else {
            return WeeklyReview(done: 0, target: 0, delta: nil, improved: [],
                                streak: 0, daysOff: 0, label: "")
        }
        let thisStart = DateKit.weekStart(today)
        let thisEnd = DateKit.adding(6, to: thisStart)
        let prevStart = DateKit.adding(-7, to: thisStart)
        let prevEnd = DateKit.adding(-1, to: thisStart)

        let thisStartKey = DateKit.key(thisStart)
        let thisEndKey = DateKit.key(thisEnd)

        let done = sessions(state, from: thisStartKey, to: state.today)
        // Target excludes the full-rest day — six trainable days a week —
        // minus any day of this week spent ill or away.
        let off = TimeOff.daysOff(state, from: thisStartKey, to: thisEndKey)
        let target = max(0, Plan.order.filter { $0 != 0 }.count - off)

        func averageWeight(from: Date, to: Date) -> Double? {
            let lo = DateKit.key(from), hi = DateKit.key(to)
            let kgs = state.weights.filter { $0.date >= lo && $0.date <= hi }.map(\.kg)
            guard !kgs.isEmpty else { return nil }
            return kgs.reduce(0, +) / Double(kgs.count)
        }
        let thisAvg = averageWeight(from: thisStart, to: thisEnd)
        let prevAvg = averageWeight(from: prevStart, to: prevEnd)
        let delta: Double? = (thisAvg != nil && prevAvg != nil) ? thisAvg! - prevAvg! : nil

        // Seeding a reduce with nil would hand `beats` a nil on the first
        // iteration; reducing an empty array without a seed traps instead.
        // Both cases are reachable from real data, so emptiness is explicit.
        func bestAcross(_ records: [LiftRecord]) -> LiftSet? {
            let sets = records.compactMap { Lifts.bestSet($0) }
            guard let first = sets.first else { return nil }
            return sets.reduce(first) { Lifts.beats($1, $0) ? $1 : $0 }
        }

        var improved: [String] = []
        for id in state.lifts.keys.sorted() {
            let history = state.liftHistory(id)
            let current = history.filter { $0.date >= thisStartKey && $0.date <= thisEndKey }
            guard !current.isEmpty else { continue }
            let before = history.filter { $0.date < thisStartKey }
            guard !before.isEmpty else { continue }
            guard let bestBefore = bestAcross(before), let bestNow = bestAcross(current) else { continue }
            if Lifts.beats(bestNow, bestBefore) { improved.append(id) }
        }

        let label = "\(DateKit.shortLabel(thisStart)) – \(DateKit.shortLabel(thisEnd))"
        return WeeklyReview(done: done, target: target, delta: delta, improved: improved,
                            streak: greenStreak(state), daysOff: off, label: label)
    }

    public struct WeekBar: Identifiable, Equatable, Sendable {
        public var id: Int
        public var sessions: Int
        /// A short bar means one of two completely different things. Carrying
        /// the week's off-days alongside the count lets the chart say which,
        /// instead of drawing a holiday and a fortnight of excuses the same
        /// colour.
        public var daysOff: Int
    }

    /// Eight weeks of sessions, oldest first.
    public static func adherence(_ state: LogState) -> [WeekBar] {
        guard let today = DateKit.date(state.today) else { return [] }
        return (0...7).reversed().map { k in
            let end = DateKit.adding(-k * 7, to: today)
            let start = DateKit.adding(-6, to: end)
            let startKey = DateKit.key(start), endKey = DateKit.key(end)
            return WeekBar(id: 7 - k,
                           sessions: sessions(state, from: startKey, to: endKey),
                           daysOff: TimeOff.daysOff(state, from: startKey, to: endKey))
        }
    }
}
