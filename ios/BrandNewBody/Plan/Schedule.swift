import SwiftUI

/// One line on a day's checklist. `id` is what gives it inline `kg × reps`
/// logging — leave it off and the item is a warm-up you can only tick.
public struct Exercise: Identifiable, Hashable, Sendable {
    /// Stable tick key, e.g. `tu-row`. Never an index into the day's list.
    public let key: String
    public var id: String { key }
    public let name: String
    /// The prescription, e.g. `4 × 8–10`. Parsed for progression targets, so
    /// the programme text stays the single source of truth rather than being
    /// duplicated into a second table that can drift.
    public let prescription: String
    /// Reps in reserve, shown as a chip.
    public let rir: String?
    /// Logging id. Two days can share one (`lat`, `calf`) on purpose: one
    /// combined progression history rather than two half-pictures.
    public let liftID: String?
    /// Barbell lift, so the plate maths is worth showing.
    public let isBarbell: Bool

    public init(key: String, name: String, prescription: String = "",
                rir: String? = nil, liftID: String? = nil, isBarbell: Bool = false) {
        self.key = key
        self.name = name
        self.prescription = prescription
        self.rir = rir
        self.liftID = liftID
        self.isBarbell = isBarbell
    }
}

public struct TrainingDay: Identifiable, Sendable {
    /// 0 = Sunday, matching `DateKit.dow`.
    public let dow: Int
    public var id: Int { dow }
    public let label: String
    public let colorHex: String
    public let title: String
    public let tag: String
    public let note: String
    /// Prescribed rest between sets, in seconds. Its presence is what puts the
    /// rest-timer button on the day.
    public let restSeconds: Int?
    public let items: [Exercise]

    public var color: Color { Color(hex: colorHex) }
}

public enum Plan {

    /// Monday-first, matching how the plan is written and how `weekStart`
    /// slices the calendar.
    public static let order = [1, 2, 3, 4, 5, 6, 0]

