import SwiftUI

enum Programme: String, CaseIterable, Identifiable {
    case body, mind
    var id: String { rawValue }
    var title: String { self == .body ? "Body" : "Mind" }
}

enum Tab: String, CaseIterable, Identifiable {
    case today, week, progress, setup
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .today: return "flame"
        case .week: return "calendar"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .setup: return "gearshape"
        }
    }
}

/// A real `TabView`, not a hand-drawn bar.
///
/// This is the one change that costs nothing and buys the most: a standard
/// `TabView` picks up whatever tab bar the OS it's running on actually
/// draws — the floating, scroll-minimizing glass bar on iOS 26, the classic
/// opaque one on older versions — with no version-specific code on this
/// side at all. The system control has always worked this way; that's the
/// entire point of using one instead of redrawing it by hand.
///
/// Each tab owns its own `NavigationStack`, which is what turns "Today" from
/// a giant custom wordmark sitting above the content into an actual
/// navigation bar title — the thing the platform expects to find there, and
/// the detail that most says "native" versus "web page in a box."
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(RestTimer.self) private var timer
    @Environment(WhoopClient.self) private var whoop

    @AppStorage("programme") private var programmeRaw = Programme.body.rawValue
    @State private var tab: Tab = .today

    private var programme: Programme {
        get { Programme(rawValue: programmeRaw) ?? .body }
        nonmutating set { programmeRaw = newValue.rawValue }
    }

    var body: some View {
        TabView(selection: $tab) {
            ForEach(Tab.allCases) { entry in
                NavigationStack {
                    content(for: entry)
                        .navigationTitle(entry.title)
                        .navigationBarTitleDisplayMode(.large)
                        .toolbar { programmeToolbar(for: entry) }
                        // Setup is a native Form and wants the system's own
                        // grouped background; every other tab still carries
                        // the app's brand fill behind its card panels, which
                        // none of them paint themselves — they always
                        // depended on this container providing it.
                        .background(entry == .setup ? Color.clear : Theme.ink)
                }
                .tabItem { Label(entry.title, systemImage: entry.symbol) }
                .tag(entry)
            }
        }
        // The standard trick for a persistent bar that floats above the tab
        // bar rather than under it — the same mechanism apps use for a
        // "now playing" strip. `.overlay` would sit on top of content
        // without making room for it; this reserves the space properly, and
        // it's on the TabView itself so the timer survives a tab switch
        // exactly like the global state backing it already does.
        .safeAreaInset(edge: .bottom) {
            if timer.isRunning { RestTimerBar() }
        }
        .animation(.snappy(duration: 0.2), value: timer.isRunning)
        .task {
            // Belt and suspenders alongside the App's scene-phase handler:
            // `.task` runs once this view first appears, which covers a cold
            // launch reliably even on the rare run where the very first
            // `scenePhase` transition to `.active` is missed.
            store.refresh()
            await whoop.fetchToday(dayKey: store.state.today)
            if let reading = whoop.today?.recovery {
                store.applyWhoopReading(reading, on: store.state.today)
            }
        }
    }

    @ViewBuilder
    private func content(for tab: Tab) -> some View {
        // Setup is a Form and scrolls itself — wrapping it in another
        // ScrollView would nest two scroll surfaces inside one another,
        // which is exactly the kind of thing that reads as broken rather
        // than merely inelegant.
        if tab == .setup {
            SetupView()
        } else {
            ScrollView {
                pageBody(for: tab)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            // One bar here covers every field on Today, Week and Progress in
            // both programmes — the weigh-in, the waist, every per-set kg and
            // reps box, the Mind minutes, the session note and the journal.
            // Setup is the other branch and brings its own.
            .keyboardDoneBar()
        }
    }

    @ViewBuilder
    private func pageBody(for tab: Tab) -> some View {
        // Setup is shared: it is configuration for the app, not for one of
        // the two programmes, so it never reads `programme`. It's also
        // handled above before this is ever called.
        if programme == .body {
            switch tab {
            case .today: TodayView()
            case .week: WeekView()
            case .progress: ProgressPage()
            case .setup: EmptyView()
            }
        } else {
            switch tab {
            case .today: MindTodayView()
            case .week: MindWeekView()
            case .progress: MindProgressView()
            case .setup: EmptyView()
            }
        }
    }

    /// The Body/Mind switch, replacing what the old masthead's row of two
    /// buttons did — as a toolbar item now, because that's where a
    /// same-screen mode switch belongs, not stacked above the content like
    /// another block of the page.
    ///
    /// On iOS 26, a plain `ToolbarItem` also gets its own automatic Liquid
    /// Glass background capsule — and the segmented picker's own style is
    /// *also* a capsule now, not the old rounded rectangle, with no way to
    /// opt out of that shape. Without `sharedBackgroundVisibility(.hidden)`
    /// the two stack: the toolbar's glass pill drawn around the picker's own
    /// glass pill, which is the doubled/overlapping-shape look this was
    /// reported as. Gated on availability since the deployment target is
    /// iOS 17 — older OSes never had the extra background to begin with, so
    /// they're unaffected either way.
    @ToolbarContentBuilder
    private func programmeToolbar(for tab: Tab) -> some ToolbarContent {
        if tab != .setup {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { programmePicker }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { programmePicker }
            }
        }
    }

    private var programmePicker: some View {
        Picker("Programme", selection: Binding(
            get: { programme },
            set: { programme = $0 }
        )) {
            ForEach(Programme.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}
