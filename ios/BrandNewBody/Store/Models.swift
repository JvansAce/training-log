import Foundation
import SwiftData

/// The persisted schema.
///
/// Three rules shape all of it, and all three come from CloudKit rather than
/// from taste:
///
/// 1. **Every property has a default.** CloudKit has no notion of a required
///    field, so SwiftData refuses to mirror a model with a non-optional,
///    default-less property. The initialisers still demand real values — the
///    defaults exist for the schema, not for callers.
/// 2. **No unique constraints and no relationships.** `.unique` is
///    unsupported by the CloudKit mirror, so uniqueness is enforced in
///    `AppStore` on write instead (fetch-then-update, never blind insert).
/// 3. **One record per day, per lift-day, per practice-day.** This is the
///    important one. The web app needed several hundred lines of server-side
///    merge logic plus a tombstone system, because it synced the whole log as
///    one JSON blob and two devices editing different days still collided.
///    Fine-grained records make CloudKit's per-record last-writer-wins do
///    exactly the same job for free: a set logged on the phone in the garage
///    and a weigh-in typed on the iPad upstairs touch different records and
///    both survive. Deletions propagate properly too, which is what the
///    tombstones existed to fake.
///
/// Awkwardly-shaped values (arrays of structs, dictionaries) are stored as
/// JSON `Data` behind a computed accessor rather than relying on SwiftData to
/// compose them, because a composite attribute that fails to mirror shows up
/// as silent sync failure rather than as a build error.
@Model
final class WeightEntry {
    var date: String = ""
    var kg: Double = 0
    /// The 79 kg placeholder a fresh install starts with. Marked so the UI
    /// doesn't tell a brand-new user they already weighed in this morning.
    var seed: Bool = false

    init(date: String, kg: Double, seed: Bool = false) {
        self.date = date
        self.kg = kg
        self.seed = seed
    }
}

@Model
final class WaistEntry {
    var date: String = ""
    var cm: Double = 0

    init(date: String, cm: Double) {
        self.date = date
        self.cm = cm
    }
}

@Model
final class DayEntry {
    var date: String = ""
    /// Item keys such as `tu-row`, never indices into the day's list.
    var doneKeys: [String] = []
    var fuelHit: Bool = false
    var mobilityKeys: [String] = []
    /// Mobility ticks as they were once stored: positions in the drill list.
    /// Read once by `AppStore.migrateMobilityIndices()` and then emptied — kept
    /// in the schema so an existing install's ticks survive the change rather
    /// than being silently dropped on first launch.
    var mobilityIndices: [Int] = []
    var note: String = ""
    /// See `DayRecord.dayOverride`.
    var dayOverrideDow: Int?

    init(date: String) {
        self.date = date
    }

    var record: DayRecord {
        DayRecord(done: Set(doneKeys), fuelHit: fuelHit,
                  mobility: Set(mobilityKeys), note: note, dayOverride: dayOverrideDow)
    }

    func apply(_ record: DayRecord) {
        doneKeys = record.done.sorted()
        fuelHit = record.fuelHit
        mobilityKeys = record.mobility.sorted()
        note = record.note
        dayOverrideDow = record.dayOverride
    }

    /// Legacy ticks count as content, so an un-migrated row is never mistaken
    /// for a blank one and deleted before it can be translated.
    var isEmpty: Bool { record.isEmpty && mobilityIndices.isEmpty }
}

@Model
final class LiftEntry {
    var liftID: String = ""
    var date: String = ""
    /// JSON `[LiftSet]`.
    var setsData: Data = Data()

    init(liftID: String, date: String, sets: [LiftSet] = []) {
        self.liftID = liftID
        self.date = date
        self.setsData = JSONCoding.encode(sets)
    }

    var sets: [LiftSet] {
        get { JSONCoding.decode(setsData, default: []) }
        set { setsData = JSONCoding.encode(newValue) }
    }
}

@Model
final class PyramidEntry {
    var date: String = ""
    var cap: Int = 4
    var vestKg: Double?

    init(date: String, cap: Int, vestKg: Double?) {
        self.date = date
        self.cap = cap
        self.vestKg = vestKg
    }
}

@Model
final class DeloadEntry {
    /// The day the deload week started.
    var date: String = ""

    init(date: String) {
        self.date = date
    }
}

