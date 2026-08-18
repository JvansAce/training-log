import Foundation

/// Turns fetched Hevy workouts into what this app actually stores — lift
/// sets and ticked checklist keys — using the liftID ↔ `exercise_template_id`
/// mapping from Setup. Pure and testable on purpose: the network call and
/// the SwiftData write both live in `AppStore`/`HevyClient`, this is just
/// the translation between the two shapes.
public enum HevyImport {

    public struct Result: Equatable {
        /// One entry per (liftID, date) actually logged. Each date's sets
        /// fully replace whatever this app currently has for that date and
        /// lift, the same as typing them in by hand would.
        public var sets: [SetEntry] = []
        /// The checklist item to tick for each date a matched lift was
        /// logged — the day's own item key, from `Plan.day`.
        public var ticks: Set<Tick> = []
        /// The newest workout actually processed — persisted so the next
        /// sync resumes from here instead of re-importing everything.
        public var lastWorkoutID: String?
        /// `exercise_template_id`s that appeared in a workout but match no
        /// mapped liftID — surfaced so Setup can say "3 exercises in your
        /// last sync aren't mapped yet" rather than silently dropping them.
        public var unmatchedTemplateIDs: Set<String> = []

        public struct SetEntry: Equatable {
            public var liftID: String
            public var date: String
            public var sets: [LiftSet]
        }

        public struct Tick: Hashable {
            public var date: String
            public var key: String
        }
    }

    /// `mapping` is liftID → Hevy `exercise_template_id`, built by searching
    /// the user's own catalog (see `HevyClient.fetchAllExerciseTemplates`) —
    /// never a guessed table. `workouts` must already be oldest-first (see
    /// `HevyClient.fetchNewWorkouts`).
    public static func apply(_ workouts: [HevyWorkout], mapping: [String: String]) -> Result {
        var result = Result()
        guard !workouts.isEmpty else { return result }

        // Built by walking `Plan.liftIDs`'s own stable order, not the
        // mapping dictionary's iteration order (hash-randomised per
        // process) — so if a mapping mistake ever points two liftIDs at
        // the same Hevy exercise, the collision resolves the same way on
        // every run instead of flipping between app launches. Matches
        // `Plan.liftIDs`'s own "an id on two days belongs to the first"
        // rule.
        var reverseMapping: [String: String] = [:]
        for liftID in Plan.liftIDs {
            guard let templateID = mapping[liftID], reverseMapping[templateID] == nil else { continue }
            reverseMapping[templateID] = liftID
        }
        let keyForLiftID: [String: String] = Plan.order.reduce(into: [:]) { acc, dow in
            for item in Plan.day(dow).items {
                if let id = item.liftID, acc[id] == nil { acc[id] = item.key }
            }
        }

        // Keyed by liftID + date, and appended into rather than a fresh
        // entry per exercise block: a workout that logs the same lift in
        // two separate blocks (straight sets, then an AMRAP set logged on
        // its own, say) has to merge into one entry — otherwise the second
        // block silently replaces the first the moment `AppStore` writes it.
        var combined: [String: Result.SetEntry] = [:]
        var order: [String] = []

        for workout in workouts {
            guard let date = dateKey(workout.startTime) else { continue }
            for exercise in workout.exercises {
                guard let liftID = reverseMapping[exercise.exerciseTemplateID] else {
                    result.unmatchedTemplateIDs.insert(exercise.exerciseTemplateID)
                    continue
                }
                let sets = exercise.sets
                    .filter { $0.type != "warmup" }
                    .compactMap { raw -> LiftSet? in
                        guard let reps = raw.reps, reps > 0 else { return nil }
                        let kg = raw.weightKg == 0 ? nil : raw.weightKg
                        return LiftSet(kg: kg, reps: reps)
                    }
                guard !sets.isEmpty else { continue }
                let mapKey = "\(liftID)|\(date)"
                if var existing = combined[mapKey] {
                    existing.sets.append(contentsOf: sets)
                    combined[mapKey] = existing
                } else {
                    combined[mapKey] = .init(liftID: liftID, date: date, sets: sets)
                    order.append(mapKey)
                }
                if let key = keyForLiftID[liftID] {
                    result.ticks.insert(.init(date: date, key: key))
                }
            }
        }
        result.sets = order.compactMap { combined[$0] }
        result.lastWorkoutID = workouts.last?.id
        return result
    }

    private static func dateKey(_ isoTimestamp: String) -> String? {
        WhoopDay.parse(isoTimestamp).map(DateKit.key)
    }

    // MARK: - Body measurements

    public struct MeasurementResult: Equatable {
        public var weights: [WeightRecord] = []
        public var waist: [WaistRecord] = []
        /// The newest date actually seen, regardless of whether it produced
        /// a usable reading — an out-of-range value below still moves the
        /// cursor forward so a sync doesn't keep re-fetching it forever.
        public var lastDate: String?
    }

