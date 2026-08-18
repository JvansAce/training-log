import Foundation

/// BRAND NEW MIND — the other half.
///
/// Same shape as the body programme deliberately: a fixed list of things to do
/// today, a load on each that climbs, a Saturday session that is the hard one,
/// and verdicts that say the unwelcome thing.
///
/// The one structural difference is that it does not start with everything
/// switched on. Seven new daily habits beginning on the same Monday is how you
/// end up doing none of them by March, so practices unlock one at a time —
/// earliest by week, and only once the ones already running are actually
/// sticking. A first day you cannot finish teaches you to ignore the app.
public enum MindPlan {

    public enum PracticeKind: String, Sendable {
        /// Free text — the journal.
        case text
        /// A target in minutes that climbs.
        case minutes
        /// Did it or didn't.
        case tick
        /// The charisma drill, logged under whichever drill was current.
        case drill
    }

    public struct Practice: Identifiable, Hashable, Sendable {
        public let key: String
        public var id: String { key }
        public let name: String
        public let group: String
        /// Earliest week (0-based) this can unlock.
        public let week: Int
        public let kind: PracticeKind
        public let why: String
        public let start: Int?
        public let step: Int?
        public let max: Int?
        /// Offers an in-app countdown.
        public let hasTimer: Bool

        init(key: String, name: String, group: String, week: Int, kind: PracticeKind,
             why: String, start: Int? = nil, step: Int? = nil, max: Int? = nil,
             hasTimer: Bool = false) {
            self.key = key; self.name = name; self.group = group; self.week = week
            self.kind = kind; self.why = why; self.start = start; self.step = step
            self.max = max; self.hasTimer = hasTimer
        }
    }

    public static let practices: [Practice] = [
        Practice(key: "journal", name: "Journal", group: "Processing", week: 0, kind: .text,
                 why: "Knowing what you think, rather than finding out mid-argument."),
        Practice(key: "read", name: "Read", group: "Input", week: 2, kind: .minutes,
                 why: "Something to say. Depth, references, curiosity.",
                 start: 15, step: 5, max: 45),
        Practice(key: "medit", name: "Meditate", group: "Stillness", week: 4, kind: .minutes,
                 why: "Not being reactive. Presence reads as confidence.",
                 start: 5, step: 2, max: 20, hasTimer: true),
        Practice(key: "word", name: "Kept my word", group: "Character", week: 6, kind: .tick,
                 why: "The specific thing you said you would do. Not a virtue score."),
        Practice(key: "social", name: "Social rep", group: "Social", week: 8, kind: .tick,
                 why: "It is a skill, it is trainable, and it decays without reps."),
        Practice(key: "make", name: "Make", group: "Output", week: 10, kind: .minutes,
                 why: "Reading without making is just accumulating.",
                 start: 15, step: 5, max: 60),
        Practice(key: "charisma", name: "Charisma drill", group: "Presence", week: 12, kind: .drill,
                 why: "One named technique at a time, until it stops being a technique."),
    ]

    public static func practice(_ key: String) -> Practice? {
        practices.first { $0.key == key }
    }

    /// Characters per journal entry. Capped because the record is synced as a
    /// unit — one pasted essay per day would bloat every device's copy.
    public static let journalMax = 4000

    // MARK: - Charisma

    /// Charisma is trainable, and this is not a self-help claim: Antonakis,
    /// Fenley and Liechti ran randomised experiments teaching twelve specific
    /// "charismatic leadership tactics" and had observers rate the results —
    /// trained speakers' ratings went up around 60% (HBR, "Learning Charisma",
    /// 2012; AMLE, "Can Charisma Be Taught?", 2011). Separately, Huang et al.
    /// (JPSP 2017) found across three studies of live conversations that
    /// asking questions — follow-ups especially — predicts being liked better
    /// than anything else measured. In their speed-dating arm the top third of
    /// question-askers got a second date 39% of the time against 22% for the
    /// bottom third.
    ///
    /// The published tactics are mostly written for someone giving a speech,
    /// which is not the problem here, so these start with the one-to-one ones
    /// and work outward to the platform ones. Ordered by payoff-per-effort.
    ///
    /// One drill at a time, deliberately. Trying to remember twelve techniques
    /// mid-conversation is how you end up present for none of them.
    public struct Drill: Identifiable, Hashable, Sendable {
        public var id: String { name }
        public let name: String
        public let how: String
        public let source: String
    }

