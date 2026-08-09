import SwiftUI
import SwiftData

@main
@MainActor
struct BrandNewBodyApp: App {
    private let container: ModelContainer
    @State private var store: AppStore
    @State private var restTimer = RestTimer()
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
            if phase == .active { store.refresh() }
        }
    }
}
