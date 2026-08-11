import XCTest
@testable import BrandNewBody

/// The maths, not the screens.
///
/// Everything under `Core` is a pure function of a `LogState` value — no
/// database, no clock, no views — which is what makes this suite possible at
/// all. `state.today` is injected, so every case here is a question about a
/// specific day rather than about the day the tests happen to run.
final class CoreTests: XCTestCase {

    // A Thursday, chosen so week boundaries land mid-fixture rather than
    // conveniently.
    let today = "2026-08-06"

    func makeState() -> LogState {
        var state = LogState(today: today)
        state.startDate = "2026-05-04"
        state.heightCm = 183
        state.birthYear = 1990
        return state
    }

    // MARK: - DateKit

    func testDayKeyRoundTrips() {
        let key = "2026-02-28"
        XCTAssertEqual(DateKit.date(key).map(DateKit.key), key)
    }

    func testDayKeyRejectsNonsense() {
        XCTAssertNil(DateKit.date("not-a-date"))
        XCTAssertNil(DateKit.date("2026-13-01"))
    }

    func testAddingCrossesMonthAndYearBoundaries() {
        XCTAssertEqual(DateKit.adding(1, to: "2026-02-28"), "2026-03-01")
        XCTAssertEqual(DateKit.adding(1, to: "2026-12-31"), "2027-01-01")
        XCTAssertEqual(DateKit.adding(-1, to: "2026-01-01"), "2025-12-31")
    }

    func testLeapDay() {
        XCTAssertEqual(DateKit.adding(1, to: "2028-02-28"), "2028-02-29")
    }

    /// Monday-start regardless of the device's locale — a US locale's
    /// Sunday-first week would silently change what a "green week" means.
    func testWeekStartIsMonday() {
        let sunday = DateKit.date("2026-08-09")!
        XCTAssertEqual(DateKit.key(DateKit.weekStart(sunday)), "2026-08-03")
        let monday = DateKit.date("2026-08-03")!
        XCTAssertEqual(DateKit.key(DateKit.weekStart(monday)), "2026-08-03")
    }

    func testDaysBetweenIsInclusiveOfNeither() {
        XCTAssertEqual(DateKit.days(from: "2026-08-01", to: "2026-08-06"), 5)
        XCTAssertEqual(DateKit.days(from: "2026-08-06", to: "2026-08-01"), -5)
    }

    func testRangeIsInclusiveOfBothEnds() {
        XCTAssertEqual(DateKit.range(from: "2026-08-01", to: "2026-08-03"),
                       ["2026-08-01", "2026-08-02", "2026-08-03"])
        XCTAssertEqual(DateKit.range(from: "2026-08-03", to: "2026-08-01"), [])
    }

    // MARK: - Trend

    /// A clean +1 kg over 20 days is +1.5 kg/month, and the fit should say so
    /// rather than approximately so.
    func testTrendFitsAKnownSlope() {
        var state = makeState()
        for day in stride(from: 20, through: 0, by: -1) {
            let date = DateKit.adding(-day, to: today)
            state.weights.append(WeightRecord(date: date, kg: 80 + Double(20 - day) * 0.05))
        }
        let fit = Trend.fit(state)
        XCTAssertNotNil(fit)
        XCTAssertEqual(fit!.rate, 1.5, accuracy: 0.0001)
        XCTAssertEqual(fit!.days, 20)
    }

    func testTrendNeedsEnoughPointsAndSpan() {
        var state = makeState()
        // Four points, but only three days apart — below the 10-day span.
        for day in 0..<4 {
            state.weights.append(WeightRecord(date: DateKit.adding(-day, to: today), kg: 80))
        }
        XCTAssertNil(Trend.fit(state))
    }

    /// The window is rolling, so ancient history must not drag the rate. Here
    /// a long flat stretch sits outside 28 days and a real climb sits inside;
    /// a whole-history fit would report near zero.
    func testTrendIgnoresDataOutsideTheWindow() {
        var state = makeState()
        for day in stride(from: 200, through: 40, by: -10) {
            state.weights.append(WeightRecord(date: DateKit.adding(-day, to: today), kg: 78))
        }
        for day in stride(from: 20, through: 0, by: -2) {
            state.weights.append(WeightRecord(date: DateKit.adding(-day, to: today),
                                             kg: 78 + Double(20 - day) * 0.05))
        }
        let fit = Trend.fit(state)
        XCTAssertNotNil(fit)
        XCTAssertEqual(fit!.rate, 1.5, accuracy: 0.0001)
    }

    /// Weigh-ins inside a run of illness, and the four days of refill after
    /// it, are water rather than progress and must not be fitted.
    func testTrendDropsWeighInsAroundTimeOff() {
        var state = makeState()
        for day in stride(from: 20, through: 0, by: -1) {
            state.weights.append(WeightRecord(date: DateKit.adding(-day, to: today), kg: 80))
        }
        // Three days ill, a week ago.
        for day in 7...9 {
            state.off[DateKit.adding(-day, to: today)] = .ill
        }
        let fit = Trend.fit(state)
        XCTAssertNotNil(fit)
        // 3 days off + the 4-day refill window after the last of them.
        XCTAssertEqual(fit!.skipped, 7)
    }

    func testVerdictBands() {
        XCTAssertEqual(Trend.verdict(stateWithRate(0.2)), .slow)
        XCTAssertEqual(Trend.verdict(stateWithRate(0.6)), .ok)
        XCTAssertEqual(Trend.verdict(stateWithRate(1.5)), .fast)
    }

    private func stateWithRate(_ perMonth: Double) -> LogState {
        var state = makeState()
        for day in stride(from: 20, through: 0, by: -1) {
            let gained = Double(20 - day) * (perMonth / 30)
            state.weights.append(WeightRecord(date: DateKit.adding(-day, to: today), kg: 80 + gained))
        }
        return state
    }

