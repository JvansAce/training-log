import Foundation

/// Per-set logging, the progression target, plate maths and the stall check.
public enum Lifts {

    public static let maxSets = 5

    // Gaps in a single lift's history, which is a different measure from days
    // off and needs different numbers. Every lift here comes round once or
    // twice a week, so a 7-day gap is the normal cadence — anything keyed at
    // or below that would read every ordinary weekly session as a layoff and
    // suppress progression on the whole programme, permanently. These are gaps
    // that mean a session was genuinely missed: 12 days is at least one
    // skipped week even allowing for a few days of drift, and 28 is roughly
    // where the detraining literature puts meaningful strength loss for a lift
    // left alone entirely.
    public static let layoffDays = 12
    public static let longLayoffDays = 28

    /// A lift counts as "current" if trained inside this.
    public static let recentDays = 14
    public static let stallDays = 28
    public static let stallMinimumSessions = 3

    // MARK: - Set arithmetic

    /// Ordering used for "which of these two sets is better": load dominates,
    /// reps break the tie.
    public static func beats(_ a: LiftSet, _ b: LiftSet) -> Bool {
        ((a.kg ?? 0) * 1000 + Double(a.reps)) > ((b.kg ?? 0) * 1000 + Double(b.reps))
    }

    public static func bestSet(_ record: LiftRecord?) -> LiftSet? {
        guard let sets = record?.sets, !sets.isEmpty else { return nil }
        return sets.reduce(sets[0]) { beats($1, $0) ? $1 : $0 }
    }

    public struct Volume: Equatable, Sendable {
        public var reps: Int
        /// nil for a session of pure bodyweight work.
        public var kg: Int?
    }

    /// Work done in one session. Bodyweight sets carry no load, so kg-volume
    /// would read 0 and look like nothing happened — report total reps for
    /// those instead and let the caller label it.
    public static func volume(_ record: LiftRecord?) -> Volume {
        let sets = record?.sets ?? []
        let reps = sets.reduce(0) { $0 + $1.reps }
        let weighted = sets.filter { ($0.kg ?? 0) > 0 }
        guard !weighted.isEmpty else { return Volume(reps: reps, kg: nil) }
        let load = weighted.reduce(0.0) { $0 + ($1.kg ?? 0) * Double($1.reps) }
        return Volume(reps: reps, kg: Int(load.rounded()))
    }

    /// Epley. Only meaningful for loaded sets, and it drifts badly at very
    /// high reps, so this caps where the formula still says something useful.
    public static func e1rm(_ set: LiftSet?) -> Double? {
        guard let set, let kg = set.kg, kg > 0, set.reps > 0, set.reps <= 15 else { return nil }
        return kg * (1 + Double(set.reps) / 30)
    }

    public static func bestE1rm(_ record: LiftRecord?) -> Double? {
        e1rm(bestSet(record))
    }

    // MARK: - Prescription parsing

    public struct Scheme: Equatable, Sendable {
        public var sets: Int
        public var low: Int
        public var high: Int
    }

    private static let schemeRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"(\d+)\s*×\s*(\d+)(?:\s*[–-]\s*(\d+))?"#)

    /// Reads the prescribed set/rep scheme out of the item's own text, so the
    /// programme stays the single source of truth rather than duplicating rep
    /// ranges into a second table that could drift.
    ///
    /// Returns nil for anything that isn't a clean numeric range — "4 × max
    /// reps", "3 × to 2 reps shy" — which correctly means no target is
    /// suggested for those.
    public static func parseScheme(_ text: String) -> Scheme? {
        guard let regex = schemeRegex else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let sets = Int(ns.substring(with: match.range(at: 1))),
              let low = Int(ns.substring(with: match.range(at: 2)))
        else { return nil }
        var high = low
        let third = match.range(at: 3)
        if third.location != NSNotFound, let parsed = Int(ns.substring(with: third)) {
            high = parsed
        }
        return Scheme(sets: sets, low: low, high: high)
    }

    /// Conservative, and smaller for light lifts: +2.5 kg on a 10 kg lateral
    /// raise is a 25% jump, which is not a progression, it is a new exercise.
    public static func loadStep(_ kg: Double) -> Double {
        kg < 15 ? 1 : 2.5
    }

    // MARK: - The target

    public struct Target: Equatable, Sendable {
        public var text: String
        /// The load the target implies, for the plate maths. nil on a
        /// bodyweight lift.
        public var kg: Double?
    }

