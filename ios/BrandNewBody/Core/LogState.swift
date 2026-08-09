import Foundation

/// One set of one lift. `kg == nil` is a bodyweight set — distinct from 0 kg,
/// which would read as "loaded with nothing" and drag the volume maths down.
public struct LiftSet: Codable, Hashable, Sendable {
    public var kg: Double?
    public var reps: Int

    public init(kg: Double? = nil, reps: Int) {
        self.kg = kg
        self.reps = reps
    }
}

public struct WeightRecord: Codable, Hashable, Sendable {
    public var date: String
    public var kg: Double
    /// The placeholder a fresh install starts with, so the charts and the
    /// calorie target have a bodyweight to read. Marked, because without the
    /// mark it tells a brand-new user they already weighed in this morning.
    public var seed: Bool

    public init(date: String, kg: Double, seed: Bool = false) {
        self.date = date
        self.kg = kg
        self.seed = seed
    }
}

public struct WaistRecord: Codable, Hashable, Sendable {
    public var date: String
    public var cm: Double

    public init(date: String, cm: Double) {
        self.date = date
        self.cm = cm
    }
}

public struct DayRecord: Codable, Hashable, Sendable {
    /// Item keys (`tu-row`), never indices. Indices meant that inserting an
    /// exercise silently changed what every past tick referred to.
    public var done: Set<String>
    public var fuelHit: Bool
    public var mobility: Set<Int>
    public var note: String

    public init(done: Set<String> = [], fuelHit: Bool = false, mobility: Set<Int> = [], note: String = "") {
        self.done = done
        self.fuelHit = fuelHit
        self.mobility = mobility
        self.note = note
    }

    public var isEmpty: Bool {
        done.isEmpty && !fuelHit && mobility.isEmpty && note.isEmpty
    }
}

public struct LiftRecord: Codable, Hashable, Sendable {
    public var date: String
    public var sets: [LiftSet]

    public init(date: String, sets: [LiftSet]) {
        self.date = date
        self.sets = sets
    }
}

public struct PyramidRecord: Codable, Hashable, Sendable {
    public var cap: Int
    public var vestKg: Double?

    public init(cap: Int, vestKg: Double? = nil) {
        self.cap = cap
        self.vestKg = vestKg
    }
}

/// Daily recovery readings. In the web app these arrived from WHOOP; here
/// they are entered by hand or read from HealthKit, but everything
/// downstream — the deload signal, the recovery chart — reads this shape
/// unchanged.
public struct RecoveryRecord: Codable, Hashable, Sendable {
    public var recovery: Int?
    public var strain: Double?
    public var sleepPct: Int?
    public var hrvMs: Double?
    public var restingHR: Int?

    public init(recovery: Int? = nil, strain: Double? = nil, sleepPct: Int? = nil,
                hrvMs: Double? = nil, restingHR: Int? = nil) {
        self.recovery = recovery
        self.strain = strain
        self.sleepPct = sleepPct
        self.hrvMs = hrvMs
        self.restingHR = restingHR
    }

    public var isEmpty: Bool {
        recovery == nil && strain == nil && sleepPct == nil && hrvMs == nil && restingHR == nil
    }
}

public enum OffKind: String, Codable, CaseIterable, Sendable {
    case ill
    case away

    public var label: String {
        switch self {
        case .ill: return "Ill"
        case .away: return "Away"
        }
    }
}

public struct MindDayRecord: Codable, Hashable, Sendable {
    public var done: Set<String>
    public var mins: [String: Int]
    public var journal: String

    public init(done: Set<String> = [], mins: [String: Int] = [:], journal: String = "") {
        self.done = done
        self.mins = mins
        self.journal = journal
    }

    public var isEmpty: Bool {
        done.isEmpty && mins.isEmpty && journal.isEmpty
    }
}

/// Everything the app derives numbers from, as one value type.
///
/// The whole `Core` layer is pure functions over this struct: no SwiftData, no
/// SwiftUI, no clock beyond the `today` it is handed. That is what makes the
/// maths — the trend fit, the streak, the progression targets — testable
/// without standing up a model container, and it is why `today` is a stored
/// property rather than something read from `Date()` deep inside a
/// calculation. A test can ask what this log looks like on any day.
public struct LogState: Codable, Hashable, Sendable {

    // MARK: Settings

    public var startDate: String
    public var pyramidCap: Int = 4
    /// nil means "track my bodyweight"; a number means the user set it by hand.
    public var vestKg: Double?
    public var vestPhase: Int = 0
    public var barKg: Double = 20
    public var calAdjust: Int = 0
    public var heightCm: Int?
    public var birthYear: Int?
    public var deloadSnooze: String?

    // MARK: Body collections

    public var weights: [WeightRecord] = []
    public var waist: [WaistRecord] = []
    public var logs: [String: DayRecord] = [:]
    /// Lift id → its entries, one per day trained.
    public var lifts: [String: [LiftRecord]] = [:]
    public var pyramidLog: [String: PyramidRecord] = [:]
    public var deloadLog: Set<String> = []
    public var off: [String: OffKind] = [:]
    public var recovery: [String: RecoveryRecord] = [:]

    // MARK: Mind

    public var mindStartDate: String?
    public var mindUnlocked: Int = 1
    public var mindLogs: [String: MindDayRecord] = [:]
    public var mindTargets: [String: Int] = [:]
    public var mindLadderLog: Set<String> = []
    public var mindLadderCap: Int = 1
    public var charismaIx: Int = 0
    public var charismaSince: String?

    // MARK: Clock

    /// The day the app considers "now". Injected rather than read from the
    /// system so every derived number is reproducible in a test.
    public var today: String

    public init(today: String = DateKit.todayKey) {
        self.today = today
        self.startDate = today
    }

    public var todayDow: Int { DateKit.dow(key: today) ?? 0 }

    // MARK: Convenience accessors

    public func day(_ date: String) -> DayRecord {
        logs[date] ?? DayRecord()
    }

    public func mindDay(_ date: String) -> MindDayRecord {
        mindLogs[date] ?? MindDayRecord()
    }

    /// Weigh-ins oldest first. Sorted on read rather than kept sorted, because
    /// records arrive from CloudKit in whatever order the sync delivers them.
    public var sortedWeights: [WeightRecord] {
        weights.sorted { $0.date < $1.date }
    }

    public var sortedWaist: [WaistRecord] {
        waist.sorted { $0.date < $1.date }
    }

    public func liftHistory(_ id: String) -> [LiftRecord] {
        (lifts[id] ?? []).sorted { $0.date < $1.date }
    }

    /// Mean of the last seven weigh-ins.
    ///
    /// nil rather than 0 when there are none: a device that syncs a brand-new
    /// account before its first weigh-in has no bodyweight to average, and
    /// every caller needs to show a placeholder rather than claim 0 kg.
    public var latestAverage: Double? {
        let recent = sortedWeights.suffix(7)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0) { $0 + $1.kg } / Double(recent.count)
    }

    public var latestWaist: WaistRecord? {
        sortedWaist.last
    }

    /// Whole weeks since the start date, floored at zero so a start date typed
    /// in the future doesn't produce a negative week counter.
    public var weeksIn: Int {
        guard let n = DateKit.days(from: startDate, to: today) else { return 0 }
        return max(0, n / 7)
    }
}