    /// Three lifts with a peak over a month back, never beaten by any of the
    /// three sessions since — `Lifts.stall`'s own condition, on every one of
    /// them.
    private func addStalledLifts(to state: inout LogState) {
        for id in ["row", "ohp", "incline"] {
            state.lifts[id] = [
                LiftRecord(date: DateKit.adding(-40, to: today), sets: [LiftSet(kg: 70, reps: 5)]),
                LiftRecord(date: DateKit.adding(-20, to: today), sets: [LiftSet(kg: 65, reps: 5)]),
                LiftRecord(date: DateKit.adding(-10, to: today), sets: [LiftSet(kg: 65, reps: 5)]),
                LiftRecord(date: DateKit.adding(-3, to: today), sets: [LiftSet(kg: 65, reps: 5)]),
            ]
        }
    }

    /// Neither series alone says whether the surplus needs adjusting or the
    /// programming does — a slow rate with stalled lifts points outside the
    /// programming entirely.
    func testTrendStagnationDetectsBothStalled() {
        var state = stateWithRate(0.2)   // .slow
        addStalledLifts(to: &state)
        XCTAssertEqual(Trend.stagnation(state), .bothStalled)
    }

    /// A normal gain rate with stalled lifts is the opposite read: food
    /// isn't the problem.
    func testTrendStagnationDetectsGainingWithoutProgress() {
        var state = stateWithRate(0.6)   // .ok
        addStalledLifts(to: &state)
        XCTAssertEqual(Trend.stagnation(state), .gainingWithoutProgress)
    }

    /// One lift having its turn for a plateau isn't a signal — it takes a
    /// real share of what's currently being trained.
    func testTrendStagnationNeedsEnoughTrainedLifts() {
        var state = stateWithRate(0.2)
        state.lifts["row"] = [LiftRecord(date: today, sets: [LiftSet(kg: 60, reps: 8)])]
        XCTAssertNil(Trend.stagnation(state))
    }

    // MARK: - Fuel

    func testFuelIsComputedFromBodyweightWhenItCan() {
        var state = makeState()
        state.weights = [WeightRecord(date: today, kg: 80)]
        // Mifflin-St Jeor: 10(80) + 6.25(183) - 5(36) + 5 = 1768.75
        let basis = Fuel.basis(state, dow: 2)
        XCTAssertTrue(basis.computed)
        XCTAssertEqual(basis.bmr!, 1768.75, accuracy: 0.001)
        XCTAssertEqual(basis.tdee!, 3007)              // ×1.7, rounded
        XCTAssertEqual(basis.base, 3207)               // + 200 surplus
    }

    func testFuelFallsBackToTheLegacyConstants() {
        var state = makeState()
        state.heightCm = nil
        state.weights = [WeightRecord(date: today, kg: 80)]
        let training = Fuel.targets(state, dow: 2)
        XCTAssertFalse(training.basis.computed)
        XCTAssertEqual(training.calories, 3200)
        XCTAssertEqual(training.protein, 170)
        let rest = Fuel.targets(state, dow: 4)
        XCTAssertEqual(rest.calories, 2900)
    }

    func testRestDaysAreThursdayAndSunday() {
        var state = makeState()
        state.weights = [WeightRecord(date: today, kg: 80)]
        XCTAssertTrue(Fuel.targets(state, dow: 4).isRestDay)
        XCTAssertTrue(Fuel.targets(state, dow: 0).isRestDay)
        XCTAssertFalse(Fuel.targets(state, dow: 6).isRestDay)
    }

    func testCalorieAdjustmentMovesTheTarget() {
        var state = makeState()
        state.weights = [WeightRecord(date: today, kg: 80)]
        state.calAdjust = -300
        XCTAssertEqual(Fuel.targets(state, dow: 2).calories, 3207 - 300)
    }

    // MARK: - Lifts

    func testParseScheme() {
        XCTAssertEqual(Lifts.parseScheme("4 × 8–10"), Lifts.Scheme(sets: 4, low: 8, high: 10))
        XCTAssertEqual(Lifts.parseScheme("3 × 12"), Lifts.Scheme(sets: 3, low: 12, high: 12))
        // "max reps" and "to 2 reps shy" have no numeric range, so no target.
        XCTAssertNil(Lifts.parseScheme("4 × max reps"))
        XCTAssertNil(Lifts.parseScheme("warm-up"))
    }

    func testBestSetPrefersLoadOverReps() {
        let record = LiftRecord(date: today, sets: [
            LiftSet(kg: 60, reps: 10), LiftSet(kg: 80, reps: 5),
        ])
        XCTAssertEqual(Lifts.bestSet(record)?.kg, 80)
    }

    func testVolumeReportsRepsForBodyweightWork() {
        let bodyweight = LiftRecord(date: today, sets: [LiftSet(reps: 12), LiftSet(reps: 10)])
        XCTAssertEqual(Lifts.volume(bodyweight), Lifts.Volume(reps: 22, kg: nil))
        let loaded = LiftRecord(date: today, sets: [LiftSet(kg: 60, reps: 10)])
        XCTAssertEqual(Lifts.volume(loaded), Lifts.Volume(reps: 10, kg: 600))
    }

    func testE1rmIsCappedAtFifteenReps() {
        XCTAssertNil(Lifts.e1rm(LiftSet(kg: 60, reps: 16)))
        XCTAssertNil(Lifts.e1rm(LiftSet(reps: 5)))          // bodyweight
        XCTAssertEqual(Lifts.e1rm(LiftSet(kg: 100, reps: 5))!, 116.666, accuracy: 0.01)
    }

    /// Every working set at the top of the range is the condition the
    /// programme names — not just the best set, which can hide one that fell
    /// apart.
    func testTargetAddsLoadOnlyWhenEverySetHitTheTop() {
        var state = makeState()
        state.lifts["row"] = [LiftRecord(date: DateKit.adding(-3, to: today), sets: [
            LiftSet(kg: 60, reps: 10), LiftSet(kg: 60, reps: 10), LiftSet(kg: 60, reps: 8),
        ])]
        let target = Lifts.nextTarget(state, id: "row", on: today, prescription: "4 × 8–10")
        XCTAssertEqual(target?.kg, 60)
        XCTAssertTrue(target!.text.contains("chase 9 reps"))

        state.lifts["row"] = [LiftRecord(date: DateKit.adding(-3, to: today), sets: [
            LiftSet(kg: 60, reps: 10), LiftSet(kg: 60, reps: 10), LiftSet(kg: 60, reps: 10),
        ])]
        let next = Lifts.nextTarget(state, id: "row", on: today, prescription: "4 × 8–10")
        XCTAssertEqual(next?.kg, 62.5)
    }

