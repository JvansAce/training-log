import Foundation

/// What "ideal weight" actually means here.
///
/// A weight on its own means nothing — 78 kg is lean on one frame and soft on
/// another — so the target is defined by two ratios against height, and the
/// scale number falls out of them.
///
/// FFMI is lean mass in kg over height in metres squared. Roughly: 20 is
/// trained and athletic, 22 is several serious years, 25 is about the natural
/// ceiling (Kouri 1995, comparing steroid-free and steroid-using lifters — a
/// heuristic, not a law). The build this programme is after is lean and
/// defined rather than big, so the band tops out at 22. Chasing past it means
/// carrying mass that costs you on a tennis court.
///
/// The waist target does the harder work. Waist-to-height ratio is the
/// body-composition measure with the best evidence behind it: under 0.50 is
/// the health threshold, and 0.45 is where the lean athletic look sits.
/// Deliberately no body-fat percentage anywhere — estimating one from a tape
/// measure adds a number that looks precise, reads several points off whatever
/// you'd guess in a mirror, and changes no decision that the waist ratio
/// hasn't already made.
public enum Build {

    public static let ffmiLow = 20.0        // athletic and visibly trained
    public static let ffmiHigh = 22.0       // the top of what this programme aims at
    public static let bodyFat = 0.11        // where a slow surplus keeps you
    public static let waistToHeight = 0.45  // waist ÷ height for the look
    public static let waistLimitRatio = 0.50

    public static let minHeight = 120
    public static let maxHeight = 230
    public static let minAge = 14
    public static let maxAge = 90

    public struct Targets: Equatable, Sendable {
        public var kgLow: Int
        public var kgHigh: Int
        public var waist: Int
        public var waistLimit: Int
    }

    /// Rounded once, here, rather than at each point of display. Keeping the
    /// raw values and rounding in the view meant the tile could read "73–80"
    /// while the sentence under it said "2.8 kg to the bottom of the band" off
    /// 70 kg — arithmetic that doesn't add up in front of the reader.
    public static func targets(_ state: LogState) -> Targets? {
        guard let cm = state.heightCm, cm > 0 else { return nil }
        let m = Double(cm) / 100
        func weight(atFFMI ffmi: Double) -> Int {
            Int((ffmi * m * m / (1 - bodyFat)).rounded())
        }
        return Targets(kgLow: weight(atFFMI: ffmiLow),
                       kgHigh: weight(atFFMI: ffmiHigh),
                       waist: Int((waistToHeight * Double(cm)).rounded()),
                       waistLimit: Int((waistLimitRatio * Double(cm)).rounded()))
    }

    public struct Reading: Equatable, Sendable {
        public var tone: Trend.Verdict
        public var text: String
    }

    /// The one sentence worth reading: bulk, hold, or deal with the waist.
    ///
    /// Ordered so the waist can veto — mass added on top of a waist already
    /// past the limit is not the build, whatever the scale says.
    public static func reading(_ state: LogState) -> Reading? {
        guard let t = targets(state) else { return nil }
        let kg = state.latestAverage
        let cm = state.latestWaist?.cm

        if let cm, cm > Double(t.waistLimit) {
            return Reading(tone: .fast, text: """
                Waist first. At \(Lifts.fmt(cm)) cm you're past the \(t.waistLimit) cm line for your \
                height — more weight on top of that reads as bigger, not leaner. Hold calories steady \
                until it's back under \(t.waist) cm.
                """)
        }

        if let kg, kg < Double(t.kgLow) {
            var text = "\(String(format: "%.1f", Double(t.kgLow) - kg)) kg to the bottom of the band. Keep the surplus running"
            if let cm {
                text += " — you have \(String(format: "%.1f", max(0, Double(t.waistLimit) - cm))) cm of waist room before it becomes the problem"
            }
            return Reading(tone: .slow, text: text + "." + bandETA(state, t))
        }

        if let kg, kg > Double(t.kgHigh) {
            let tail = (cm != nil && cm! <= Double(t.waist))
                ? "and it is, so this is just more of the build."
                : "but it is the waist that decides, and yours is the number to watch now."
            return Reading(tone: .unknown, text:
                "Above the band at \(String(format: "%.1f", kg)) kg. That's fine if the waist is holding — \(tail)")
        }

        if let kg, let cm, cm <= Double(t.waist) {
            return Reading(tone: .ok, text: """
                This is it. \(String(format: "%.1f", kg)) kg at a \(Lifts.fmt(cm)) cm waist is the build. \
                Stop chasing the scale and hold it — the work now is keeping it while the lifts keep climbing.
                """)
        }

        if let cm {
            return Reading(tone: .ok, text: """
                Weight is in the band. What's left is \(String(format: "%.1f", cm - Double(t.waist))) cm of waist — \
                drop the surplus and sit at maintenance while the lifts keep climbing. That is the brake, not a diet.
                """)
        }
        return Reading(tone: .ok, text: """
            Weight is in the band. Log a waist measurement and this can tell you whether the mass is \
            landing in the right place.
            """)
    }

    /// How long the band actually is away, at the rate being gained right now.
    /// The app already has the gap and the trend, so it can say months instead
    /// of gesturing at "this takes a while".
    static func bandETA(_ state: LogState, _ t: Targets) -> String {
        guard let kg = state.latestAverage, let fit = Trend.fit(state), kg < Double(t.kgLow) else { return "" }
        guard fit.rate > 0.05 else {
            return " At the moment the scale is flat, so the band is not getting any closer."
        }
        let months = (Double(t.kgLow) - kg) / fit.rate
        let phrase = months < 1.5 ? "a month" : "\(Int(months.rounded())) months"
        return " At your current \(String(format: "%.2f", fit.rate)) kg/month that's about \(phrase) away."
    }
}
