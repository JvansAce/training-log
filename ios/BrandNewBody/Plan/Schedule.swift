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
    /// The lift is loaded by your own body, so load can go negative: a band
    /// or an assist machine taking weight off. Nothing else can — a barbell
    /// row does not go below an empty bar.
    public let isBodyweight: Bool

    public init(key: String, name: String, prescription: String = "",
                rir: String? = nil, liftID: String? = nil, isBarbell: Bool = false,
                isBodyweight: Bool = false) {
        self.key = key
        self.name = name
        self.prescription = prescription
        self.rir = rir
        self.liftID = liftID
        self.isBarbell = isBarbell
        self.isBodyweight = isBodyweight
    }

    /// `name` as written for anything else; for a bodyweight lift, adjusted
    /// for whichever side of bodyweight it's currently logged on. See
    /// `Lifts.displayName`.
    public func displayName(_ state: LogState) -> String {
        guard isBodyweight, let liftID else { return name }
        return Lifts.displayName(state, id: liftID, base: name)
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
                dow: 2, label: "TU", colorHex: "E23B3B", title: "Upper · Strength", tag: "Rest 2–3 min / 60–90s",
                note: """
                    The heavy day. Add weight or a rep whenever you hit the top of the range. That 2–3 min \
                    rest is for the four main lifts — face pulls and lateral raises are fine at 60–90s.
                    """,
                restSeconds: 150,
                items: [
                    Exercise(key: "tu-warm", name: "Band pull-aparts + arm circles", prescription: "warm-up 2×15"),
                    // "· heavy" is not decoration: this and Friday's pull-up are
                    // separate liftIDs with separate histories on purpose, and
                    // renaming this one from "Weighted pull-ups" to plain
                    // "Pull-ups" — so `displayName` could prefix it correctly —
                    // made the two indistinguishable everywhere `Plan.liftNames`
                    // is what gets shown, notably the weekly "beaten this week"
                    // list, which carries no day context to tell them apart.
                    // 4 sets down to 3: back and lat were the one muscle group
                    // the review found genuinely over-dosed at 16–17 sets a
                    // week, and the pyramid quietly adds ten more pull-ups on
                    // top of that — the same reasoning that took the row from
                    // 4 to 3, applied consistently.
                    Exercise(key: "tu-wpullup", name: "Pull-ups · heavy",
                             prescription: "3 × 5–8 — add weight at 8",
                             rir: "1–3", liftID: "wpullup", isBodyweight: true),
                    // Heavy enough to actually be the strength day: strength
                    // cares far less about proximity to failure than
                    // hypertrophy does, so 2–3 RIR costs much less fatigue for
                    // a near-equal strength return.
                    //
                    // Deliberately still allows dumbbells, and deliberately
                    // keeps the `incline` liftID. Naming this barbell-only and
                    // flagging `isBarbell` would have asserted a change of
                    // implement on a lift whose whole logged history is
                    // per-dumbbell: the plate maths would read a 20 kg DB
                    // entry as a 20 kg bar total, and a first barbell session
                    // would land in the same history as a ~2× PR, spiking
                    // e1RM and resetting the stall baseline. Switching
                    // implement is the user's call to make knowingly — the
                    // prescription says so — not something a plan revision
                    // does silently underneath a year of numbers.
                    Exercise(key: "tu-incline", name: "Incline press",
                             prescription: "4 × 4–6 — barbell or machine is easier to control this heavy; DB is fine, but switching implement makes the logged numbers stop being comparable",
                             rir: "2–3", liftID: "incline"),
                    Exercise(key: "tu-row", name: "Barbell or DB row", prescription: "3 × 8–10",
                             rir: "1–2", liftID: "row", isBarbell: true),
                    Exercise(key: "tu-ohp", name: "Overhead press", prescription: "3 × 8–10",
                             rir: "1–2", liftID: "ohp", isBarbell: true),
                    // 3 down to 2, for the reason the review raises in 3.9 and
                    // then never spends: the pyramid already puts 20 dips and
                    // 30 push-ups into the week at cap 4, and more every time
                    // a round goes on. Chest and triceps are the two groups
                    // that volume actually lands on, so this is where it gets
                    // accounted for rather than counted twice.
                    Exercise(key: "tu-dips", name: "Dips", prescription: "2 × 8–12", rir: "1–2", liftID: "dips",
                             isBodyweight: true),
                    // Rear delts had almost no direct volume anywhere in the
                    // week — the stated goal is side and rear shoulder, so
                    // they need loading, not a warm-up band set. Placed here,
                    // between the two presses, as the antagonist break the
                    // heavy day was otherwise missing. Shares the `facepull`
                    // id with Friday's version on purpose — one combined
                    // history rather than two half-pictures.
                    Exercise(key: "tu-facepull", name: "Face pulls or reverse fly",
                             prescription: "3 × 12–15 — antagonist to the presses",
                             rir: "0–2", liftID: "facepull"),
                    // Shares the `lat` id with Friday on purpose.
                    //
                    // 3 up to 4, with Friday going 4 to 5: side delts were the
                    // other group the review's table called borderline-low
                    // against the stated goal, at 7 sets a week, and 3.1's
                    // instruction only covered the rear. Shoulders are the most
                    // visible part of what this programme is for, and lateral
                    // raises are the cheapest sets in the week to add — light
                    // load, 60–90s rest, almost no systemic cost. 9 a week now.
                    Exercise(key: "tu-lat", name: "Lateral raises", prescription: "4 × 12–15 — strict, no swing",
                             rir: "0–2", liftID: "lat"),
                ]),

            TrainingDay(
                dow: 3, label: "WE", colorHex: "E23B3B", title: "Lower · Strength", tag: "Rest 2–3 min / 60–90s",
                note: """
                    If Monday tennis left you wrecked, swap this with Tuesday. 2–3 min on the squat/deadlift \
                    and the RDL, 60–90s on everything after.
                    """,
                restSeconds: 150,
                items: [
                    Exercise(key: "we-warm", name: "Leg swings · hip circles · 90/90", prescription: "warm-up 5 min"),
                    Exercise(key: "we-squat", name: "Squat or trap bar deadlift", prescription: "4 × 5–8",
                             rir: "1–3", liftID: "squat", isBarbell: true),
                    // Trap bar deadlift is already heavy hip extension — a full
                    // RDL on top of it is two heavy hinges stacking on the same
                    // lower back in one session. Squat doesn't have that overlap,
                    // so it keeps the RDL at its full volume.
                    Exercise(key: "we-rdl", name: "Romanian deadlift",
                             prescription: "3 × 8–10 — only 2 sets (or swap for leg curl) if you did trap bar deadlift above",
                             rir: "1–2", liftID: "rdl", isBarbell: true),
                    // The RDL is pure hip extension. The short head of the biceps
                    // femoris only crosses the knee, so it barely works in any
                    // hinge — this is the movement that actually trains it.
                    Exercise(key: "we-legcurl", name: "Leg curl or Nordic", prescription: "3 × 8–12",
                             rir: "0–2", liftID: "legcurl"),
                    // Deep knee flexion under a rotational bias through the
                    // rep is the same combination occupational studies link
                    // to medial meniscus lesions — not a reason to drop the
                    // exercise, but the front knee's the thing worth
                    // watching as the set fatigues, specifically for a
                    // meniscus history.
                    Exercise(key: "we-bss", name: "Bulgarian split squat",
                             prescription: "3 × 10 / leg — front knee tracks over the foot, not inward, late in the set",
                             rir: "1–2", liftID: "bss"),
                    // The deep-flexion-under-a-rotational-bias combination the
                    // comment above warns about, confirmed the hard way — a
                    // real squat at real load (40 kg) was fine, this specific
                    // pattern wasn't. Kept in the schedule rather than
                    // replaced outright, since its history is real; `Knee`
                    // swaps it out for `we-legpress` when knee-care mode is
                    // on, and back once it's off — no key or liftID here
                    // ever changes, so nothing already logged is at risk.
                    Exercise(key: "we-legpress", name: "Leg press, limited depth",
                             prescription: "3 × 10 — depth is the progression variable here, not the plate; go a little deeper only after 24h with no next-day reaction",
                             rir: "1–2", liftID: "legpress"),
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
                dow: 5, label: "FR", colorHex: "E23B3B", title: "Upper · Volume", tag: "Rest ~2 min / 60–90s",
                note: """
                    Chase the pump here. Side and rear delts are what make the suit fit — and they only get \
                    trained if you actually load them. Give pull-ups and the flat press closer to 2 min, \
                    since they're still working near failure — everything after that is fine at 60–90s. \
                    Never go under 60s: that's where the hypertrophy effect actually starts to suffer.
                    """,
                restSeconds: 90,
                items: [
                    Exercise(key: "fr-warm", name: "Band pull-aparts", prescription: "warm-up 2×15"),
                    // Four sets to failure was expensive for a lift that,
                    // assisted or not, still runs into the same session's
                    // pressing and the next Upper day. The first two sets
                    // stay controlled; only the last one goes all the way
                    // down — hypertrophy's benefit from proximity to failure
                    // flattens out well before every set is one, and the
                    // fatigue cost doesn't.
                    Exercise(key: "fr-pullup", name: "Pull-ups",
                             prescription: "3 × max reps — first two @ 1–2 RIR, third set to failure",
                             liftID: "pullup", isBodyweight: true),
                    // Same reasoning as Tuesday's incline: deliberately keeps
                    // the `flat` liftID rather than a new one, and deliberately
                    // doesn't flag `isBarbell` — this lift's whole logged
                    // history is per-dumbbell, and asserting barbell-only now
                    // would have the plate maths read an old 20 kg DB entry as
                    // a 20 kg bar total, spiking e1RM off a implement switch
                    // rather than a real PR. The prescription says so instead,
                    // same as incline — switching implement is a choice to
                    // make knowingly, not one a rename makes for you.
                    Exercise(key: "fr-flat", name: "Barbell bench press",
                             prescription: "4 × 10–12 — switching from dumbbells means the numbers stop being directly comparable to old sessions",
                             rir: "1–2", liftID: "flat"),
                    Exercise(key: "fr-crow", name: "Cable or band row", prescription: "3 × 12", rir: "1–2", liftID: "crow"),
                    // See the note on Tuesday's lateral raises: 4 to 5 here,
                    // 3 to 4 there, side delts from 7 a week to 9.
                    Exercise(key: "fr-lat", name: "Lateral raises", prescription: "5 × 15", rir: "0–1", liftID: "lat"),
                    // Promoted from a warm-up to real loaded sets — rear delts had
                    // no working volume anywhere in the week.
                    Exercise(key: "fr-facepull", name: "Face pulls",
                             prescription: "3 × 15 — load it, pause at the face", rir: "0–2", liftID: "facepull"),
                    Exercise(key: "fr-arms", name: "Curls + triceps", prescription: "2 × 12 each",
                             rir: "0–1", liftID: "arms"),
                ]),

            TrainingDay(
                dow: 6, label: "SA", colorHex: "E23B3B", title: "Lower + Pyramid", tag: "Treat it as a session",
                note: """
                    The pyramid is a full session element, not an add-on — but it's conditioning and \
                    durability work, not the main driver of muscle growth. That's what the lifts above are \
                    for. Alternate the two ways of progressing it: one week add a round, the next keep the \
                    same rounds and wear the vest. 2–3 min rest on the squat, 60–90s after.
                    """,
                restSeconds: 180,
                items: [
                    Exercise(key: "sa-warm", name: "Dynamic warm-up + light hops",
                             prescription: "leg swings · ankle bounces · 2×5 easy pogo hops"),
                    // Explosive work belongs first, not after four heavy sets
                    // of squats — jumping under pre-fatigue is exactly when
                    // height drops and the set's own abort rule kicks in too
                    // early to have been worth starting.
                    Exercise(key: "sa-boxjump", name: "Box jumps",
                             prescription: "4 × 6 explosive, full rest — stop the set if height drops, land soft and even on both feet",
                             liftID: "boxjump"),
                    // Plyometric landing is squarely in the avoid list for a
                    // meniscus issue, and unlike the squat pattern this isn't
                    // something to test at load and confirm either way —
                    // kept in the schedule for its own history, same as
                    // `we-bss` above, and `Knee` swaps it for this whenever
                    // knee-care mode is on. Heavily loadable and a genuine
                    // volume replacement, not a consolation exercise — no
                    // knee flexion depth or rotation involved at all.
                    Exercise(key: "sa-hipthrust", name: "Hip thrust", prescription: "4 × 8–10",
                             rir: "1–2", liftID: "hipthrust", isBarbell: true),
                    Exercise(key: "sa-fsquat", name: "Front or goblet squat", prescription: "4 × 8",
                             rir: "1–2", liftID: "fsquat", isBarbell: true),
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

    /// Revised against an actual literature pass rather than fitness-content
    /// convention (full sourcing kept outside the codebase). Two of the
    /// original four held up as reasonable defaults with no change needed;
    /// one got a cue that measurably matters more than the stretch itself;
    /// one got replaced outright.
    ///
    /// - Squat hold: the *link* between ankle/hip range and squat depth is
    ///   real, but no trial tests holding the bottom position itself as an
    ///   intervention — kept as cheap position rehearsal, not corrective
    ///   therapy.
    /// - Couch stretch: a 2024 crossover trial found actively bracing a
    ///   posterior pelvic tilt during the stretch beats the stretch alone at
    ///   reducing hip-flexor tension — the cue matters more than the named
    ///   stretch, so it's now part of the prescription, not left implicit.
    /// - Shoulder dislocates → cross-body stretch: no trial validates the
    ///   ballistic band/broomstick drill, and general shoulder-instability
    ///   guidance flags the exact position it cycles through — abduction
    ///   combined with external rotation — as where an unstable shoulder is
    ///   most likely to give way. This program already drives that same
    ///   end-range on tennis day and under a bar on Tuesday/Friday, so a
    ///   ballistic version adds risk without adding anything the week isn't
    ///   already providing. A controlled, static cross-body stretch targets
    ///   the same posterior capsule without the swing.
    /// - Dead hang: kept, but on its actual evidence — grip endurance and
    ///   scapular control transfer to a program with three separate
    ///   pull-up/row days, not the "decompresses the shoulder" claim that
    ///   circulates with it, which no controlled trial has tested directly.
    /// A fifth item, added afterward: single-leg balance. Not really a
    /// "mobility" drill at all — a meniscus doesn't get more flexible from
    /// stretching it, so the four above don't do anything for one. What
    /// actually helps a partially-healed tear stay resolved is offloading
    /// (quad strength, already trained twice a week by the squat/RDL/split
    /// squat) and neuromuscular control — proprioceptive training after
    /// meniscus surgery has shown real gains in balance, strength and
    /// function scores versus conventional training alone, and it's the one
    /// piece nothing else in the week actually trains. Sits here rather than
    /// as an accessory lift because the useful dose is small and frequent —
    /// short daily balance work, not an occasional heavy session — which is
    /// exactly this checklist's format already.
    public static let mobility: [Mobility] = [
        .init(key: "mob-squat", name: "Deep squat hold", prescription: "2 × 1 min"),
        .init(key: "mob-couch", name: "Couch stretch",
              prescription: "1 min / side — tuck the pelvis under, don't just lean into it"),
        .init(key: "mob-shoulder", name: "Cross-body shoulder stretch",
              prescription: "2 × 30s / side — pull the arm across the chest, controlled, not ballistic"),
        .init(key: "mob-hang", name: "Dead hang", prescription: "2 × 30–45s"),
        .init(key: "mob-balance", name: "Single-leg balance",
              prescription: "2 × 30–45s / leg — progress to eyes closed or an uneven surface once it's easy"),
    ]

    /// The drill order as it stood while ticks were positions, back when
    /// there were four. **Frozen** in length and order — a new drill goes on
    /// the end of `mobility` (as the balance drill did) and is simply absent
    /// here, never inserted into this list, or every already-recorded tick
    /// would translate to the wrong drill. Renaming what a position points to
    /// (as happened at index 2, dislocates → cross-body stretch) is not an
    /// insertion and stays safe, the same way renaming a lift in `Schedule`
    /// doesn't corrupt its liftID-keyed history — the position, not the
    /// label, is what a legacy tick is anchored to.
    /// `testMobilityKeysAreStableAndUnique` fails if the two drift apart.
    private static let legacyMobilityOrder = [
        "mob-squat", "mob-couch", "mob-shoulder", "mob-hang",
    ]

    /// Translates an old positional tick, or nil if the position never existed.
    public static func mobilityKey(legacyIndex index: Int) -> String? {
        legacyMobilityOrder.indices.contains(index) ? legacyMobilityOrder[index] : nil
    }

    /// One extra drill layered on top of the fixed baseline, chosen by what
    /// the day itself demands rather than by the calendar:
    /// - Monday is tennis — a rotational sport — so it gets thoracic
    ///   *rotation*. An 8-week multimodal mobility program in competitive
    ///   tennis players measurably increased thoracic mobility and shoulder
    ///   internal/external rotation, with serve accuracy and velocity
    ///   improving alongside it rather than suffering for it — the strongest
    ///   single piece of evidence in this whole redesign, and it's specific
    ///   to this exact sport.
    /// - Tuesday and Friday both press overhead, which wants thoracic
    ///   *extension* instead — the range a press needs to come from the
    ///   spine rather than the lower back arching to fake it.
    /// - Wednesday and Saturday both squat — ankle dorsiflexion (the
    ///   knee-to-wall drill) is a validated clinical measure that tracks
    ///   with squat depth and mechanics. Dosed at 5 × 30s here specifically
    ///   because that's the protocol the RCT behind this actually used (twice
    ///   daily for 3 weeks, in that trial) — this gets you one of the two
    ///   bouts; a second later in the day compounds it, but one is a real
    ///   dose, not a token gesture.
    /// - Thursday (the plan's own lowest-priority day) and Sunday (which
    ///   already has its own 20-minute mobility block, `su-mob`) get nothing
    ///   extra here.
    ///
    /// The two thoracic drills also picked up a second set: the tennis trial
    /// behind Monday's case combined stretching with actual strengthening and
    /// myofascial work 4×/week for 8 weeks, which one drill on a checklist
    /// can't honestly claim to replicate — but it can at least carry the
    /// volume a single mobility drill would reasonably need, rather than the
    /// bare-minimum single set it shipped with before.
    ///
    /// Additive only, and never touches `mobility` or `legacyMobilityOrder` —
    /// a day with no case here just runs the same baseline drills everyone
    /// else runs.
    public static func mobilityFocus(dow: Int) -> Mobility? {
        switch dow {
        case 1:
            return .init(key: "mob-tspine-rotation", name: "Thoracic rotation (open book or quadruped)",
                         prescription: "2 × 8–10 / side, slow — follow the top hand with your eyes")
        case 2, 5:
            return .init(key: "mob-tspine-extension", name: "Thoracic extension (bench or roller)",
                         prescription: "2 × 8–10 reps, hold 2s at the top")
        case 3, 6:
            return .init(key: "mob-ankle", name: "Ankle dorsiflexion (knee-to-wall)",
                         prescription: "5 × 30s hold / side, knee driving over the toes")
        default:
            return nil
        }
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
