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

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(RestTimer.self) private var timer

    @AppStorage("programme") private var programmeRaw = Programme.body.rawValue
    @State private var tab: Tab = .today

    private var programme: Programme {
        get { Programme(rawValue: programmeRaw) ?? .body }
        nonmutating set { programmeRaw = newValue.rawValue }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.ink.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Masthead(programme: programme, tab: tab) { programme = $0 }
                        page
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)

                if timer.isRunning { RestTimerBar() }

                TabBar(selection: $tab)
            }
        }
        .animation(.snappy(duration: 0.2), value: timer.isRunning)
        .task { store.refresh() }
    }

    @ViewBuilder
    private var page: some View {
        // Setup is shared: it is configuration for the app, not for one of the
        // two programmes.
        if tab == .setup {
            SetupView()
        } else if programme == .body {
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
}

private struct Masthead: View {
    @Environment(AppStore.self) private var store
    var programme: Programme
    var tab: Tab
    var onSwitch: (Programme) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased())
                .font(Theme.mono(10))
                .tracking(2.2)
                .foregroundStyle(Theme.muted)

            (Text("BRAND\nNEW ").foregroundStyle(Theme.bone)
             + Text(programme.title.uppercased()).foregroundStyle(Theme.red))
                .font(Theme.display(46))
                .lineSpacing(-8)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                ForEach(Programme.allCases) { option in
                    Button { onSwitch(option) } label: {
                        Text(option.title.uppercased())
                            .font(Theme.mono(10, weight: option == programme ? .bold : .regular))
                            .tracking(1.6)
                            .foregroundStyle(option == programme ? Theme.bone : Theme.muted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(option == programme ? Theme.red : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(option == programme ? .clear : Theme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eyebrow: String {
        let state = store.state
        var parts: [String] = []
        if let date = DateKit.date(state.today) {
            parts.append(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        }
        parts.append("week \(state.weeksIn + 1)")
        if let kind = TimeOff.today(state) { parts.append(kind.label) }
        return parts.joined(separator: " · ")
    }
}

private struct TabBar: View {
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.title.uppercased())
                            .font(Theme.mono(8.5))
                            .tracking(1.2)
                    }
                    .foregroundStyle(selection == tab ? Theme.bone : Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .background(Theme.slate)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
