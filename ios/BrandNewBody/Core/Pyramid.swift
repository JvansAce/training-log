import Foundation

/// The pyramid, precisely. Round N is N pull-ups, 2N dips, 3N push-ups, 4N
/// sit-ups, 5N squats — the 1:2:3:4:5 ratio roughly matching how hard each
/// movement is. Climbing "to cap C" means doing rounds 1 through C, so each
/// movement's total is its ratio times the Cth triangular number. That makes
/// total work grow with the SQUARE of the cap: 6 to 10 is not four more
/// rounds, it is 2.6× the reps. Hence alternating load instead.
public enum Pyramid {

    public struct Part: Identifiable, Equatable, Sendable {
        public var id: String { name }
        public var name: String
        public var reps: Int
    }

    public struct Totals: Equatable, Sendable {
        public var parts: [Part]
        public var total: Int
    }

    static let ratio: [(name: String, k: Int)] = [
        ("pull-ups", 1), ("dips", 2), ("push-ups", 3), ("sit-ups", 4), ("squats", 5),
    ]

    public static let maxCap = 10

    public static func totals(cap: Int) -> Totals {
        let triangular = cap * (cap + 1) / 2
        let parts = ratio.map { Part(name: $0.name, reps: $0.k * triangular) }
        return Totals(parts: parts, total: parts.reduce(0) { $0 + $1.reps })
    }

    // Suggested vest load scales with bodyweight so it tracks the bulk without
    // being touched, and mildly with the cap, since a higher cap is evidence
    // of capacity. Deliberately conservative — the usual guide for loaded
    // calisthenic volume is 5–10% of bodyweight, and the rep count is already
    // climbing quadratically underneath it.
    public static let vestPercentMin = 0.05
    public static let vestPercentMax = 0.08

    public static func suggestedVestKg(_ state: LogState) -> Double? {
        guard let bodyweight = state.latestAverage else { return nil }
        let cap = min(maxCap, max(3, state.pyramidCap))
        let percent = vestPercentMin + (Double(cap - 3) / 7) * (vestPercentMax - vestPercentMin)
        return (bodyweight * percent * 2).rounded() / 2      // nearest 0.5 kg
    }

    /// Whatever the user set by hand, otherwise the suggestion.
    public static func vestKg(_ state: LogState) -> Double? {
        state.vestKg ?? suggestedVestKg(state)
    }

    /// Alternation does NOT start from week one. While the cap is still low,
    /// adding a round is the cheap progression — cap 4 to 5 is 150 reps to
    /// 225 — so just climb. The vest earns its place once a round starts
    /// costing 100+ reps, which is around cap 6. Below that, alternating would
    /// be adding load to someone who hasn't finished learning the movement
    /// volume yet.
    public static let vestFromCap = 6

    /// Which programme week a date falls in. Taken from the date rather than
    /// from `today`, so back-filling last Saturday asks about *last* Saturday's
    /// week rather than this one's.
    public static func weekIndex(_ state: LogState, on date: String) -> Int {
        guard let n = DateKit.days(from: state.startDate, to: date) else { return state.weeksIn }
        return max(0, n / 7)
    }

    /// `vestPhase` only flips which parity carries the vest, for when the real
    /// schedule drifts out of step with the counter.
    public static func isVestWeek(_ state: LogState, on date: String? = nil) -> Bool {
        let week = date.map { weekIndex(state, on: $0) } ?? state.weeksIn
        return state.pyramidCap >= vestFromCap && ((week + state.vestPhase) % 2) == 1
    }

    /// The pyramid line as it appears on Saturday's checklist, with the cap
    /// and — on a vest week — the load folded into the name.
    public static func itemName(_ state: LogState, on date: String? = nil) -> String {
        var name = "Holland pyramid — rounds 1–\(state.pyramidCap)"
        if isVestWeek(state, on: date), let v = vestKg(state) {
            name += " · vest \(String(format: "%.1f", v)) kg"
        }
        return name
    }

    public static let itemPrescription =
        "round N = N pull-ups · 2N dips · 3N push-ups · 4N sit-ups · 5N squats"
}