    public static let schedule: [Int: TrainingDay] = {
        let days: [TrainingDay] = [
            TrainingDay(
                dow: 1, label: "MO", colorHex: "4C7BE8", title: "Tennis", tag: "Athletic day",
                note: "Your conditioning is covered. No lifting today. Carb meal 2–3h before, shake after.",
                restSeconds: nil,
                items: [
                    Exercise(key: "mo-warm", name: "Dynamic warm-up",
                             prescription: "leg swings · lunge w/ rotation · shoulder circles · 3 short sprints"),
                    Exercise(key: "mo-tennis", name: "Tennis", prescription: "play"),
                    Exercise(key: "mo-core", name: "Core finisher",
                             prescription: "ab wheel or plank 3×45s · Pallof press 3×10 / side"),
                    Exercise(key: "mo-shake", name: "Post-match shake",
                             prescription: "30g whey + 300ml milk + banana"),
                ]),

            TrainingDay(
                dow: 2, label: "TU", colorHex: "E23B3B", title: "Upper · Strength", tag: "Rest 2–3 min",
                note: "The heavy day. Add weight or a rep whenever you hit the top of the range.",
                restSeconds: 150,
                items: [
                    Exercise(key: "tu-warm", name: "Band pull-aparts + arm circles", prescription: "warm-up 2×15"),
                    Exercise(key: "tu-wpullup", name: "Weighted pull-ups", prescription: "4 × 5–8 — add weight at 8",
                             rir: "1–3", liftID: "wpullup"),
                    Exercise(key: "tu-incline", name: "Incline DB press", prescription: "4 × 8–10",
                             rir: "1–2", liftID: "incline"),
                    Exercise(key: "tu-row", name: "Barbell or DB row", prescription: "4 × 8–10",
                             rir: "1–2", liftID: "row", isBarbell: true),
                    Exercise(key: "tu-ohp", name: "Overhead press", prescription: "3 × 8–10",
                             rir: "1–2", liftID: "ohp", isBarbell: true),
                    Exercise(key: "tu-dips", name: "Dips", prescription: "3 × 8–12", rir: "1–2", liftID: "dips"),
                    // Shares the `lat` id with Friday on purpose.
                    Exercise(key: "tu-lat", name: "Lateral raises", prescription: "3 × 12–15 — strict, no swing",
                             rir: "0–2", liftID: "lat"),
                ]),

            TrainingDay(
                dow: 3, label: "WE", colorHex: "E23B3B", title: "Lower · Strength", tag: "Rest 2–3 min",
                note: "If Monday tennis left you wrecked, swap this with Tuesday.",
                restSeconds: 150,
                items: [
                    Exercise(key: "we-warm", name: "Leg swings · hip circles · 90/90", prescription: "warm-up 5 min"),
                    Exercise(key: "we-squat", name: "Squat or trap bar deadlift", prescription: "4 × 5–8",
                             rir: "1–3", liftID: "squat", isBarbell: true),
                    Exercise(key: "we-rdl", name: "Romanian deadlift", prescription: "3 × 8–10",
                             rir: "1–2", liftID: "rdl", isBarbell: true),
                    // The RDL is pure hip extension. The short head of the biceps
                    // femoris only crosses the knee, so it barely works in any
                    // hinge — this is the movement that actually trains it.
                    Exercise(key: "we-legcurl", name: "Leg curl or Nordic", prescription: "3 × 8–12",
                             rir: "0–2", liftID: "legcurl"),
                    Exercise(key: "we-bss", name: "Bulgarian split squat", prescription: "3 × 10 / leg",
                             rir: "1–2", liftID: "bss"),
                    Exercise(key: "we-calf", name: "Calf raises", prescription: "3 × 15", rir: "0–2", liftID: "calf"),
                    Exercise(key: "we-hlr", name: "Hanging leg raises",
                             prescription: "3 × 12 — add a dumbbell between the feet when 12 is easy",
                             rir: "0–2", liftID: "hlr"),
                ]),

            TrainingDay(
                dow: 4, label: "TH", colorHex: "D9A13B", title: "Easy Cardio", tag: "Zone 2 only",
                note: "Conversational pace. If recovery is red, take the full rest instead — this is the first thing to drop.",
                restSeconds: nil,
                items: [
                    Exercise(key: "th-z2", name: "Zone 2", prescription: "20–35 min easy jog, bike or brisk hike"),
                    Exercise(key: "th-mob", name: "Daily mobility", prescription: "see below"),
                ]),

            TrainingDay(
                dow: 5, label: "FR", colorHex: "E23B3B", title: "Upper · Volume", tag: "Rest 60–90s",
                note: "Chase the pump here. Side and rear delts are what make the suit fit — and they only get trained if you actually load them.",
                restSeconds: 75,
                items: [
                    Exercise(key: "fr-warm", name: "Band pull-aparts", prescription: "warm-up 2×15"),
                    Exercise(key: "fr-pullup", name: "Pull-ups", prescription: "4 × max reps", rir: "0", liftID: "pullup"),
                    Exercise(key: "fr-flat", name: "Flat DB press", prescription: "4 × 10–12", rir: "1–2", liftID: "flat"),
                    Exercise(key: "fr-crow", name: "Cable or band row", prescription: "3 × 12", rir: "1–2", liftID: "crow"),
                    Exercise(key: "fr-lat", name: "Lateral raises", prescription: "4 × 15", rir: "0–1", liftID: "lat"),
                    // Promoted from a warm-up to real loaded sets — rear delts had
                    // no working volume anywhere in the week.
                    Exercise(key: "fr-facepull", name: "Face pulls",
                             prescription: "3 × 15 — load it, pause at the face", rir: "0–2", liftID: "facepull"),
                    Exercise(key: "fr-arms", name: "Curls + triceps", prescription: "3 × 12 each",
                             rir: "0–1", liftID: "arms"),
                ]),

            TrainingDay(
                dow: 6, label: "SA", colorHex: "E23B3B", title: "Lower + Pyramid", tag: "Treat it as a session",
                note: "The pyramid is a full session element, not an add-on. Alternate the two ways of progressing it: one week add a round, the next keep the same rounds and wear the vest.",
                restSeconds: 180,
                items: [
                    Exercise(key: "sa-fsquat", name: "Front or goblet squat", prescription: "4 × 8",
                             rir: "1–2", liftID: "fsquat", isBarbell: true),
                    Exercise(key: "sa-boxjump", name: "Box jumps",
                             prescription: "4 × 6 explosive, full rest — stop the set if height drops", liftID: "boxjump"),
                    // Saturday used to be entirely quad-dominant, which left the
                    // hamstrings and glutes on Wednesday alone. A hip extension
                    // here fixes the frequency without repeating Wednesday's hinge.
                    Exercise(key: "sa-ext", name: "45° back extension",
                             prescription: "3 × 10–12 — hip thrust or Nordic if no bench", rir: "1–2", liftID: "ext"),
                    Exercise(key: "sa-calf", name: "Calf raises", prescription: "3 × 12–15 — pause at the top",
                             rir: "0–2", liftID: "calf"),
                    // Loaded flexion, so abs get progressive overload like
                    // anything else. The pyramid's sit-ups are endurance work.
                    Exercise(key: "sa-crunch", name: "Cable crunch or weighted sit-up",
                             prescription: "3 × 10–15 — add load, not reps", rir: "0–2", liftID: "crunch"),
                    Exercise(key: "sa-pyramid", name: "PYRAMID", prescription: "", liftID: "pyramid"),
                ]),

            TrainingDay(
                dow: 0, label: "SU", colorHex: "868FA6", title: "Full Rest", tag: "Growth happens here",
                note: "Nothing structured. Walk, stretch, eat. Long mobility is the only box worth ticking.",
                restSeconds: nil,
                items: [
                    Exercise(key: "su-mob", name: "Long mobility (20 min)",
                             prescription: "deep squat · couch stretch · thoracic rotations · pigeon · calves"),
                    Exercise(key: "su-weigh", name: "Weekly weigh-in average check", prescription: "see Progress"),
                ]),
        ]
        return Dictionary(uniqueKeysWithValues: days.map { ($0.dow, $0) })
    }()