    /// The programme says "add weight or a rep whenever you hit the top of the
    /// range". This works out what that means for this lift, today, instead of
    /// leaving it as arithmetic to do between sets.
    public static func nextTarget(_ state: LogState, id: String, on date: String,
                                 prescription: String) -> Target? {
        guard let scheme = parseScheme(prescription) else { return nil }
        let history = state.liftHistory(id).filter { $0.date != date }
        guard let last = history.last, !last.sets.isEmpty else { return nil }

        let working = last.sets.filter { $0.reps > 0 }
        guard let minReps = working.map(\.reps).min(), let first = working.first else { return nil }
        let kg = first.kg

        // Progression assumes the last session was recent. After a layoff it
        // is arithmetic on a number your body has not seen in weeks. Strength
        // barely moves across a fortnight off, so this repeats the load rather
        // than dropping it — and only backs the bar off once the gap is long
        // enough for detraining to be real.
        let gap = DateKit.days(from: last.date, to: date) ?? 0
        if gap >= layoffDays {
            guard let kg else {
                return Target(text: "\(gap) days since this one — repeat it before chasing reps", kg: nil)
            }
            if gap >= longLayoffDays {
                let step = loadStep(kg)
                let back = max(step, (kg * 0.1 / step).rounded() * step)
                let to = max(step, kg - back)
                return Target(text: "\(gap) days off this lift — open at \(fmt(to)) kg and climb back", kg: to)
            }
            return Target(text: "\(gap) days since this one — repeat \(fmt(kg)) kg before adding", kg: kg)
        }

        // Every working set at or above the top of the range is the condition
        // the programme actually names — not just the best set, which can hide
        // a set that fell apart.
        if minReps >= scheme.high {
            guard let kg else {
                return Target(text: "all sets at \(scheme.high) — time to add load", kg: nil)
            }
            let next = kg + loadStep(kg)
            return Target(text: "hit \(scheme.high)s — go \(fmt(next)) kg × \(scheme.low)", kg: next)
        }

        let target = min(minReps + 1, scheme.high)
        guard let kg else { return Target(text: "chase \(target) reps", kg: nil) }
        return Target(text: "stay \(fmt(kg)) kg — chase \(target) reps", kg: kg)
    }

    // MARK: - Plates

    public static let plates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    /// Plate maths for a barbell, per side. Anything the available plates
    /// cannot express exactly is reported as nil rather than silently rounded
    /// to something you can't actually load.
    public static func platesFor(total: Double?, bar: Double) -> String? {
        guard let total, total >= bar else { return nil }
        var perSide = (total - bar) / 2
        var parts: [String] = []
        for plate in plates {
            let count = Int((perSide + 1e-9) / plate)
            if count > 0 {
                parts.append("\(count)×\(fmt(plate))")
                // Rounded each step so binary drift across seven subtractions
                // can't leave a residue that fails the exactness check below
                // for a load that is in fact loadable.
                perSide = ((perSide - Double(count) * plate) * 10_000).rounded() / 10_000
            }
        }
        guard perSide <= 0.01 else { return nil }
        return parts.isEmpty ? "bar only" : parts.joined(separator: " + ")
    }

    // MARK: - Stalls

    public struct Stall: Equatable, Sendable {
        public var weeks: Int
        public var sessions: Int
    }

    /// "You logged it, but it hasn't moved." Only fires with enough recent
    /// entries to be a real plateau rather than a two-week gap.
    public static func stall(_ history: [LiftRecord]) -> Stall? {
        let scored = history.compactMap { record -> (date: String, value: Double)? in
            guard let v = bestE1rm(record) else { return nil }
            return (record.date, v)
        }
        guard scored.count >= stallMinimumSessions, let newest = scored.last else { return nil }

        let cutoff = DateKit.adding(-stallDays, to: newest.date)
        let recent = scored.filter { $0.date >= cutoff }
        guard recent.count >= stallMinimumSessions else { return nil }

        guard let peak = scored.map(\.value).max() else { return nil }
        // First time the peak was reached, not the last. Someone grinding the
        // same 100×5 every week has the peak value on every entry including
        // today's — taking the latest would read that as a fresh PR and never
        // flag anything. Matching an old best is not progress.
        guard let peakAt = scored.first(where: { $0.value == peak }) else { return nil }
        // Peak inside the window means it's genuinely still moving.
        guard peakAt.date < cutoff else { return nil }

        let days = DateKit.days(from: peakAt.date, to: newest.date) ?? 0
        return Stall(weeks: max(Int((Double(days) / 7).rounded()), 1), sessions: recent.count)
    }

    // MARK: - Formatting

    /// Whole numbers print without a decimal point; halves keep one. Matches
    /// how JavaScript rendered these and, more to the point, how anyone writes
    /// a weight down.
    public static func fmt(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.2f", value)
                .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    public static func describe(_ set: LiftSet) -> String {
        guard let kg = set.kg, kg > 0 else { return "BW × \(set.reps)" }
        return "\(fmt(kg)) kg × \(set.reps)"
    }

    public static func describe(_ record: LiftRecord) -> String {
        record.sets.map(describe).joined(separator: " · ")
    }

    public static func describe(_ volume: Volume) -> String {
        if let kg = volume.kg { return "\(kg) kg vol" }
        return "\(volume.reps) reps"
    }

    /// The one-line history under a lift's inputs.
    public static func reference(_ state: LogState, id: String, on date: String) -> String {
        let history = state.liftHistory(id)
        let mine = history.first { $0.date == date }
        let last = history.filter { $0.date != date }.last

        // Once there's more than one set logged, the individual sets are
        // already visible in the inputs right above — the useful summary is
        // the totals.
        func totals(_ record: LiftRecord) -> String {
            guard record.sets.count > 1 else { return "" }
            var out = " · \(describe(volume(record)))"
            if let est = bestE1rm(record) { out += " · e1RM \(Int(est.rounded()))" }
            return out
        }

        guard let last else {
            guard let mine else { return "first entry — this becomes your benchmark" }
            return "logged \(describe(mine))\(totals(mine))"
        }

        var text = "last \(describe(last))\(totals(last)) · \(String(last.date.dropFirst(5)))"
        if let mineBest = bestSet(mine), let lastBest = bestSet(last), beats(mineBest, lastBest) {
            text += " ▲ beaten"
        }
        return text
    }
}