    func testLoadStepIsSmallerForLightLifts() {
        XCTAssertEqual(Lifts.loadStep(10), 1)
        XCTAssertEqual(Lifts.loadStep(60), 2.5)
    }

    /// A weekly cadence is not a layoff — anything keyed at or below 7 days
    /// would suppress progression across the whole programme, permanently.
    func testSevenDayGapIsNotALayoff() {
        var state = makeState()
        state.lifts["row"] = [LiftRecord(date: DateKit.adding(-7, to: today),
                                         sets: [LiftSet(kg: 60, reps: 10)])]
        let target = Lifts.nextTarget(state, id: "row", on: today, prescription: "4 × 8–10")
        XCTAssertEqual(target?.kg, 62.5)
        XCTAssertFalse(target!.text.contains("days since"))
    }

    func testShortLayoffRepeatsTheLoadAndLongOneBacksItOff() {
        var state = makeState()
        state.lifts["row"] = [LiftRecord(date: DateKit.adding(-14, to: today),
                                         sets: [LiftSet(kg: 60, reps: 10)])]
        XCTAssertEqual(Lifts.nextTarget(state, id: "row", on: today, prescription: "4 × 8–10")?.kg, 60)

        state.lifts["row"] = [LiftRecord(date: DateKit.adding(-40, to: today),
                                         sets: [LiftSet(kg: 60, reps: 10)])]
        let long = Lifts.nextTarget(state, id: "row", on: today, prescription: "4 × 8–10")
        XCTAssertEqual(long?.kg, 55)       // 10% off, snapped to the 2.5 kg step
    }

    func testPlateMaths() {
        // 40 kg a side: the greedy walk takes 25 first, then 15.
        XCTAssertEqual(Lifts.platesFor(total: 100, bar: 20), "1×25 + 1×15")
        XCTAssertEqual(Lifts.platesFor(total: 20, bar: 20), "bar only")
        // 61 kg is 20.5 per side, which these plates cannot express exactly.
        XCTAssertNil(Lifts.platesFor(total: 61, bar: 20))
        XCTAssertNil(Lifts.platesFor(total: 15, bar: 20))
    }

    /// Matching an old best is not progress: someone grinding the same 100×5
    /// every week has the peak on today's entry too, and taking the latest
    /// peak would mean nothing is ever flagged.
    func testStallUsesTheFirstTimeThePeakWasReached() {
        var history: [LiftRecord] = []
        for week in 0..<10 {
            history.append(LiftRecord(date: DateKit.adding(-7 * (9 - week), to: today),
                                      sets: [LiftSet(kg: 100, reps: 5)]))
        }
        let stall = Lifts.stall(history)
        XCTAssertNotNil(stall)
        XCTAssertEqual(stall?.weeks, 9)
    }

    func testNoStallWhileTheLiftIsStillMoving() {
        var history: [LiftRecord] = []
        for week in 0..<6 {
            history.append(LiftRecord(date: DateKit.adding(-7 * (5 - week), to: today),
                                      sets: [LiftSet(kg: 90 + Double(week) * 2.5, reps: 5)]))
        }
        XCTAssertNil(Lifts.stall(history))
    }

    // MARK: - Assisted lifts

    /// A pull-up or a dip starts at your own bodyweight, so the only way to
    /// make one easier is to take weight off — a band, or an assist machine.
    /// Logged as a negative, that used to walk through every one of these
    /// functions as if it were weight added.
    func testOnlyTheBodyweightLiftsAcceptAssistance() {
        let items = Plan.order.flatMap { Plan.day($0).items }
        let assisted = Set(items.filter(\.isBodyweight).compactMap(\.liftID))
        XCTAssertEqual(assisted, ["pullup", "wpullup", "dips"])
        // A barbell row cannot be loaded below an empty bar, and "BW −15 kg"
        // would be a lie about what was done.
        XCTAssertFalse(items.contains { $0.isBarbell && $0.isBodyweight })
    }

    /// "Weighted pull-ups" reads as a lie while still assisted, and plain
    /// "Pull-ups" says nothing once load's been added — the name has to
    /// track which side of bodyweight the lift is actually on.
    func testDisplayNameReflectsAssistedBodyweightAndWeightedState() {
        var state = makeState()
        XCTAssertEqual(Lifts.displayName(state, id: "wpullup", base: "Pull-ups"), "Pull-ups",
                       "no history yet — the base name stands")
        state.lifts["wpullup"] = [LiftRecord(date: today, sets: [LiftSet(kg: -15, reps: 6)])]
        XCTAssertEqual(Lifts.displayName(state, id: "wpullup", base: "Pull-ups"), "Assisted pull-ups")
        state.lifts["wpullup"] = [LiftRecord(date: today, sets: [LiftSet(kg: 0, reps: 6)])]
        XCTAssertEqual(Lifts.displayName(state, id: "wpullup", base: "Pull-ups"), "Pull-ups",
                       "plain bodyweight — neither prefix applies")
        state.lifts["wpullup"] = [LiftRecord(date: today, sets: [LiftSet(kg: 10, reps: 6)])]
        XCTAssertEqual(Lifts.displayName(state, id: "wpullup", base: "Pull-ups"), "Weighted pull-ups")
    }

