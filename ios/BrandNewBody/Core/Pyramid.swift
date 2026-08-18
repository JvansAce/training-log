import Foundation

/// The pyramid circuit's rep-count structure, kept for one reason: reading
/// back whatever was already logged before the circuit was dropped from the
/// plan. Round N was N pull-ups, 2N dips, 3N push-ups, 4N sit-ups, 5N squats
/// — the 1:2:3:4:5 ratio roughly matching how hard each movement is. Climbing
/// "to cap C" meant doing rounds 1 through C, so each movement's total was
/// its ratio times the Cth triangular number.
///
/// `PyramidEntry`/`PyramidRecord` and the settings behind it (`pyramidCap`,
/// `vestKg`, `vestPhase`) are untouched on purpose — anyone who logged a
/// Saturday under the old plan keeps that history, in `SessionExport` and any
/// backup, exactly as it was recorded. Only the live progression logic
/// (cap/vest adjustment, the deload reduction, the checklist line itself) is
/// gone, along with the schedule entry that drove it.
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

    public static func totals(cap: Int) -> Totals {
        let triangular = cap * (cap + 1) / 2
        let parts = ratio.map { Part(name: $0.name, reps: $0.k * triangular) }
        return Totals(parts: parts, total: parts.reduce(0) { $0 + $1.reps })
    }
}