    public static func day(_ dow: Int) -> TrainingDay {
        // Every value 0...6 is present; the fallback exists only so callers
        // never have to unwrap.
        schedule[dow] ?? schedule[0]!
    }

    /// Every loggable lift id, in the order the week presents them. An id on
    /// two days belongs to the first day it appears on.
    public static let liftIDs: [String] = {
        var seen = Set<String>()
        var out: [String] = []
        for d in order {
            for item in day(d).items {
                guard let id = item.liftID, id != "pyramid", !seen.contains(id) else { continue }
                seen.insert(id)
                out.append(id)
            }
        }
        return out
    }()

    /// Display name for a lift id, taken from the first day it appears on.
    public static let liftNames: [String: String] = {
        var out: [String: String] = [:]
        for d in order {
            for item in day(d).items {
                guard let id = item.liftID, out[id] == nil else { continue }
                out[id] = item.name
            }
        }
        return out
    }()

    /// Keyed like the exercises, and for the same reason: mobility ticks used
    /// to be stored as positions in this list, so inserting a drill silently
    /// changed what every past tick referred to. That is the exact defect
    /// session ticks were fixed for in the web app — and never fixed here.
    public struct Mobility: Identifiable, Sendable {
        public let key: String
        public var id: String { key }
        public let name: String
        public let prescription: String
    }

    public static let mobility: [Mobility] = [
        .init(key: "mob-squat", name: "Deep squat hold", prescription: "2 × 1 min"),
        .init(key: "mob-couch", name: "Couch stretch", prescription: "1 min / side"),
        .init(key: "mob-dislocate", name: "Shoulder dislocates", prescription: "2 × 10, band or broomstick"),
        .init(key: "mob-hang", name: "Dead hang", prescription: "2 × 30–45s"),
    ]

    /// The drill order as it stood while ticks were positions. **Frozen.** New
    /// drills go on the end of `mobility`; nothing is ever inserted here, or
    /// every already-recorded tick would translate to the wrong drill.
    /// `testMobilityKeysAreStableAndUnique` fails if the two drift apart.
    private static let legacyMobilityOrder = [
        "mob-squat", "mob-couch", "mob-dislocate", "mob-hang",
    ]

    /// Translates an old positional tick, or nil if the position never existed.
    public static func mobilityKey(legacyIndex index: Int) -> String? {
        legacyMobilityOrder.indices.contains(index) ? legacyMobilityOrder[index] : nil
    }

    public struct Meal: Identifiable, Sendable {
        public var id: String { heading }
        public let heading: String
        public let kcal: String
        public let detail: String
    }

    public static let meals: [Meal] = [
        .init(heading: "Breakfast", kcal: "~750 kcal",
              detail: "100g oats + 400ml whole milk, banana, 30g nuts, 2 eggs"),
        .init(heading: "Lunch", kcal: "~800 kcal",
              detail: "150–180g chicken/beef/fish, 120g rice dry, veg + 1 EL olive oil"),
        .init(heading: "Post-workout shake", kcal: "~400 kcal",
              detail: "30g whey + 300ml whole milk + banana"),
        .init(heading: "Dinner", kcal: "~800 kcal",
              detail: "Protein + big carb portion + veg. Vollkornbrot with Quark works too."),
        .init(heading: "Evening", kcal: "~450 kcal",
              detail: "250g Magerquark with honey/berries + handful of nuts"),
    ]

    public static let addIns: [String] = [
        "Weighted vest hike, 60–90 min",
        "Handstand practice, 5 min after upper days",
        "Rope climbs or towel pull-ups",
        "Bouldering session",
        "Sprints: 6–8 × 60m, full rest",
        "\"Murph light\" with vest — quarterly benchmark",
    ]

    /// Add-ins open at week 12, once the four lifting days are habit.
    public static let addInWeek = 12

    public static let dayNames: [Int: String] = [
        0: "Sunday", 1: "Monday", 2: "Tuesday", 3: "Wednesday",
        4: "Thursday", 5: "Friday", 6: "Saturday",
    ]
}