    func testAssistancePrintsAsBodyweightMinusTheHelp() {
        XCTAssertEqual(Lifts.describe(LiftSet(kg: -15, reps: 8)), "BW −15 kg × 8")
        XCTAssertEqual(Lifts.describe(LiftSet(kg: -12.5, reps: 6)), "BW −12.5 kg × 6")
        XCTAssertEqual(Lifts.describe(LiftSet(kg: 12.5, reps: 8)), "12.5 kg × 8")
        // Zero is bodyweight, not a load of nothing.
        XCTAssertEqual(Lifts.describe(LiftSet(kg: 0, reps: 8)), "BW × 8")
        XCTAssertEqual(Lifts.describeLoad(-15), "15 kg assist")
        XCTAssertEqual(Lifts.describeLoad(0), "bodyweight")
        XCTAssertEqual(Lifts.describeLoad(nil), "bodyweight")
    }

    func testLessHelpIsTheBetterSet() {
        XCTAssertTrue(Lifts.beats(LiftSet(kg: -10, reps: 8), LiftSet(kg: -15, reps: 8)))
        XCTAssertFalse(Lifts.beats(LiftSet(kg: -15, reps: 8), LiftSet(kg: -10, reps: 8)))
        XCTAssertTrue(Lifts.beats(LiftSet(reps: 8), LiftSet(kg: -5, reps: 8)),
                      "plain bodyweight beats any amount of help")
    }

    /// -15 × 8 through Epley reads -19 kg, which then becomes the peak of the
    /// series, the baseline a stall is measured against, and a printed number.
    func testAssistedWorkHasNoE1rmAndNoKgVolume() {
        XCTAssertNil(Lifts.e1rm(LiftSet(kg: -15, reps: 8)))
        XCTAssertNil(Lifts.e1rm(LiftSet(kg: 0, reps: 8)))
        let record = LiftRecord(date: today, sets: [LiftSet(kg: -15, reps: 8), LiftSet(kg: -15, reps: 7)])
        XCTAssertEqual(Lifts.volume(record), Lifts.Volume(reps: 15, kg: nil),
                       "negative kg-volume would read as work done in reverse")
    }

    func testTheStepIsSizedByHowMuchLoadThereIsNotWhichSideOfZero() {
        XCTAssertEqual(Lifts.loadStep(-10), 1)
        XCTAssertEqual(Lifts.loadStep(-20), 2.5)
    }

    func testProgressionTakesHelpAwayAndTheLastKiloLandsOnBodyweight() {
        var state = makeState()
        state.lifts["dips"] = [LiftRecord(date: DateKit.adding(-3, to: today), sets: [
            LiftSet(kg: -15, reps: 12), LiftSet(kg: -15, reps: 12),
        ])]
        let target = Lifts.nextTarget(state, id: "dips", on: today, prescription: "3 × 8–12")
        XCTAssertEqual(target?.kg, -12.5, "adding load means less assistance, not more")
        XCTAssertTrue(target!.text.contains("12.5 kg assist"))

        state.lifts["dips"] = [LiftRecord(date: DateKit.adding(-3, to: today),
                                          sets: [LiftSet(kg: -1, reps: 12)])]
        let last = Lifts.nextTarget(state, id: "dips", on: today, prescription: "3 × 8–12")
        XCTAssertEqual(last?.kg, 0)
        XCTAssertTrue(last!.text.contains("bodyweight"), "a target of \"go 0 kg\" is not a sentence")
    }

    /// Backing off means less load, which on an assisted lift means more help
    /// from the band. The old floor sent an assisted lifter to +1 kg.
    func testLongLayoffOnAnAssistedLiftGivesMoreHelpNotMoreWeight() {
        var state = makeState()
        state.lifts["dips"] = [LiftRecord(date: DateKit.adding(-40, to: today),
                                          sets: [LiftSet(kg: -15, reps: 10)])]
        let target = Lifts.nextTarget(state, id: "dips", on: today, prescription: "3 × 8–12")
        XCTAssertEqual(target?.kg, -17.5)
        XCTAssertTrue(target!.text.contains("17.5 kg assist"))
    }

    // MARK: - Pyramid

    /// Total work grows with the square of the cap: 6 to 10 is not four more
    /// rounds, it is 2.6× the reps.
    func testPyramidTotals() {
        XCTAssertEqual(Pyramid.totals(cap: 4).total, 150)
        XCTAssertEqual(Pyramid.totals(cap: 5).total, 225)
        XCTAssertEqual(Pyramid.totals(cap: 6).total, 315)
        XCTAssertEqual(Pyramid.totals(cap: 10).total, 825)
        XCTAssertEqual(Pyramid.totals(cap: 4).parts.first?.reps, 10)   // pull-ups, 1× the triangular
    }

    func testVestStaysOffUntilTheCapEarnsIt() {
        var state = makeState()
        state.pyramidCap = 5
        XCTAssertFalse(Pyramid.isVestWeek(state))
        state.pyramidCap = 6
        // weeksIn is 13 from the fixture's start date, so odd → vest week.
        XCTAssertEqual(state.weeksIn % 2, 1)
        XCTAssertTrue(Pyramid.isVestWeek(state))
        state.vestPhase = 1
        XCTAssertFalse(Pyramid.isVestWeek(state))
    }

    /// Back-filling last Saturday must ask about *last* Saturday's week, not
    /// this one's, or the recorded pyramid carries the wrong vest parity.
    func testVestWeekIsJudgedByTheDayBeingLogged() {
        var state = makeState()
        state.pyramidCap = 6
        XCTAssertEqual(state.weeksIn, 13)
        XCTAssertTrue(Pyramid.isVestWeek(state))                                  // week 13, odd
        XCTAssertEqual(Pyramid.weekIndex(state, on: DateKit.adding(-7, to: today)), 12)
        XCTAssertFalse(Pyramid.isVestWeek(state, on: DateKit.adding(-7, to: today)))
        XCTAssertTrue(Pyramid.isVestWeek(state, on: today))
    }

    func testSuggestedVestScalesWithBodyweight() {
        var state = makeState()
        state.pyramidCap = 6
        state.weights = [WeightRecord(date: today, kg: 80)]
        // 5% + 3/7 of the 3-point spread = 6.28…% of 80 kg, to the nearest 0.5.
        XCTAssertEqual(Pyramid.suggestedVestKg(state), 5.0)
    }