@Model
final class OffDayEntry {
    var date: String = ""
    /// `OffKind.rawValue`. Stored as a string because a raw-value enum is one
    /// more thing that has to mirror cleanly, and this one never needs to be
    /// queried on.
    var kindRaw: String = OffKind.ill.rawValue

    init(date: String, kind: OffKind) {
        self.date = date
        self.kindRaw = kind.rawValue
    }

    var kind: OffKind {
        get { OffKind(rawValue: kindRaw) ?? .ill }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class RecoveryEntry {
    var date: String = ""
    var recovery: Int?
    var strain: Double?
    var sleepPct: Int?
    var hrvMs: Double?
    var restingHR: Int?

    init(date: String) {
        self.date = date
    }

    var record: RecoveryRecord {
        RecoveryRecord(recovery: recovery, strain: strain, sleepPct: sleepPct,
                       hrvMs: hrvMs, restingHR: restingHR)
    }

    func apply(_ record: RecoveryRecord) {
        recovery = record.recovery
        strain = record.strain
        sleepPct = record.sleepPct
        hrvMs = record.hrvMs
        restingHR = record.restingHR
    }
}

@Model
final class MindDayEntry {
    var date: String = ""
    var doneKeys: [String] = []
    /// JSON `[String: Int]` — practice key to minutes logged.
    var minsData: Data = Data()
    var journal: String = ""

    init(date: String) {
        self.date = date
    }

    var record: MindDayRecord {
        MindDayRecord(done: Set(doneKeys),
                      mins: JSONCoding.decode(minsData, default: [:]),
                      journal: journal)
    }

    func apply(_ record: MindDayRecord) {
        doneKeys = record.done.sorted()
        minsData = JSONCoding.encode(record.mins)
        journal = record.journal
    }

    var isEmpty: Bool { record.isEmpty }
}

@Model
final class LadderEntry {
    /// The Saturday the ladder was cleared.
    var date: String = ""

    init(date: String) {
        self.date = date
    }
}

/// Everything that is a setting rather than a dated record.
///
/// A singleton by convention — `AppStore` fetches the first row and creates
/// one if the table is empty. It cannot be a singleton by constraint, because
/// `.unique` doesn't mirror to CloudKit; if two devices ever race and create
/// two, the store keeps the oldest and folds the other away rather than
/// showing the user two sets of settings.
@Model
final class AppSettings {
    /// Tie-break for the duplicate case above: oldest wins, deterministically
    /// on every device.
    var createdAt: Date = Date.distantPast

    var startDate: String = ""
    var pyramidCap: Int = 4
    /// nil means "track my bodyweight".
    var vestKg: Double?
    var vestPhase: Int = 0
    var barKg: Double = 20
    var calAdjust: Int = 0
    var heightCm: Int?
    var birthYear: Int?
    var deloadSnooze: String?
    /// Swaps a small number of specific exercises for knee-friendlier
    /// versions — see `Knee.swift`. Off by default so nobody's plan changes
    /// underneath them until they turn it on.
    var kneeCareMode: Bool = false

    var mindStartDate: String?
    var mindUnlocked: Int = 1
    /// JSON `[String: Int]` — practice key to current minute target.
    var mindTargetsData: Data = Data()
    var mindLadderCap: Int = 1
    var charismaIx: Int = 0
    var charismaSince: String?

    init(startDate: String, createdAt: Date = Date()) {
        self.startDate = startDate
        self.createdAt = createdAt
    }

    var mindTargets: [String: Int] {
        get { JSONCoding.decode(mindTargetsData, default: [:]) }
        set { mindTargetsData = JSONCoding.encode(newValue) }
    }
}

/// JSON in and out of a `Data` column, with failure treated as "empty" rather
/// than as a crash. A single unreadable blob costs one day's detail; a trap
/// here would cost the whole app on launch.
enum JSONCoding {
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ data: Data, default fallback: T) -> T {
        guard !data.isEmpty else { return fallback }
        return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
    }
}

enum SchemaV1 {
    static let models: [any PersistentModel.Type] = [
        WeightEntry.self, WaistEntry.self, DayEntry.self, LiftEntry.self,
        PyramidEntry.self, DeloadEntry.self, OffDayEntry.self, RecoveryEntry.self,
        MindDayEntry.self, LadderEntry.self, AppSettings.self,
    ]
}
