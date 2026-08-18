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
    /// Mobility drill keys (`mob-hang`) — also keys, for the same reason.
    public var mobility: Set<String>
    public var note: String
    /// Follow a different weekday's plan on this date — sore from Friday, so
    /// Saturday's lifts happen Sunday instead. `nil` is "whatever this date's
    /// own weekday prescribes", the default for every day that's never had
    /// this touched. See `LogState.effectiveDow`.
    public var dayOverride: Int?

    public init(done: Set<String> = [], fuelHit: Bool = false,
                mobility: Set<String> = [], note: String = "", dayOverride: Int? = nil) {
        self.done = done
        self.fuelHit = fuelHit
        self.mobility = mobility
        self.note = note
        self.dayOverride = dayOverride
    }

    enum CodingKeys: String, CodingKey {
        case done, fuelHit, mobility, note, dayOverride
    }

    /// Hand-written only to read both shapes of `mobility`. A backup exported
    /// while ticks were still positions in the drill list has to keep
    /// importing, and a restore is exactly the moment you cannot afford to
    /// throw. Encoding stays synthesised, so nothing new is ever written in
    /// the old shape.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        done = (try? container.decode(Set<String>.self, forKey: .done)) ?? []
        fuelHit = (try? container.decode(Bool.self, forKey: .fuelHit)) ?? false
        note = (try? container.decode(String.self, forKey: .note)) ?? ""
        dayOverride = try? container.decode(Int.self, forKey: .dayOverride)
        if let keys = try? container.decode(Set<String>.self, forKey: .mobility) {
            mobility = keys
        } else if let positions = try? container.decode(Set<Int>.self, forKey: .mobility) {
            mobility = Set(positions.compactMap { Plan.mobilityKey(legacyIndex: $0) })
        } else {
            mobility = []
        }
    }

    public var isEmpty: Bool {
        done.isEmpty && !fuelHit && mobility.isEmpty && note.isEmpty && dayOverride == nil
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

    /// Bumped only for a change decoding-as-default can't absorb — a rename
    /// or a type change, never a plain addition. Every backup written
    /// before this field existed decodes as 1.
    public var schemaVersion: Int = 1

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
    /// Swaps a small number of specific exercises for knee-friendlier
    /// versions — see `Knee.swift`.
    public var kneeCareMode: Bool = false

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

    // MARK: Hevy

    /// This app's liftID → Hevy's `exercise_template_id`. See `HevyImport`.
    public var hevyMapping: [String: String] = [:]
    /// The newest Hevy workout id already imported.
    public var hevyLastImportedWorkoutID: String?
    /// The newest body-measurement date already imported.
    public var hevyLastImportedMeasurementDate: String?
    /// The one Hevy routine folder this app's pushed routines live in.
    public var hevyRoutineFolderID: String?
    /// Weekday (as a string key) → the Hevy routine id already pushed for
    /// it, so re-pushing updates in place instead of duplicating.
    public var hevyRoutineIDs: [String: String] = [:]

    // MARK: Clock

    /// The day the app considers "now". Injected rather than read from the
    /// system so every derived number is reproducible in a test.
    public var today: String

    public init(today: String = DateKit.todayKey) {
        self.today = today
        self.startDate = today
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, startDate, pyramidCap, vestKg, vestPhase, barKg, calAdjust,
             heightCm, birthYear, deloadSnooze, kneeCareMode,
             weights, waist, logs, lifts, pyramidLog, deloadLog, off, recovery,
             mindStartDate, mindUnlocked, mindLogs, mindTargets, mindLadderLog, mindLadderCap,
             charismaIx, charismaSince,
             hevyMapping, hevyLastImportedWorkoutID, hevyLastImportedMeasurementDate,
             hevyRoutineFolderID, hevyRoutineIDs,
             today
    }

    /// Hand-written, unlike every other `Codable` type in this file, because
    /// this one is the whole exported backup — and the synthesized
    /// conformance it replaces treated every non-Optional property as a
    /// required JSON key. Adding a single field in some future version would
    /// have broken every backup already sitting on someone's disk, for a
    /// file that's otherwise perfectly valid: `import` is exactly the
    /// operation that must tolerate a degree of forward drift it never
    /// controlled. Each field now falls back to its own ordinary default —
    /// the same one its declaration already carries — when the key is
    /// missing, rather than throwing.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

        today = try c.decodeIfPresent(String.self, forKey: .today) ?? DateKit.todayKey
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate) ?? today
        pyramidCap = try c.decodeIfPresent(Int.self, forKey: .pyramidCap) ?? 4
        vestKg = try c.decodeIfPresent(Double.self, forKey: .vestKg)
        vestPhase = try c.decodeIfPresent(Int.self, forKey: .vestPhase) ?? 0
        barKg = try c.decodeIfPresent(Double.self, forKey: .barKg) ?? 20
        calAdjust = try c.decodeIfPresent(Int.self, forKey: .calAdjust) ?? 0
        heightCm = try c.decodeIfPresent(Int.self, forKey: .heightCm)
        birthYear = try c.decodeIfPresent(Int.self, forKey: .birthYear)
        deloadSnooze = try c.decodeIfPresent(String.self, forKey: .deloadSnooze)
        kneeCareMode = try c.decodeIfPresent(Bool.self, forKey: .kneeCareMode) ?? false

        weights = try c.decodeIfPresent([WeightRecord].self, forKey: .weights) ?? []
        waist = try c.decodeIfPresent([WaistRecord].self, forKey: .waist) ?? []
        logs = try c.decodeIfPresent([String: DayRecord].self, forKey: .logs) ?? [:]
        lifts = try c.decodeIfPresent([String: [LiftRecord]].self, forKey: .lifts) ?? [:]
        pyramidLog = try c.decodeIfPresent([String: PyramidRecord].self, forKey: .pyramidLog) ?? [:]
        deloadLog = try c.decodeIfPresent(Set<String>.self, forKey: .deloadLog) ?? []
        off = try c.decodeIfPresent([String: OffKind].self, forKey: .off) ?? [:]
        recovery = try c.decodeIfPresent([String: RecoveryRecord].self, forKey: .recovery) ?? [:]

        mindStartDate = try c.decodeIfPresent(String.self, forKey: .mindStartDate)
        mindUnlocked = try c.decodeIfPresent(Int.self, forKey: .mindUnlocked) ?? 1
        mindLogs = try c.decodeIfPresent([String: MindDayRecord].self, forKey: .mindLogs) ?? [:]
        mindTargets = try c.decodeIfPresent([String: Int].self, forKey: .mindTargets) ?? [:]
        mindLadderLog = try c.decodeIfPresent(Set<String>.self, forKey: .mindLadderLog) ?? []
        mindLadderCap = try c.decodeIfPresent(Int.self, forKey: .mindLadderCap) ?? 1
        charismaIx = try c.decodeIfPresent(Int.self, forKey: .charismaIx) ?? 0
        charismaSince = try c.decodeIfPresent(String.self, forKey: .charismaSince)

        hevyMapping = try c.decodeIfPresent([String: String].self, forKey: .hevyMapping) ?? [:]
        hevyLastImportedWorkoutID = try c.decodeIfPresent(String.self, forKey: .hevyLastImportedWorkoutID)
        hevyLastImportedMeasurementDate = try c.decodeIfPresent(String.self, forKey: .hevyLastImportedMeasurementDate)
        hevyRoutineFolderID = try c.decodeIfPresent(String.self, forKey: .hevyRoutineFolderID)
        hevyRoutineIDs = try c.decodeIfPresent([String: String].self, forKey: .hevyRoutineIDs) ?? [:]
    }

    public var todayDow: Int { DateKit.dow(key: today) ?? 0 }

    // MARK: Convenience accessors

    public func day(_ date: String) -> DayRecord {
        logs[date] ?? DayRecord()
    }

    /// Which weekday's plan actually applies to this date — that date's own
    /// override if one was set, otherwise its calendar weekday. Every lookup
    /// that decides which exercises, mobility focus or fuel target a date
    /// gets should go through this rather than `DateKit.dow` directly, so a
    /// swapped day stays consistent everywhere it's read.
    public func effectiveDow(on date: String) -> Int {
        day(date).dayOverride ?? DateKit.dow(key: date) ?? 0
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