    /// During today's own deload week, the pyramid logs a round lighter with
    /// no vest — without ever touching the persisted, climbing cap itself.
    func testPyramidDropsARoundAndTheVestDuringTodaysDeloadWeek() {
        var state = makeState()
        state.pyramidCap = 6
        state.deloadLog = [today]
        XCTAssertTrue(Pyramid.isDeloadedToday(state))
        XCTAssertEqual(Pyramid.effectiveCap(state), 5)
        XCTAssertFalse(Pyramid.itemName(state).contains("vest"))
        // The persisted cap the +/– buttons move is untouched.
        XCTAssertEqual(state.pyramidCap, 6)
    }

    /// A back-filled past Saturday happened under whatever was actually
    /// prescribed that week — hindsight from today's deload must not rewrite
    /// what gets logged for it.
    func testPyramidDeloadReductionNeverAppliesToABackFilledDay() {
        var state = makeState()
        state.pyramidCap = 6
        state.deloadLog = [today]
        let yesterday = DateKit.adding(-1, to: today)
        XCTAssertFalse(Pyramid.isDeloadedToday(state, on: yesterday))
        XCTAssertEqual(Pyramid.effectiveCap(state, on: yesterday), 6)
    }

    func testNoDeloadMeansThePyramidCapIsUntouched() {
        var state = makeState()
        state.pyramidCap = 6
        XCTAssertFalse(Pyramid.isDeloadedToday(state))
        XCTAssertEqual(Pyramid.effectiveCap(state), 6)
    }

    // MARK: - Consistency

    private func fillSessions(_ state: inout LogState, from: String, to: String, perWeek: Int) {
        var count = 0
        for date in DateKit.range(from: from, to: to) {
            guard let dow = DateKit.dow(key: date) else { continue }
            if dow == 1 { count = 0 }   // Monday starts the week
            guard count < perWeek else { continue }
            let need = Consistency.sessionNeed(dow: dow)
            let keys = Plan.day(dow).items.prefix(need).map(\.key)
            state.logs[date] = DayRecord(done: Set(keys))
            count += 1
        }
    }

    func testSessionNeedIsCappedByTheDaysOwnLength() {
        XCTAssertEqual(Consistency.sessionNeed(dow: 2), 3)   // seven items
        XCTAssertEqual(Consistency.sessionNeed(dow: 4), 2)   // cardio day has two
        XCTAssertEqual(Consistency.sessionNeed(dow: 0), 2)   // rest day has two
    }

    func testGreenStreakCountsFullWeeksOnly() {
        var state = makeState()
        fillSessions(&state, from: "2026-06-01", to: "2026-08-02", perWeek: 4)
        XCTAssertGreaterThanOrEqual(Consistency.greenStreak(state), 8)
    }

    /// A week the app itself prescribed a deload for is not a week you fell
    /// off — counting it against the streak is telling someone off for doing
    /// what they were just told to do.
    func testDeloadWeekKeepsTheStreak() {
        var state = makeState()
        fillSessions(&state, from: "2026-06-01", to: "2026-08-02", perWeek: 4)
        // Wipe one week's sessions and mark it as a deload instead.
        for date in DateKit.range(from: "2026-07-13", to: "2026-07-19") {
            state.logs[date] = nil
        }
        let withoutDeload = Consistency.greenStreak(state)
        state.deloadLog = ["2026-07-13"]
        XCTAssertGreaterThan(Consistency.greenStreak(state), withoutDeload)
    }

    /// A fortnight in Spain does not earn green weeks and does not cost the
    /// ones already banked — the streak bridges it.
    func testTimeOffBridgesRatherThanBreaksTheStreak() {
        var state = makeState()
        fillSessions(&state, from: "2026-06-01", to: "2026-08-02", perWeek: 4)
        for date in DateKit.range(from: "2026-07-13", to: "2026-07-19") {
            state.logs[date] = nil
            state.off[date] = .away
        }
        // The empty week is skipped entirely, so the streak spans it.
        XCTAssertGreaterThanOrEqual(Consistency.greenStreak(state), 8)
    }

    func testGreenNeedScalesDownWithDaysOff() {
        var state = makeState()
        XCTAssertEqual(Consistency.greenNeed(state, from: "2026-07-13", to: "2026-07-19"), 4)
        for date in DateKit.range(from: "2026-07-13", to: "2026-07-15") {
            state.off[date] = .ill
        }
        XCTAssertEqual(Consistency.greenNeed(state, from: "2026-07-13", to: "2026-07-19"), 2)
    }

    // MARK: - Time off

    func testCurrentRunIsNamedByItsEarliestDay() {
        var state = makeState()
        state.off[DateKit.adding(-2, to: today)] = .ill
        state.off[DateKit.adding(-1, to: today)] = .away
        state.off[today] = .away
        let run = TimeOff.current(state)
        XCTAssertEqual(run?.days, 3)
        XCTAssertEqual(run?.kind, .ill)
        XCTAssertEqual(run?.since, DateKit.adding(-2, to: today))
    }

    func testReturnRampOnlyAfterALongEnoughBreak() {
        var state = makeState()
        // Two days off, ended yesterday — below the four-day floor.
        state.off[DateKit.adding(-3, to: today)] = .ill
        state.off[DateKit.adding(-2, to: today)] = .ill
        XCTAssertNil(TimeOff.returnRamp(state))

        for day in 4...9 { state.off[DateKit.adding(-day, to: today)] = .ill }
        let ramp = TimeOff.returnRamp(state)
        XCTAssertNotNil(ramp)
        XCTAssertFalse(ramp!.long)       // eight days is short of the fortnight
    }

    func testNoRampWhileStillOff() {
        var state = makeState()
        for day in 0...9 { state.off[DateKit.adding(-day, to: today)] = .ill }
        XCTAssertNil(TimeOff.returnRamp(state))
        XCTAssertNotNil(TimeOff.current(state))
    }

    // MARK: - Deload

