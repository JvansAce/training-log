import Foundation

/// Calorie and macro targets.
///
/// The target used to be two constants, 2900 and 3200, tuned once for one
/// bodyweight. That is fine until the bodyweight changes: maintenance rises
/// with every kilo gained, so a frozen number quietly shrinks into a smaller
/// and smaller surplus until the scale stalls — and the app reads its own
/// arithmetic as a plateau.
///
/// So it is computed. Mifflin-St Jeor for resting expenditure (the estimate
/// that holds up best against measured RMR in non-obese adults), an activity
/// multiplier for the kind of day it is, and a fixed surplus on top.
/// Deliberately still a starting point rather than an answer: any TDEE formula
/// carries roughly ±10% error, which is larger than the surplus itself.
/// `calAdjust` is the correction, and it is driven by the measured 28-day
/// trend — the scale is the instrument, this is just the first guess.
public enum Fuel {

    public static let activityTraining = 1.7   // Mon tennis, Tue/Wed/Fri/Sat lifting
    public static let activityRest = 1.5       // Thu zone 2, Sun nothing
    public static let surplus = 200            // the "slight" in slight surplus
    public static let proteinPerKg = 2.0       // inside 1.6–2.2 g/kg for a lifter in a surplus
    public static let fatFraction = 0.27       // of total calories
    public static let legacyRest = 2900
    public static let legacyTraining = 3200
    public static let calorieStep = 200

    public struct Basis: Equatable, Sendable {
        public var isRestDay: Bool
        /// False when height or year of birth is missing, in which case the
        /// old flat constants are used and an install that predates those
        /// fields behaves exactly as it did.
        public var computed: Bool
        public var kg: Double?
        public var cm: Int?
        public var age: Int?
        public var bmr: Double?
        public var multiplier: Double?
        public var tdee: Int?
        public var base: Int
    }

    public struct Targets: Equatable, Sendable {
        public var calories: Int
        public var protein: Int
        public var fat: Int
        public var carbs: Int
        public var isRestDay: Bool
        public var basis: Basis
    }

    /// Mifflin-St Jeor, male.
    public static func bmr(kg: Double, cm: Int, age: Int) -> Double {
        10 * kg + 6.25 * Double(cm) - 5 * Double(age) + 5
    }

    public static func age(_ state: LogState) -> Int? {
        guard let birthYear = state.birthYear,
              let today = DateKit.date(state.today) else { return nil }
        return Calendar.current.component(.year, from: today) - birthYear
    }

    public static func basis(_ state: LogState, dow: Int) -> Basis {
        let rest = (dow == 0 || dow == 4)
        guard let kg = state.latestAverage, let cm = state.heightCm, let age = age(state) else {
            return Basis(isRestDay: rest, computed: false, kg: nil, cm: nil, age: nil,
                         bmr: nil, multiplier: nil, tdee: nil,
                         base: rest ? legacyRest : legacyTraining)
        }
        let resting = bmr(kg: kg, cm: cm, age: age)
        let multiplier = rest ? activityRest : activityTraining
        let tdee = Int((resting * multiplier).rounded())
        return Basis(isRestDay: rest, computed: true, kg: kg, cm: cm, age: age,
                     bmr: resting, multiplier: multiplier, tdee: tdee, base: tdee + surplus)
    }

    public static func targets(_ state: LogState, dow: Int) -> Targets {
        let b = basis(state, dow: dow)
        let calories = b.base + state.calAdjust
        // Protein tracks bodyweight where there is one; the old flat 170 g is
        // what a legacy install keeps.
        let protein = b.computed ? Int(((b.kg ?? 0) * proteinPerKg).rounded()) : 170
        let fat = b.computed
            ? Int((Double(calories) * fatFraction / 9).rounded())
            : (b.isRestDay ? 90 : 95)
        let carbs = Int((Double(calories - protein * 4 - fat * 9) / 4).rounded())
        return Targets(calories: calories, protein: protein, fat: fat, carbs: carbs,
                       isRestDay: b.isRestDay, basis: b)
    }
}
