import XCTest
import SwiftData
@testable import BrandNewBody

/// The store layer, not the maths — `CoreTests` covers pure functions over a
/// `LogState` value; this covers what `AppStore` actually does to SwiftData,
/// with a fresh in-memory container per test so nothing here touches a real
/// device's data. Every case exists because it's exactly the kind of thing
/// that fails silently: a replace that turns into a merge, a seed that
/// survives a real weigh-in, an empty day record nobody ever asked for.
@MainActor
final class AppStoreTests: XCTestCase {

    private func makeStore() -> (store: AppStore, context: ModelContext) {
        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        return (AppStore(context: context), context)
    }

    // MARK: - setSets

    /// `setSets` replaces whatever was stored for a (lift, date) pair rather
    /// than merging into it — the exact semantic that made a momentarily
    /// blank reps field capable of deleting an already-logged set (see
    /// LiftRow.flush). This pins the replace behaviour itself, at the store.
    func testSetSetsReplacesRatherThanMerges() throws {
        let (store, context) = makeStore()
        let date = store.state.today

        store.setSets([LiftSet(kg: 60, reps: 8), LiftSet(kg: 60, reps: 8)], liftID: "row", on: date)
        XCTAssertEqual(store.state.liftHistory("row").first?.sets.count, 2)

        store.setSets([LiftSet(kg: 65, reps: 5)], liftID: "row", on: date)
        let sets = store.state.liftHistory("row").first?.sets
        XCTAssertEqual(sets?.count, 1)
        XCTAssertEqual(sets?.first?.kg, 65)

        // One row per (liftID, date) in the actual store — not the old one
        // left behind alongside a new one.
        let rows = try context.fetch(FetchDescriptor<LiftEntry>())
        XCTAssertEqual(rows.filter { $0.liftID == "row" && $0.date == date }.count, 1)
    }

    /// Every set with zero or negative reps is "an empty input box, not a
    /// set that happened" — the whole entry should disappear, not persist
    /// as a record with nothing in it.
    func testSetSetsWithNoValidRepsDeletesTheEntry() throws {
        let (store, context) = makeStore()
        let date = store.state.today

        store.setSets([LiftSet(kg: 60, reps: 8)], liftID: "row", on: date)
        XCTAssertFalse(store.state.liftHistory("row").isEmpty)

        store.setSets([LiftSet(kg: 60, reps: 0)], liftID: "row", on: date)
        XCTAssertTrue(store.state.liftHistory("row").isEmpty)

        let rows = try context.fetch(FetchDescriptor<LiftEntry>())
        XCTAssertTrue(rows.filter { $0.liftID == "row" && $0.date == date }.isEmpty)
    }

    // MARK: - Weigh-ins

    /// A fresh install seeds one placeholder weigh-in so the chart and the
    /// calorie target have a bodyweight to read. A real weigh-in for *any*
    /// date — not just today — has to evict it, or a first real log made a
    /// few days into using the app leaves a fabricated 79 kg sitting in the
    /// log forever, dragging the trend with it.
    func testLogWeightEvictsTheSeedRegardlessOfDate() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.state.weights.count, 1)
        XCTAssertTrue(store.state.weights[0].seed)

        let pastDate = DateKit.adding(-3, to: store.state.today)
        store.logWeight(kg: 82, on: pastDate)

        XCTAssertEqual(store.state.weights.count, 1)
        XCTAssertEqual(store.state.weights[0].date, pastDate)
        XCTAssertEqual(store.state.weights[0].kg, 82)
        XCTAssertFalse(store.state.weights[0].seed)
    }

    // MARK: - Session ticks

    /// Empty days are deleted rather than kept as blanks, so merely opening
    /// a day you didn't touch never writes a row that syncs to every other
    /// device. Ticking an item and then unticking it back to nothing has to
    /// land in that same empty state — not leave a technically-empty record
    /// behind because the delete path only runs on the "never touched" case.
    func testTogglingAnItemOffAgainDeletesTheEmptyDayRecord() throws {
        let (store, context) = makeStore()
        let date = store.state.today

        store.toggleItem("tu-row", on: date)
        XCTAssertTrue(store.state.day(date).done.contains("tu-row"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<DayEntry>())
            .filter { $0.date == date }.count, 1)

        store.toggleItem("tu-row", on: date)
        XCTAssertTrue(store.state.day(date).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<DayEntry>())
            .filter { $0.date == date }.isEmpty)
    }

    // MARK: - Backup

    /// The round-trip Setup's "Export file" / "Import file" actually
    /// perform, through the real store rather than just through
    /// `LogState`'s own `Codable` — settings, a lift, a session tick and a
    /// weigh-in all have to survive going out through `exportData()` and
    /// back in through `importData()` on a completely fresh store.
    func testExportThenImportRestoresTheLoggedState() throws {
        let (store, _) = makeStore()
        let date = store.state.today
        store.logWeight(kg: 81.4, on: date)
        store.setSets([LiftSet(kg: 60, reps: 8)], liftID: "row", on: date)
        store.toggleItem("tu-row", on: date)
        store.setHeight(183)

        let data = try store.exportData()

        let (fresh, _) = makeStore()
        try fresh.importData(data)

        XCTAssertEqual(fresh.state.heightCm, 183)
        XCTAssertEqual(fresh.state.liftHistory("row").first?.sets.first?.reps, 8)
        XCTAssertTrue(fresh.state.day(date).done.contains("tu-row"))
        XCTAssertEqual(fresh.state.weights.first { !$0.seed }?.kg, 81.4)
    }

    // MARK: - Settings dedup

    /// Two devices racing on first launch can each create an `AppSettings`
    /// row before either has synced. `fetchSettings()` already collapses
    /// that down to the oldest on the very next read — this pins the
    /// behaviour so a future change to that method can't quietly drop it.
    func testDuplicateSettingsRowsCollapseToTheOldestOnNextRead() throws {
        let (store, context) = makeStore()
        let extra = AppSettings(startDate: "2020-01-01", createdAt: Date().addingTimeInterval(3600))
        context.insert(extra)
        try context.save()

        store.setBarKg(22.5)

        let rows = try context.fetch(FetchDescriptor<AppSettings>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertNotEqual(rows.first?.startDate, "2020-01-01")
    }
}