    private func withRecovery(_ values: [Int]) -> LogState {
        var state = makeState()
        // Clear of the calendar-based backstop (Deload.blockWeeks) so these
        // stay a test of the recovery signal specifically, not an incidental
        // trip over a second trigger `makeState`'s fixed start date happens
        // to sit past.
        state.startDate = DateKit.adding(-14, to: today)
        for (offset, value) in values.enumerated() {
            state.recovery[DateKit.adding(-(offset + 1), to: today)] = RecoveryRecord(recovery: value)
        }
        return state
    }

    func testDeloadFiresOnALowMean() {
        let state = withRecovery([40, 45, 38, 52, 44, 49, 41])
        let signal = Deload.signal(state)
        XCTAssertNotNil(signal)
        XCTAssertLessThan(signal!.mean, Deload.meanThreshold)
    }

    func testDeloadFiresOnRedDaysInsideAnOtherwiseNormalWeek() {
        let state = withRecovery([30, 28, 25, 80, 82, 85, 88])
        let signal = Deload.signal(state)
        XCTAssertNotNil(signal)
        XCTAssertEqual(signal?.reds, 3)
    }

    func testDeloadStaysQuietOnAGoodWeek() {
        XCTAssertNil(Deload.signal(withRecovery([70, 72, 68, 75, 80, 66, 71])))
    }

    func testDeloadNeedsEnoughReadings() {
        XCTAssertNil(Deload.signal(withRecovery([30, 28, 25])))
    }

    /// A fever tanks recovery for days, and that is the illness, not training
    /// fatigue. Prescribing a deload for it would also burn the 28-day
    /// cooldown on work that was never done.
    func testIllDaysAreNotCountedTowardsADeload() {
        var state = withRecovery([20, 22, 25, 80, 82, 85, 88])
        for day in 1...3 { state.off[DateKit.adding(-day, to: today)] = .ill }
        // Still off today, so nothing is judged at all.
        state.off[today] = .ill
        XCTAssertNil(Deload.signal(state))
    }

    func testDeloadRespectsTheCooldown() {
        var state = withRecovery([40, 45, 38, 52, 44, 49, 41])
        state.deloadLog = [DateKit.adding(-20, to: today)]
        XCTAssertNil(Deload.signal(state))
        state.deloadLog = [DateKit.adding(-40, to: today)]
        XCTAssertNotNil(Deload.signal(state))
    }

    func testSnoozeQuietensTheRollingSignal() {
        var state = withRecovery([40, 45, 38, 52, 44, 49, 41])
        state.deloadSnooze = DateKit.adding(-1, to: today)
        XCTAssertNil(Deload.signal(state))
        state.deloadSnooze = DateKit.adding(-6, to: today)
        XCTAssertNotNil(Deload.signal(state))
    }

    /// A device with a fast clock — or a record synced from one — must not pin
    /// the app into a deload week that counts up instead of down.
    func testFutureDatedDeloadIsIgnored() {
        var state = makeState()
        state.deloadLog = [DateKit.adding(30, to: today)]
        XCTAssertFalse(Deload.inDeloadWeek(state))
    }

    /// Anyone without WHOOP or manual recovery entries would otherwise never
    /// see a deload signal at all — the calendar backstop is what catches
    /// them. `makeState`'s own fixed start date sits 94 days back, well past
    /// the block window, and there is no recovery data logged at all here.
    func testDeloadFiresOnTheCalendarAloneWithNoRecoveryData() {
        let state = makeState()
        XCTAssertEqual(Deload.signal(state)?.kind, .calendar)
    }

    func testCalendarDeloadStaysQuietBeforeTheBlockWindowCloses() {
        var state = makeState()
        state.startDate = DateKit.adding(-14, to: today)
        XCTAssertNil(Deload.signal(state))
    }

    /// Two sessions running of a worse best set at the same prescription,
    /// across half or more of the currently-trained lifts, is fatigue
    /// outrunning recovery even when the recovery data itself hasn't caught
    /// up yet.
    func testDeloadFiresOnDecliningPerformanceAcrossMainLifts() {
        var state = makeState()
        state.startDate = DateKit.adding(-14, to: today)
        for id in ["row", "ohp", "incline"] {
            state.lifts[id] = [
                LiftRecord(date: DateKit.adding(-14, to: today), sets: [LiftSet(kg: 60, reps: 8)]),
                LiftRecord(date: DateKit.adding(-7, to: today), sets: [LiftSet(kg: 57.5, reps: 8)]),
                LiftRecord(date: DateKit.adding(-1, to: today), sets: [LiftSet(kg: 55, reps: 8)]),
            ]
        }
        XCTAssertEqual(Deload.signal(state)?.kind, .performance)
    }

    func testDeloadStaysQuietWhenPerformanceIsStillClimbing() {
        var state = makeState()
        state.startDate = DateKit.adding(-14, to: today)
        for id in ["row", "ohp", "incline"] {
            state.lifts[id] = [
                LiftRecord(date: DateKit.adding(-14, to: today), sets: [LiftSet(kg: 55, reps: 8)]),
                LiftRecord(date: DateKit.adding(-7, to: today), sets: [LiftSet(kg: 57.5, reps: 8)]),
                LiftRecord(date: DateKit.adding(-1, to: today), sets: [LiftSet(kg: 60, reps: 8)]),
            ]
        }
        XCTAssertNil(Deload.signal(state))
    }

    // MARK: - Build

    func testBuildTargetsFromHeight() {
        let state = makeState()          // 183 cm
        let targets = Build.targets(state)
        XCTAssertEqual(targets?.kgLow, 75)        // FFMI 20 at 11% body fat
        XCTAssertEqual(targets?.kgHigh, 83)       // FFMI 22
        XCTAssertEqual(targets?.waist, 82)        // 0.45 × height
        XCTAssertEqual(targets?.waistLimit, 92)   // 0.50 × height
    }

    func testWaistVetoesTheScale() {
        var state = makeState()
        state.weights = [WeightRecord(date: today, kg: 70)]     // well under the band
        state.waist = [WaistRecord(date: today, cm: 95)]        // over the limit
        let reading = Build.reading(state)
        XCTAssertEqual(reading?.tone, .fast)
        XCTAssertTrue(reading!.text.hasPrefix("Waist first"))
    }

