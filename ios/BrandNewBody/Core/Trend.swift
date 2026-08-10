import Foundation

/// The kg/month figure that drives the calorie advice.
///
/// Deliberately a rolling window, not the whole history: comparing the first
/// weigh-ins ever against the most recent ones measures a chord across the
/// entire log, so months in it reports a lifetime average and keeps saying
/// "on target" during a multi-week stall — exactly when it should be saying to
/// eat more. Least-squares over the window rather than first-vs-last, so one
/// heavy water-weight morning at either edge doesn't swing the whole verdict.
public enum Trend {

    public static let windowDays = 28
    public static let minimumPoints = 4
    public static let minimumSpan = 10

    public struct Fit: Equatable, Sendable {
        /// Kilograms per month.
        public var rate: Double
        /// Days actually spanned by the window.
        public var days: Int
        public var points: Int
        /// Weigh-ins left out because they sat inside or just after time off.
        public var skipped: Int
    }

    public enum Verdict: String, Sendable {
        case slow, ok, fast, unknown
    }

    public static func fit(_ state: LogState) -> Fit? {
        // Drop the days off and their refill before anything else, so the
        // 28-day window is 28 days of comparable mornings rather than 28
        // calendar days.
        let usable = state.sortedWeights.filter { !TimeOff.skipsWeighIn(state, $0.date) }
        guard usable.count >= minimumPoints, let newest = usable.last else { return nil }

        let cutoff = DateKit.adding(-windowDays, to: newest.date)
        let window = usable.filter { $0.date >= cutoff }
        guard window.count >= minimumPoints, let first = window.first else { return nil }

        let xs: [Double] = window.map { Double(DateKit.days(from: first.date, to: $0.date) ?? 0) }
        let ys: [Double] = window.map(\.kg)
        guard let span = xs.last, span >= Double(minimumSpan) else { return nil }

        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0
        var denominator = 0.0
        for i in xs.indices {
            numerator += (xs[i] - meanX) * (ys[i] - meanY)
            denominator += (xs[i] - meanX) * (xs[i] - meanX)
        }
        guard denominator != 0 else { return nil }

        let skipped = state.weights.count - usable.count
        return Fit(rate: (numerator / denominator) * 30,
                   days: Int(span.rounded()),
                   points: window.count,
                   skipped: skipped)
    }

    public static func verdict(_ state: LogState) -> Verdict {
        guard let f = fit(state) else { return .unknown }
        if f.rate < 0.35 { return .slow }
        if f.rate > 1.0 { return .fast }
        return .ok
    }

    /// The sentence under the big number.
    public static func verdictText(_ state: LogState) -> String {
        guard let f = fit(state) else {
            return (TimeOff.today(state) != nil || TimeOff.returnRamp(state) != nil)
                ? "Weigh-ins around time off are water, not progress — the rate comes back once there are \(minimumPoints)+ ordinary mornings again."
                : "Log \(minimumPoints)+ weigh-ins over a couple of weeks to see your rate."
        }
        let tail: String
        switch verdict(state) {
        case .slow:
            tail = "Below target — add \(Fuel.calorieStep) kcal (more milk, bigger rice portion)."
        case .fast:
            tail = "Faster than a lean bulk needs. Hold calories steady."
        default:
            tail = "On target for a lean bulk."
        }
        let sign = f.rate > 0 ? "+" : ""
        var text = "\(sign)\(String(format: "%.2f", f.rate)) kg / month over the last \(f.days) days. \(tail)"
        if f.skipped > 0 {
            text += " (\(f.skipped) weigh-in\(f.skipped == 1 ? "" : "s") around time off left out)"
        }
        return text
    }
}