    public static let charisma: [Drill] = [
        .init(name: "Follow-up questions",
              how: "Ask a question, listen, then ask a second one that could only follow that answer.",
              source: "The strongest single predictor of being liked in the Harvard conversation studies — and most people have no idea it works."),
        .init(name: "Presence",
              how: "When your attention drifts mid-conversation, notice it and come back. Phone out of sight, not face-down on the table.",
              source: "Cabane puts presence first of the three: people can tell, and they read the drift as disinterest in them."),
        .init(name: "Warmth before competence",
              how: "Open with interest in them rather than with what you do. Let the CV come out later, or not at all.",
              source: "Warmth is judged before competence and colours everything after it."),
        .init(name: "Stories, not summaries",
              how: "Answer \"how was your weekend\" with one small scene — a place, a person, something that happened. Not an adjective.",
              source: "Stories and anecdotes are one of the nine verbal tactics, and the easiest to use off a stage."),
        .init(name: "Land the ending",
              how: "Finish sentences instead of trailing off. Say the last word at full volume and stop.",
              source: "Trailing off reads as asking permission. It is the fastest thing to fix on this list."),
        .init(name: "The pause",
              how: "When you finish a thought, say nothing. Do not fill it. Let them come in.",
              source: "Filling every silence signals you expect to be interrupted. Holding one signals the opposite."),
        .init(name: "Let your face react",
              how: "React visibly to what you are hearing. A face doing nothing reads as bored or hostile, never as neutral.",
              source: "One of the three non-verbal tactics in the study."),
        .init(name: "Animated voice",
              how: "Vary pace, pitch and volume across a single point. Slow down for the part that matters.",
              source: "Non-verbal tactic two. A flat delivery undoes good content."),
        .init(name: "Gestures",
              how: "Hands out of pockets. Gesture once, deliberately, on the point you want remembered.",
              source: "Non-verbal tactic three."),
        .init(name: "Name the room",
              how: "Say the thing everyone is thinking and nobody has said yet.",
              source: "\"Reflecting the group's sentiment\" — the tactic that makes a group feel understood rather than addressed."),
        .init(name: "Metaphor",
              how: "Explain one thing today by comparing it to something physical everyone already knows.",
              source: "First on the list of nine verbal tactics, and the one that survives being repeated afterwards."),
        .init(name: "Contrast",
              how: "Say it as \"not this — but this.\" One sentence, both halves.",
              source: "Contrast gives a point an edge that a plain statement does not have."),
        .init(name: "Three-part list",
              how: "Make the point in threes. Three reasons, three examples, three words.",
              source: "Threes are remembered and repeated. Twos sound incomplete, fours sound like a list."),
        .init(name: "Conviction",
              how: "Say what you actually think is right, in the unhedged version, once today.",
              source: "\"Expressions of moral conviction\" — the tactic people avoid, and the one that separates being liked from being followed."),
    ]

    /// Uses of a drill before the next one arrives.
    public static let charismaUsesNeeded = 4

    // MARK: - Social reps

    /// Rotates so it never becomes one rote move, and escalates across the
    /// week towards Saturday.
    public static let socialReps: [Int: String] = [
        1: "Reach out to someone you have not spoken to in a month",
        2: "Ask someone a question you do not know the answer to — then a follow-up",
        3: "Give a specific compliment. The choice, not the appearance",
        4: "Say the thing you would normally soften",
        5: "Talk to someone you do not know",
        6: "The ladder — see below",
        0: "One long conversation with the phone off the table",
    ]

    public static func socialRep(dow: Int) -> String {
        socialReps[dow] ?? socialReps[1]!
    }

    // MARK: - Journal prompts

    /// Prompts get harder as the habit gets older rather than the entry
    /// getting longer. Tier is by weeks in, so week one is not asking you to
    /// excavate anything.
    public static let prompts: [[String]] = [
        [   // tier 1 — weeks 0–3, build the habit
            "What went well today?",
            "What would you do differently?",
            "Who did you enjoy talking to, and why?",
            "What took more energy than it should have?",
            "What are you looking forward to?",
            "What did you learn today, however small?",
            "Where did the day go?",
        ],
        [   // tier 2 — weeks 4–11, start observing yourself
            "What did you avoid today, and what was the actual fear?",
            "Where were you not honest?",
            "What did you want to say and did not?",
            "What did you do purely because it was expected?",
            "When were you most yourself today?",
            "What are you pretending not to know?",
            "What would you do this week if you were not worried about looking stupid?",
        ],
        [   // tier 3 — week 12+, the ones with teeth
            "What do you do that you would criticise in someone else?",
            "Who are you resentful of, and what does that say about what you want?",
            "If nothing changed for a year, what would bother you most?",
            "What are you getting out of the problem you say you want to fix?",
            "Who have you been unfair to lately?",
            "What do you want that you have never said out loud?",
            "What would the version of you from five years ago think of this week?",
        ],
    ]

    // MARK: - The ladder

    public static let ladder: [String] = [
        "Eye contact and a smile at a stranger",
        "Ask a stranger a real question",
        "Give a specific, genuine compliment",
        "Hold a five-minute conversation with someone new",
        "Say the unpopular thing in a group",
        "Make a direct ask — a favour, a date, a raise",
        "Have the conversation you have been putting off",
    ]

    // MARK: - Add-ins

    /// The catalogue that did not make the core seven. Unlocks once the whole
    /// core is running and has been for a while — by then the core is boring,
    /// which is exactly when a new one is welcome rather than a burden.
    public static let addIns: [String] = [
        "Notes on what you read — reading without notes is a leaky bucket",
        "Memorise something: a poem, a toast, three good jokes",
        "Argue the other side of something you believe",
        "A walk with no headphones",
        "Ten minutes of boredom, no input at all",
        "Host something — be the one who makes the plan",
        "Learn a language, daily reps",
        "An instrument, or anything with a skill floor",
        "Cook something you have never cooked",
        "Read outside your field entirely",
        "Remember and use three names today",
        "Do something for someone with no return",
    ]

    public static let addInWeek = 18
}
