import SwiftUI

/// Named `ProgressPage` rather than `ProgressView`, which is already a
/// SwiftUI type — shadowing it would make every spinner in the app ambiguous.
struct ProgressPage: View {
    @Environment(AppStore.self) private var store

    private var state: LogState { store.state }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            thisWeek
            bodyWeight
            BuildPanel(state: state)
            recovery
            consistency
            topSets
        }
    }

    // MARK: This week

    private var thisWeek: some View {
        let review = Consistency.weeklyReview(state)
        return Panel(title: "This week", tag: review.label) {
            MacroGrid(items: [
                .init(value: "\(review.done)", label: "sessions", suffix: "/\(review.target)"),
                .init(value: review.delta.map { "\($0 > 0 ? "+" : "")\(String(format: "%.1f", $0))" } ?? "–",
                      label: "kg vs last wk"),
                .init(value: "\(review.improved.count)", label: "lifts up",
                      symbol: review.improved.isEmpty ? nil : "arrow.up"),
                .init(value: "\(review.streak)", label: "green weeks",
                      symbol: review.streak >= Consistency.greenWeek ? "flame.fill" : nil,
                      symbolTint: Theme.amber),
            ])

            if !review.improved.isEmpty {
                Note("Beaten this week: " +
                     review.improved.map { Plan.liftNames[$0] ?? $0 }.joined(separator: ", ") + ".")
            }
            if review.daysOff > 0 {
                Note("""
                    \(review.daysOff) day\(review.daysOff == 1 ? "" : "s") ill or away this week. The target \
                    above has come down to match, and the streak treats the week as neither won nor lost.
                    """)
            }
            Note(streakCopy(review.streak))
        }
    }

    private func streakCopy(_ streak: Int) -> String {
        if streak >= Consistency.greenWeek {
            return "\(streak) weeks running at \(Consistency.greenWeek)+ sessions. This is the part that actually builds the body — keep it boring."
        }
        if streak > 0 {
            return "\(streak) week\(streak == 1 ? "" : "s") running at \(Consistency.greenWeek)+ sessions. \(Consistency.greenWeek - streak) more for a full green month."
        }
        return "A week counts as green at \(Consistency.greenWeek)+ sessions. The streak starts with one."
    }

    // MARK: Body weight

    private var bodyWeight: some View {
        let weights = state.sortedWeights
        let gain = weights.count > 1 ? (weights.last!.kg - weights.first!.kg) : 0
        return Panel(title: "Body weight", tag: "\(weights.count) weigh-ins") {
            BigStat(value: state.latestAverage.map { String(format: "%.1f", $0) } ?? "–", unit: "kg")
            VerdictLine(text: Trend.verdictText(state), tone: Trend.verdict(state))
            WeightChart(records: weights)
            Note("""
                Since you started: \(gain > 0 ? "+" : "")\(String(format: "%.1f", gain)) kg. Target for a lean \
                bulk is +0.5–0.75 kg per month.
                """)
            WaistNote(state: state)

            if !weights.isEmpty {
                Reveal(title: "Edit weigh-ins") {
                    VStack(alignment: .leading, spacing: 0) {
                        Note("""
                            One mistyped morning sits inside the 28-day window the gain rate is measured \
                            over, and drags the calorie advice with it.
                            """)
                        ForEach(weights.reversed().prefix(14), id: \.date) { record in
                            StatRow {
                                Text(record.date)
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.muted)
                            } trailing: {
                                HStack(spacing: 10) {
                                    Text("\(String(format: "%.1f", record.kg)) kg")
                                        .font(Theme.body(13, weight: .bold))
                                        .foregroundStyle(Theme.bone)
                                    Button(role: .destructive) { store.deleteWeight(on: record.date) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Delete weigh-in for \(record.date)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Recovery

    private var recovery: some View {
        let points = state.recovery.keys.sorted().suffix(30).compactMap { date -> RecoveryPoint? in
            guard let value = state.recovery[date]?.recovery else { return nil }
            return RecoveryPoint(date: date, value: value)
        }
        return Panel(title: "Recovery", tag: "last 30 days") {
            RecoveryChart(days: Array(points))
            Note("""
                Whatever you log each morning accumulates here. Red bars clustering around your heaviest \
                weeks is the signal worth acting on — and it is the same data the deload prompt reads.
                """)
        }
    }

    // MARK: Consistency

    private var consistency: some View {
        Panel(title: "Consistency", tag: "sessions per week") {
            AdherenceChart(bars: Consistency.adherence(state))
            Note("""
                A session counts once three items are ticked — or all of them, on the shorter cardio and \
                rest days. Four green weeks in a row is the real win.
                """)
        }
    }

    // MARK: Top sets

    private var topSets: some View {
        let logged = Plan.liftIDs.filter { !(state.lifts[$0] ?? []).isEmpty }
        return Panel(title: "Top sets", tag: "best vs latest") {
            if logged.isEmpty {
                Note("Log a set on the Today page and your progression appears here.")
            } else {
                // Grouped by the session they belong to, because that is how
                // the list gets read — and it opens on the day you are about
                // to train. Collapsing by "trained recently" would do nothing:
                // there are 21 loggable lifts across the week and you train
                // the whole week, so everything is always recent.
                ForEach(groups(logged), id: \.dow) { group in
                    Reveal(title: "\(Plan.day(group.dow).label) · \(Plan.day(group.dow).title) — \(group.ids.count) lift\(group.ids.count == 1 ? "" : "s")",
                           startsOpen: group.dow == openDay(logged)) {
                        VStack(spacing: 0) {
                            ForEach(group.ids, id: \.self) { id in
                                LiftHistoryRow(state: state, liftID: id)
                            }
                        }
                    }
                }
            }
            Note("""
                e1RM is an Epley estimate from your best set — useful for comparing a heavy triple against \
                a lighter set of ten, not a number to go and test.
                """)
        }
    }

    private struct LiftGroup { var dow: Int; var ids: [String] }

    /// An id that appears on two days (`lat`, `calf`) belongs to the first.
    private func groups(_ logged: [String]) -> [LiftGroup] {
        var seen = Set<String>()
        var out: [LiftGroup] = []
        for dow in Plan.order {
            let ids = Plan.day(dow).items.compactMap(\.liftID)
                .filter { $0 != "pyramid" && logged.contains($0) && !seen.contains($0) }
            ids.forEach { seen.insert($0) }
            if !ids.isEmpty { out.append(LiftGroup(dow: dow, ids: ids)) }
        }
        return out
    }

    private func openDay(_ logged: [String]) -> Int {
        let all = groups(logged)
        return all.contains { $0.dow == state.todayDow } ? state.todayDow : (all.first?.dow ?? 1)
    }
}

private struct LiftHistoryRow: View {
    var state: LogState
    var liftID: String

    var body: some View {
        let history = state.liftHistory(liftID)
        let scored = history.compactMap { record -> (LiftRecord, LiftSet)? in
            guard let best = Lifts.bestSet(record) else { return nil }
            return (record, best)
        }
        if let latest = scored.last, let best = scored.max(by: { Lifts.beats($1.1, $0.1) }) {
            let isBest = !Lifts.beats(best.1, latest.1)
            let series = scored.compactMap { Lifts.bestE1rm($0.0) }
            let volume = Lifts.volume(latest.0)
            let stall = Lifts.stall(history)

            StatRow {
                HStack(spacing: 8) {
                    Text(Plan.liftNames[liftID] ?? liftID)
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.bone)
                    if series.count > 1 { MiniSpark(values: series) }
                }
                if let stall {
                    Text("no PR in \(stall.weeks) week\(stall.weeks == 1 ? "" : "s") · \(stall.sessions) sessions — change a variable")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } trailing: {
                HStack(spacing: 5) {
                    Text(Lifts.describe(latest.0))
                        .font(Theme.body(12.5, weight: .bold))
                        .foregroundStyle(Theme.bone)
                    if isBest {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.green)
                            .accessibilityLabel("best")
                    }
                }
                Text(Lifts.describe(volume) +
                     (Lifts.bestE1rm(latest.0).map { " · e1RM \(Int($0.rounded()))" } ?? "") +
                     " · best \(Lifts.describe(best.1)) · \(history.count) entr\(history.count == 1 ? "y" : "ies")")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

/// Waist against weight is the question a bulk actually turns on: gaining with
/// the waist flat is muscle, gaining with it climbing is not.
private struct WaistNote: View {
    var state: LogState

    var body: some View {
        Note(text)
    }

    /// Built here rather than in `body` because assembling a sentence needs
    /// statements, and a `ViewBuilder` body is not a place for them.
    private var text: String {
        let waist = state.sortedWaist
        guard let first = waist.first, let last = waist.last, waist.count >= 2 else {
            return "Log your waist twice and the comparison against bodyweight shows up here."
        }
        let deltaCm = last.cm - first.cm
        let span = DateKit.days(from: first.date, to: last.date) ?? 0
        let weights = state.sortedWeights
        let atFirst = weights.last { $0.date <= first.date }
        let atLast = weights.last { $0.date <= last.date }
        let deltaKg: Double? = (atFirst != nil && atLast != nil) ? atLast!.kg - atFirst!.kg : nil

        var verdict = ""
        if let deltaKg, span >= 14 {
            if deltaKg > 0.3 && deltaCm <= 0.5 {
                verdict = " That is the bulk working — weight up, waist holding."
            } else if deltaKg > 0.3 && deltaCm > 1.5 {
                verdict = " Waist is climbing with the scale — trim the surplus by 200 kcal."
            } else if deltaKg <= 0.3 && deltaCm <= 0.5 {
                verdict = " Neither moving much — this is maintenance, not a bulk."
            }
        }

        return "Waist \(deltaCm > 0 ? "+" : "")\(String(format: "%.1f", deltaCm)) cm"
            + (deltaKg.map { " against \($0 > 0 ? "+" : "")\(String(format: "%.1f", $0)) kg" } ?? "")
            + " over \(span) days.\(verdict)"
    }
}

private struct BuildPanel: View {
    var state: LogState
    @Environment(AppStore.self) private var store

    var body: some View {
        if let targets = Build.targets(state) {
            let kg = state.latestAverage
            let waist = state.latestWaist
            let inBand = kg.map { $0 >= Double(targets.kgLow) && $0 <= Double(targets.kgHigh) } ?? false

            Panel(title: "The build", tag: "\(state.heightCm ?? 0) cm") {
                MacroGrid(items: [
                    .init(value: "\(targets.kgLow)–\(targets.kgHigh)", label: "target kg"),
                    .init(value: "\(targets.waist)", label: "target waist"),
                    .init(value: kg.map { String(format: "%.1f", $0) } ?? "–", label: "now kg",
                          symbol: inBand ? "checkmark" : nil),
                    .init(value: waist.map { Lifts.fmt($0.cm) } ?? "–", label: "now waist",
                          symbol: waistSymbol(waist, targets), symbolTint: waistTint(waist, targets)),
                ])

                if let reading = Build.reading(state) {
                    VerdictLine(text: reading.text, tone: reading.tone)
                }

                Note("""
                    Lean and athletic rather than big: enough mass to have shape, and a waist small enough \
                    that you can see it. The band is FFMI \(Int(Build.ffmiLow))–\(Int(Build.ffmiHigh)) at \
                    around \(Int(Build.bodyFat * 100))% body fat; the waist target is \(Build.waistToHeight)× \
                    your height, with \(targets.waistLimit) cm the line you don't want to cross.
                    """)
                Note("""
                    No bulk-and-cut cycling. The surplus is small enough that you never need a deficit to \
                    undo it — at +0.5–0.75 kg a month most of what you add is lean, so there is nothing to \
                    strip off later. The waist is the brake: if it climbs, sit at maintenance for a few \
                    weeks and then start the surplus again.
                    """)
                Reveal(title: "Change height") {
                    HeightField(current: state.heightCm) { store.setHeight($0) }
                }
            }
        } else {
            Panel(title: "The build", tag: "needs your height") {
                Note("""
                    A target weight is meaningless without a height — the same 78 kg is lean on one frame \
                    and soft on another. Type yours and this works out the weight band and the waist that \
                    go with it.
                    """)
                HeightField(current: state.heightCm) { store.setHeight($0) }
            }
        }
    }

    private func waistSymbol(_ waist: WaistRecord?, _ targets: Build.Targets) -> String? {
        guard let waist else { return nil }
        if waist.cm <= Double(targets.waist) { return "checkmark" }
        if waist.cm > Double(targets.waistLimit) { return "exclamationmark" }
        return nil
    }

    private func waistTint(_ waist: WaistRecord?, _ targets: Build.Targets) -> Color {
        guard let waist, waist.cm > Double(targets.waistLimit) else { return Theme.green }
        return Theme.red
    }
}

/// Shared because the height field appears on both Progress and Setup — it is
/// the input that unlocks the target, so it belongs where the target is, and
/// it is configuration, so it belongs in Setup too.
struct HeightField: View {
    var current: Int?
    var onSet: (Int) -> Void

    var body: some View {
        EntryField(placeholder: "your height, cm",
                   buttonTitle: current == nil ? "Set height" : "Update",
                   prominent: current == nil,
                   keyboard: .numberPad) { text in
            guard let value = Int(text), value >= Build.minHeight, value <= Build.maxHeight else { return false }
            onSet(value)
            return true
        }
    }
}
