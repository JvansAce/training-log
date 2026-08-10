import SwiftUI

/// The four sections of Today whose order is a matter of habit, not
/// meaning. Vitals, Fuel and Mobility never depend on one appearing before
/// another — only the session's position relative to the contextual
/// banners (time off, deload) matters, and those aren't in this list at
/// all, because a state banner isn't a "section" someone would want to drag
/// below their macros.
enum TodaySection: String, CaseIterable, Identifiable, Codable {
    case vitals, session, fuel, mobility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vitals: return "Vitals"
        case .session: return "Today's session"
        case .fuel: return "Fuel"
        case .mobility: return "Mobility"
        }
    }

    var subtitle: String {
        switch self {
        case .vitals: return "Weight and recovery, at a glance"
        case .session: return "The checklist and per-set logging"
        case .fuel: return "Calories and macros"
        case .mobility: return "Daily mobility drills"
        }
    }
}

/// Persisted as a plain comma-joined string rather than through `Data` and
/// `JSONEncoder` — four fixed cases don't need that ceremony, and a string
/// is trivially inspectable or resettable by hand if it ever needs to be.
/// Unrecognised or missing entries — a future section renamed or added —
/// fall back to declaration order rather than silently dropping content:
/// `load` always returns all four, never fewer.
enum TodaySectionOrderStore {
    static let key = "todaySectionOrder"
    static let defaultRaw = TodaySection.allCases.map(\.rawValue).joined(separator: ",")

    static func load(from raw: String) -> [TodaySection] {
        let parsed = raw.split(separator: ",").compactMap { TodaySection(rawValue: String($0)) }
        let missing = TodaySection.allCases.filter { !parsed.contains($0) }
        return parsed + missing
    }

    static func save(_ order: [TodaySection]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }
}

/// A dedicated reorder screen rather than drag handles mixed into Today's
/// own scroll view. Today already carries per-set text fields, a rest
/// timer, and disclosure groups — layering drag-to-reorder gestures over
/// all of that live is exactly the kind of interaction that's easy to get
/// subtly wrong in a way only shows up on a device. This is the same
/// pattern Apple uses for reordering Home Screen widgets or Control Center
/// modules: a separate, single-purpose list, edit mode forced on because
/// reordering is the only thing this screen does.
struct TodaySectionOrderView: View {
    @AppStorage(TodaySectionOrderStore.key) private var orderRaw = TodaySectionOrderStore.defaultRaw
    @State private var order: [TodaySection] = []

    var body: some View {
        List {
            ForEach(order) { section in
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                    Text(section.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onMove { indices, offset in
                order.move(fromOffsets: indices, toOffset: offset)
                orderRaw = TodaySectionOrderStore.save(order)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Today's order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") {
                    order = TodaySection.allCases
                    orderRaw = TodaySectionOrderStore.defaultRaw
                }
            }
        }
        .onAppear {
            if order.isEmpty { order = TodaySectionOrderStore.load(from: orderRaw) }
        }
    }
}