    func testNoBuildTargetWithoutAHeight() {
        var state = makeState()
        state.heightCm = nil
        XCTAssertNil(Build.targets(state))
        XCTAssertNil(Build.reading(state))
    }

    // MARK: - Mind

    private func mindState(unlocked: Int, weeksAgo: Int) -> LogState {
        var state = makeState()
        state.mindStartDate = DateKit.adding(-7 * weeksAgo, to: today)
        state.mindUnlocked = unlocked
        return state
    }

    func testPracticesUnlockOneAtATime() {
        let state = mindState(unlocked: 1, weeksAgo: 0)
        XCTAssertEqual(Mind.activePractices(state).count, 1)
        XCTAssertEqual(Mind.nextPractice(state)?.key, "read")
    }

    /// Logging three minutes of a twenty-minute sit is not a session, and
    /// counting it would let the streak and the unlock gate both drift away
    /// from reality.
    func testMinutesPracticeNeedsToActuallyHitTheTarget() {
        var state = mindState(unlocked: 2, weeksAgo: 3)
        let read = MindPlan.practice("read")!
        state.mindLogs[today] = MindDayRecord(mins: ["read": 10])
        XCTAssertFalse(Mind.didPractice(state, read, on: today))
        state.mindLogs[today] = MindDayRecord(mins: ["read": 15])
        XCTAssertTrue(Mind.didPractice(state, read, on: today))
    }

    func testJournalCountsOnlyWhenItHasContent() {
        var state = mindState(unlocked: 1, weeksAgo: 1)
        let journal = MindPlan.practice("journal")!
        state.mindLogs[today] = MindDayRecord(journal: "   ")
        XCTAssertFalse(Mind.didPractice(state, journal, on: today))
        state.mindLogs[today] = MindDayRecord(journal: "Went well.")
        XCTAssertTrue(Mind.didPractice(state, journal, on: today))
    }

    func testMinuteTargetClimbsAfterThreeSessionsAtTarget() {
        var state = mindState(unlocked: 2, weeksAgo: 4)
        let read = MindPlan.practice("read")!
        for day in 1...2 {
            state.mindLogs[DateKit.adding(-day, to: today)] = MindDayRecord(mins: ["read": 15])
        }
        XCTAssertFalse(Mind.nextTarget(state, read)!.ready)
        state.mindLogs[DateKit.adding(-3, to: today)] = MindDayRecord(mins: ["read": 15])
        let next = Mind.nextTarget(state, read)!
        XCTAssertTrue(next.ready)
        XCTAssertEqual(next.next, 20)
    }

    func testMinuteTargetStopsAtTheCeiling() {
        var state = mindState(unlocked: 2, weeksAgo: 20)
        state.mindTargets["read"] = 45
        let next = Mind.nextTarget(state, MindPlan.practice("read")!)!
        XCTAssertTrue(next.capped)
        XCTAssertEqual(next.at, 45)
    }

    func testUnlockNeedsBothTheWeekAndTheAdherence() {
        var state = mindState(unlocked: 1, weeksAgo: 3)
        // Week 3 is before `read`'s week 2? No — it is past it, so the gate is
        // adherence alone.
        for day in 1...10 {
            state.mindLogs[DateKit.adding(-day, to: today)] = MindDayRecord(journal: "done")
        }
        XCTAssertEqual(Mind.unlockDue(state)?.ready, true)

        // Same history, but only a week in: the practice is not due yet.
        var early = state
        early.mindStartDate = DateKit.adding(-7, to: today)
        XCTAssertNil(Mind.unlockDue(early))
    }

    func testUnlockIsHeldByPoorAdherence() {
        var state = mindState(unlocked: 1, weeksAgo: 4)
        for day in 1...10 where day % 3 == 0 {
            state.mindLogs[DateKit.adding(-day, to: today)] = MindDayRecord(journal: "done")
        }
        XCTAssertEqual(Mind.unlockDue(state)?.ready, false)
    }

    /// A fortnight away would otherwise empty the whole window and hold the
    /// next unlock for a month after you got back — punishing the holiday
    /// twice.
    func testTimeOffLeavesTheAdherenceDenominatorAlone() {
        var state = mindState(unlocked: 1, weeksAgo: 4)
        for day in 1...7 {
            state.mindLogs[DateKit.adding(-day, to: today)] = MindDayRecord(journal: "done")
        }
        // The window is today plus the 13 days before it, and today is never
        // scored, so days 8–13 are the ones that fall inside it.
        for day in 8...13 { state.off[DateKit.adding(-day, to: today)] = .away }
        let adherence = Mind.adherence(state)
        XCTAssertNotNil(adherence)
        XCTAssertEqual(adherence!.rate, 1.0, accuracy: 0.0001)
        XCTAssertEqual(adherence!.skipped, 6)
        XCTAssertEqual(adherence!.days, 7)
    }

    /// Each lap through the drill list gets its own keys, so a second pass at
    /// "Follow-up questions" does not inherit the first pass's tally.
    func testCharismaLapsWithoutInheritingTheOldTally() {
        var state = mindState(unlocked: 7, weeksAgo: 14)
        state.charismaIx = 0
        for day in 1...4 {
            state.mindLogs[DateKit.adding(-day, to: today)] = MindDayRecord(done: ["chr0"])
        }
        XCTAssertEqual(Mind.charismaUses(state), 4)
        XCTAssertTrue(Mind.charismaReady(state))

        // One lap later the index is 14, the key is chr14, and the old chr0
        // entries count for nothing.
        state.charismaIx = MindPlan.charisma.count
        XCTAssertEqual(Mind.charismaLap(state), 2)
        XCTAssertEqual(Mind.charismaDrill(state).name, MindPlan.charisma[0].name)
        XCTAssertEqual(Mind.charismaUses(state), 0)
    }

    func testPromptIsStableForAGivenDay() {
        let state = mindState(unlocked: 1, weeksAgo: 1)
        XCTAssertEqual(Mind.prompt(state, on: today), Mind.prompt(state, on: today))
        XCTAssertTrue(MindPlan.prompts[0].contains(Mind.prompt(state, on: today)))
    }