    /// Sanity-bounded the same way the manual weigh-in and waist fields on
    /// Today already are — a decoding mismatch on an unconfirmed field name
    /// (see `HevyBodyMeasurement`) should read as "nothing usable here",
    /// not as a wildly implausible number landing in the weight trend.
    private static let plausibleBodyweightKg = 40.0...200
    private static let plausibleWaistCm = 50.0...150

    public static func applyMeasurements(_ entries: [HevyBodyMeasurement]) -> MeasurementResult {
        var result = MeasurementResult()
        for entry in entries {
            if let kg = entry.weightKg, plausibleBodyweightKg.contains(kg) {
                result.weights.append(WeightRecord(date: entry.date, kg: kg, seed: false))
            }
            if let cm = entry.waistCm, plausibleWaistCm.contains(cm) {
                result.waist.append(WaistRecord(date: entry.date, cm: cm))
            }
        }
        result.lastDate = entries.last?.date
        return result
    }

    // MARK: - Routine push

    /// The four lifting days' `Exercise` list, translated into a Hevy
    /// routine — target rep ranges from `Lifts.parseScheme`, set counts
    /// from `Lifts.prescribedSets`, so the routine reads the same
    /// prescription this app's own checklist does rather than a second,
    /// separately-maintained copy of it. An item with no liftID (a warm-up)
    /// or no entry yet in `mapping` is simply left out — the routine ends
    /// up with whatever of the day *is* mapped, not blocked on all of it
    /// being mapped at once.
    public static func routineInput(for dow: Int, mapping: [String: String], folderID: String?) -> HevyRoutineInput {
        let day = Plan.day(dow)
        let exercises: [HevyRoutineExerciseInput] = day.items.compactMap { item -> HevyRoutineExerciseInput? in
            guard let liftID = item.liftID, let templateID = mapping[liftID] else { return nil }
            let count = min(Lifts.maxSets, max(1, Lifts.prescribedSets(item.prescription) ?? 1))
            let scheme = Lifts.parseScheme(item.prescription)
            let sets = (0..<count).map { _ in
                HevyRoutineSetInput(repRange: scheme.map { .init(start: $0.low, end: $0.high) })
            }
            return HevyRoutineExerciseInput(exerciseTemplateID: templateID, sets: sets, restSeconds: day.restSeconds)
        }
        return HevyRoutineInput(title: day.title, folderID: folderID.flatMap(Int.init), exercises: exercises)
    }
}

/// Search terms for the one-time "match my exercises" pass — plain English
/// words to look up in the user's own Hevy catalog, not exercise IDs. Every
/// match this produces is still shown for review and editable in Setup
/// before anything is saved; these are just a reasonable starting guess per
/// lift, in the same order `Plan.liftIDs` lists them.
public enum HevySearchTerms {
    public static let byLiftID: [String: String] = [
        "wpullup": "weighted pull up",
        "incline": "incline bench press",
        "row": "barbell row",
        "ohp": "shoulder press",
        "dips": "dip",
        "facepull": "face pull",
        "lat": "lateral raise",
        "squat": "squat",
        "rdl": "romanian deadlift",
        "legcurl": "leg curl",
        "bss": "bulgarian split squat",
        "legpress": "leg press",
        "calf": "calf raise",
        "hlr": "hanging leg raise",
        "pullup": "pull up",
        "flat": "bench press",
        "crow": "cable row",
        "curl": "dumbbell curl",
        "tricep": "overhead triceps extension",
        "boxjump": "box jump",
        "hipthrust": "hip thrust",
        "fsquat": "front squat",
        "ext": "back extension",
        "crunch": "crunch",
    ]

    /// Every candidate whose title contains `term`, shortest first: Hevy's
    /// catalog lists variants ("Bench Press (Barbell)", "Bench Press
    /// (Dumbbell)", "Close Bench Press (Barbell)") and the plainest one is
    /// usually the intended match, not whichever the catalog happens to
    /// list first. Shared by the one-time auto-match pass and the manual
    /// search sheet in `HevyMappingView`, so the ranking rule only lives
    /// in one place.
    public static func matches(for term: String, in candidates: [HevyExerciseTemplate]) -> [HevyExerciseTemplate] {
        candidates
            .filter { $0.title.range(of: term, options: .caseInsensitive) != nil }
            .sorted { $0.title.count < $1.title.count }
    }

    /// The single best guess — see `matches`.
    public static func bestMatch(for term: String, in candidates: [HevyExerciseTemplate]) -> HevyExerciseTemplate? {
        matches(for: term, in: candidates).first
    }
}
