import SwiftUI

struct WeekView: View {
    @Environment(AppStore.self) private var store

    private var state: LogState { store.state }

    var body: some View {
        let weeks = state.weeksIn
        let unlocked = weeks >= Plan.addInWeek
        let pick = Plan.addIns[weeks % Plan.addIns.count]

        VStack(alignment: .leading, spacing: 14) {
            Panel(title: "The week", tag: "4 lifts · 1 tennis · 1 cardio") {
                Note("""
                    Priority order when life gets busy: keep the four lifting days, drop Thursday cardio \
                    first, the pyramid second.
                    """)
                ForEach(Plan.order, id: \.self) { dow in
                    let day = Plan.day(dow)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Circle().fill(day.color).frame(width: 7, height: 7)
                            Text(day.title)
                                .font(Theme.body(14, weight: .bold))
                                .foregroundStyle(Theme.bone)
                            Spacer()
                            PTag(day.label)
                        }
                        ForEach(day.items) { item in
                            let isPyramid = item.key == "sa-pyramid"
                            Text((isPyramid ? Pyramid.itemName(state) : item.name) +
                                 (item.prescription.isEmpty && !isPyramid ? "" :
                                    " — " + (isPyramid ? Pyramid.itemPrescription : item.prescription)))
                                .font(Theme.body(12.5))
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }

            Panel(title: "Fuel rules", tag: "reference") {
                ForEach(Self.fuelRules, id: \.self) { rule in
                    Text(rule)
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                }
                Note("""
                    Those are the plan's starting numbers. What the Fuel panel actually shows you is \
                    calculated from your own bodyweight, height and age, so it keeps up as you gain.
                    """)
            }

            Panel(title: "Add-ins",
                  tag: unlocked ? "unlocked" : "week \(weeks) of \(Plan.addInWeek)",
                  dimmed: !unlocked) {
                Note(unlocked
                    ? "Rotate one into Saturday or in place of Thursday every couple of weeks. They replace conditioning slots — never stack on top. This week: \(pick)."
                    : "Build the base first. These open at week \(Plan.addInWeek), once the four lifting days are habit and the scale is moving.")
                FlowChips(items: Plan.addIns, highlighted: unlocked ? pick : nil)
            }
        }
    }

    private static let fuelRules = [
        "Training / tennis days — 3,200 kcal · 170g protein · ~416g carbs · 95g fat",
        "Rest days (Thu, Sun) — 2,900 kcal · 170g protein · ~352g carbs · 90g fat",
        "Scale flat two weeks — add 200 kcal, easiest as milk and a bigger rice portion",
        "Protein at every meal — 170g over five feedings beats two giant ones",
        "Tennis Mondays — proper carb meal 2–3h before, shake straight after",
    ]
}

/// Chips that wrap. `LazyVGrid` with adaptive columns rather than a hand-rolled
/// flow layout: the chips here are short and a ragged grid reads the same as
/// a flow at this size.
struct FlowChips: View {
    var items: [String]
    var highlighted: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)],
                  alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Chip(text: item, highlighted: item == highlighted)
            }
        }
    }
}