    func testPromptTierHardensWithTime() {
        XCTAssertEqual(Mind.promptTier(mindState(unlocked: 1, weeksAgo: 1)), 0)
        XCTAssertEqual(Mind.promptTier(mindState(unlocked: 1, weeksAgo: 6)), 1)
        XCTAssertEqual(Mind.promptTier(mindState(unlocked: 1, weeksAgo: 14)), 2)
    }

    // MARK: - Plan integrity

    /// Two days share the `lat` and `calf` ids on purpose — one combined
    /// progression history rather than two half-pictures — but nothing else
    /// should collide, and every tick key must be unique across the week.
    func testPlanKeysAreUnique() {
        var keys = Set<String>()
        for dow in Plan.order {
            for item in Plan.day(dow).items {
                XCTAssertTrue(keys.insert(item.key).inserted, "duplicate item key \(item.key)")
            }
        }
    }

    func testEveryDayOfTheWeekIsPresent() {
        for dow in 0...6 {
            XCTAssertFalse(Plan.day(dow).items.isEmpty, "no items for day \(dow)")
        }
        XCTAssertEqual(Set(Plan.order), Set(0...6))
    }

    /// The guard on the mobility migration. Reordering `Plan.mobility` without
    /// updating the frozen legacy order would translate every already-recorded
    /// tick to the wrong drill, silently, and this is what catches it.
    func testMobilityKeysAreStableAndUnique() {
        XCTAssertEqual(Set(Plan.mobility.map(\.key)).count, Plan.mobility.count)
        XCTAssertEqual(Plan.mobility.prefix(4).map(\.key),
                       (0..<4).compactMap { Plan.mobilityKey(legacyIndex: $0) })
        XCTAssertNil(Plan.mobilityKey(legacyIndex: 4))
        XCTAssertNil(Plan.mobilityKey(legacyIndex: -1))
    }

    /// A backup exported while mobility ticks were still positions in the drill
    /// list has to keep importing — a restore is the one moment you cannot
    /// afford to throw.
    func testLegacyMobilityPositionsStillDecode() throws {
        let json = #"{"done":["su-mob"],"fuelHit":false,"mobility":[0,3],"note":"easy"}"#
        let record = try JSONDecoder().decode(DayRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.mobility, ["mob-squat", "mob-hang"])
        XCTAssertEqual(record.done, ["su-mob"])
        XCTAssertEqual(record.note, "easy")
    }

    func testCurrentMobilityKeysDecodeUnchanged() throws {
        let json = #"{"done":[],"fuelHit":true,"mobility":["mob-couch"],"note":""}"#
        let record = try JSONDecoder().decode(DayRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.mobility, ["mob-couch"])
        XCTAssertTrue(record.fuelHit)
    }

    /// A day record written by this version must read back as itself.
    func testDayRecordRoundTripsThroughItsOwnEncoder() throws {
        let original = DayRecord(done: ["tu-row"], fuelHit: true,
                                 mobility: ["mob-hang", "mob-squat"], note: "note")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(DayRecord.self, from: data), original)
    }

    func testEveryLoggableLiftHasAName() {
        for id in Plan.liftIDs {
            XCTAssertNotNil(Plan.liftNames[id], "no name for \(id)")
        }
    }

    /// Two lift ids sharing a display name are indistinguishable everywhere
    /// `Plan.liftNames` is what gets rendered — most sharply in the weekly
    /// "beaten this week" list, which carries no day context at all, so a
    /// collision there reads as the same lift listed twice. Renaming
    /// Tuesday's heavy pull-up to plain "Pull-ups" (so `displayName` could
    /// prefix it) collided it with Friday's, which is what this guards.
    func testNoTwoLiftsShareADisplayName() {
        let names = Plan.liftIDs.compactMap { Plan.liftNames[$0] }
        XCTAssertEqual(Set(names).count, names.count,
                       "duplicate lift display names: " +
                       Dictionary(grouping: names, by: { $0 })
                           .filter { $0.value.count > 1 }.keys.joined(separator: ", "))
    }

    /// The round-trip the backup file depends on.
    func testLogStateSurvivesAJSONRoundTrip() throws {
        var state = makeState()
        state.weights = [WeightRecord(date: today, kg: 80.4)]
        state.lifts["row"] = [LiftRecord(date: today, sets: [LiftSet(kg: 60, reps: 8)])]
        state.off[today] = .away
        state.mindLogs[today] = MindDayRecord(done: ["chr0"], mins: ["read": 20], journal: "hello")

        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(LogState.self, from: data)
        XCTAssertEqual(restored, state)
    }

    /// A backup written before some field existed — or hand-edited down to
    /// just the essentials — has to keep importing. `LogState`'s `Decodable`
    /// is hand-written for exactly this: every field falls back to its own
    /// ordinary default when the key is missing, instead of the whole
    /// restore failing over one field an old export never had a chance to
    /// write.
    func testLogStateDecodesMissingFieldsAsDefaults() throws {
        let json = #"{"today":"2026-01-01"}"#
        let state = try JSONDecoder().decode(LogState.self, from: Data(json.utf8))
        XCTAssertEqual(state.today, "2026-01-01")
        XCTAssertEqual(state.startDate, "2026-01-01")
        XCTAssertEqual(state.pyramidCap, 4)
        XCTAssertEqual(state.barKg, 20)
        XCTAssertEqual(state.mindUnlocked, 1)
        XCTAssertEqual(state.mindLadderCap, 1)
        XCTAssertTrue(state.weights.isEmpty)
        XCTAssertTrue(state.logs.isEmpty)
        XCTAssertTrue(state.lifts.isEmpty)
        XCTAssertEqual(state.schemaVersion, 1)
    }

    /// Even nothing at all — every key absent — has to decode rather than
    /// throw, the same way a corrupted-down-to-nothing file would.
    func testLogStateDecodesAnEmptyObjectWithoutThrowing() throws {
        XCTAssertNoThrow(try JSONDecoder().decode(LogState.self, from: Data("{}".utf8)))
    }
}
