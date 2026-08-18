import SwiftUI
import SwiftData

@main
@MainActor
struct BrandNewBodyApp: App {
    private let container: ModelContainer
    @State private var store: AppStore
    @State private var restTimer = RestTimer()
    @State private var whoop = WhoopClient()
    @State private var hevy = HevyClient()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let result = Persistence.makeContainer()
        container = result.container
        _store = State(initialValue: AppStore(context: result.container.mainContext,
                                             cloudStatus: result.status))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(restTimer)
                .environment(whoop)
                .environment(hevy)
                .preferredColorScheme(.dark)
                .tint(Theme.red)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // An installed app is resumed, not relaunched: it can sit in the
            // switcher across midnight for days, and every write path reads
            // `state.today`. Without this, everything typed after midnight
            // silently lands on yesterday. It is also the moment to pick up
            // anything CloudKit delivered while the app was asleep.
            guard phase == .active else { return }
            store.refresh()
            Task {
                await whoop.fetchToday(dayKey: store.state.today)
                if let reading = whoop.today?.recovery {
                    store.applyWhoopReading(reading, on: store.state.today)
                }
            }
            Task {
                guard hevy.status == .connected else { return }
                let workouts = await hevy.fetchNewWorkouts(since: store.state.hevyLastImportedWorkoutID)
                if !workouts.isEmpty {
                    store.applyHevyImport(HevyImport.apply(workouts, mapping: store.state.hevyMapping))
                }
                let measurements = await hevy.fetchNewBodyMeasurements(since: store.state.hevyLastImportedMeasurementDate)
                if !measurements.isEmpty {
                    store.applyHevyMeasurements(HevyImport.applyMeasurements(measurements))
                }
            }
        }
    }
}
