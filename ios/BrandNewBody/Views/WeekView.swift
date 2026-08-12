import SwiftUI

/// The old version put every day's full exercise list on screen at once,
/// permanently expanded — seven headers and roughly forty lines of running
/// text with nothing to anchor on, which is what "reads like a website"
/// actually meant here. This gives the page the two things it was missing:
/// a headline (which week, which day is today — every other tab opens with
/// one) and a reason to look at any single day before you've scrolled past
/// six others — today's day starts open, the rest collapse to a header you
/// scan and tap into, the same disclosure pattern Today already uses for its
/// own dense detail.
struct WeekView: View {
    @Environment(AppStore.self) private var store

    private var state: LogState { store.state }

    var body: some View {
        let weeks = state.weeksIn
        let unlocked = weeks >= Plan.addInWeek
        let pick = Plan.addIns[weeks % Plan.addIns.count]

        LazyVStack(alignment: .leading, spacing: 22) {
            WeekHero(state: state)

            Panel(title: "The week", tag: "4 lifts · 1 tennis · 1 cardio") {
                Note("""
                    Priority order when life gets busy: keep the four lifting days, drop Thursday cardio \
                    first, the pyramid second.
                    """)
                ForEach(Plan.order, id: \.self) { dow in
                    DayRow(dow: dow, state: state)
                }
            }

            Panel(title: "Fuel rules", tag: "reference") {
                FuelRuleGrid()
                ForEach(Self.fuelNotes, id: \.self) { rule in
                    Note(rule)
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

    private static let fuelNotes = [
        "Scale flat two weeks — add 200 kcal, easiest as milk and a bigger rice portion",
        "Protein at every meal — 170g over five feedings beats two giant ones",
        "Tennis Mondays — proper carb meal 2–3h before, shake straight after",
    ]
}

// MARK: - Hero

/// Every other tab opens with a headline — Today's session count, Progress's
/// weekly stats. This one had none, just a panel title identical in weight to
/// every other panel title on the page. The week number plus a plain,
/// non-interactive echo of Today's own weekday strip gives it one, without
/// duplicating the live session/streak numbers Progress already owns for
/// "this week" — this strip is about which day of the plan you're looking
/// at, not what you've done.
private struct WeekHero: View {
    var state: LogState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Week \(state.weeksIn + 1)")
                .font(Theme.display(30))
                .foregroundStyle(Theme.bone)

            HStack(spacing: 4) {
                ForEach(Plan.order, id: \.self) { dow in
                    let day = Plan.day(dow)
                    let isToday = dow == state.todayDow
                    VStack(spacing: 5) {
                        Text(day.label)
                            .font(Theme.mono(10, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Theme.bone : Theme.muted)
                        Circle()
                            .fill(day.color.opacity(isToday ? 1 : 0.4))
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isToday ? Theme.raise : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

// MARK: - Day row

/// A collapsed header — the colour, the day, what kind of day it is — with
/// the actual exercise breakdown behind the same `Reveal` disclosure Today
/// uses. Today's own row starts open; every other day is a header you can
/// scan without reading five lines of prescription text you didn't ask for.
private struct DayRow: View {
    var dow: Int
    var state: LogState

    private var day: TrainingDay { Plan.day(dow) }
    private var isToday: Bool { dow == state.todayDow }
    /// Same filter Today applies — otherwise a knee-care substitution shows
    /// up here as two items instead of one, since both sides are real,
    /// permanent entries in `Plan.schedule`. See `Knee.swift`.
    private var items: [Exercise] { Knee.adjustedItems(day.items, kneeCareMode: state.kneeCareMode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(day.color).frame(width: 7, height: 7)
                Text(day.label)
                    .font(Theme.mono(10, weight: isToday ? .bold : .regular))
                    .foregroundStyle(Theme.muted)
                Text(day.title)
                    .font(Theme.body(14, weight: .bold))
                    .foregroundStyle(Theme.bone)
                Spacer(minLength: 8)
                PTag(day.tag)
            }
            Reveal(title: "\(items.count) item\(items.count == 1 ? "" : "s")", startsOpen: isToday) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        let isPyramid = item.key == "sa-pyramid"
                        Text((isPyramid ? Pyramid.itemName(state) : item.displayName(state)) +
                             (item.prescription.isEmpty && !isPyramid ? "" :
                                " — " + (isPyramid ? Pyramid.itemPrescription : item.prescription)))
                            .font(Theme.body(12.5))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(10)
        .background(isToday ? Theme.raise.opacity(0.5) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

// MARK: - Fuel

/// The plan's two starting numbers side by side as the same stat grid every
/// other calorie/macro figure in the app uses, instead of two lines of prose
/// buried in a bullet list. Comparable numbers belong next to each other, not
/// one paragraph apart.
private struct FuelRuleGrid: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            fuelRow(label: "Training / tennis days", kcal: 3200, protein: 170, carbs: 416, fat: 95)
            Rectangle().fill(Theme.line).frame(height: 1)
            fuelRow(label: "Rest days (Thu, Sun)", kcal: 2900, protein: 170, carbs: 352, fat: 90)
        }
    }

    private func fuelRow(label: String, kcal: Int, protein: Int, carbs: Int, fat: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(Theme.mono(10))
                .tracking(0.8)
                .foregroundStyle(Theme.muted)
            MacroGrid(items: [
                .init(value: "\(kcal)", label: "kcal"),
                .init(value: "\(protein)", label: "protein"),
                .init(value: "\(carbs)", label: "carbs"),
                .init(value: "\(fat)", label: "fat"),
            ])
        }
    }
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
