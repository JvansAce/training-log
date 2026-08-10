import SwiftUI
import Charts

/// Real Swift Charts, not an SVG-style impression of one.
///
/// The first pass here hand-drew every mark with `Path` and `GeometryReader`
/// — workable, and it got the accessibility decisions right (see the note on
/// `AdherenceChart` below), but it could never look like more than a careful
/// facsimile: no native anti-aliasing on the curves, no automatic dark-mode
/// axis colour, no native animation when the data changes. `Chart` gets all
/// of that for free, which is most of why a screen built from these reads as
/// an app rather than a rendered web page.
///
/// The public surface — every struct name and its properties — is unchanged
/// from the hand-drawn version, so nothing that calls into this file needed
/// to change at all.
enum ChartSpec {
    static let lineWidth: CGFloat = 2
    static let areaOpacity: Double = 0.14
    static let barCornerRadius: CGFloat = 4
}

/// One day's recovery reading. A named struct rather than a tuple because
/// `ForEach`/`Chart` need a key path, and Swift has no key paths into tuple
/// labels.
struct RecoveryPoint: Identifiable, Equatable {
    var id: String { date }
    var date: String
    var value: Int
}

// MARK: - Sparkline

/// The last 30 weigh-ins, inline under the big number. One series, so no
/// legend — the panel title already says what it is.
struct Sparkline: View {
    var values: [Double]
    var tint: Color = Theme.red

    var body: some View {
        if values.count > 1, let low = values.min(), let high = values.max() {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("Index", index), y: .value("kg", value))
                        .lineStyle(StrokeStyle(lineWidth: ChartSpec.lineWidth, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("Index", index), y: .value("kg", value))
                        .interpolationMethod(.catmullRom)
                }
                if let last = values.indices.last {
                    PointMark(x: .value("Index", last), y: .value("kg", values[last]))
                        .foregroundStyle(Theme.bone)
                        .symbolSize(50)
                }
            }
            .foregroundStyle(tint)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            // Padded on both sides so a flat run of identical weigh-ins still
            // gets a real, non-zero range rather than a degenerate one.
            .chartYScale(domain: (low - 0.4)...(high + 0.4))
            .frame(height: 44)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Body weight

/// The full weigh-in history. Swift Charts draws its own axis, so this only
/// adds the one thing worth calling out directly: the latest reading.
struct WeightChart: View {
    var records: [WeightRecord]

    var body: some View {
        if records.count < 3 {
            Note("Log a few mornings and the curve shows up here.")
                .frame(height: 60)
        } else {
            let values = records.map(\.kg)
            let low = (values.min() ?? 0).rounded(.down) - 1
            let high = (values.max() ?? 0).rounded(.up) + 1

            VStack(alignment: .leading, spacing: 6) {
                Chart {
                    ForEach(records, id: \.date) { record in
                        LineMark(x: .value("Date", record.date), y: .value("kg", record.kg))
                            .lineStyle(StrokeStyle(lineWidth: ChartSpec.lineWidth, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)
                        AreaMark(x: .value("Date", record.date), y: .value("kg", record.kg))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .foregroundStyle(Theme.red)
                .chartXAxis(.hidden)
                .chartYScale(domain: low...high)
                .frame(height: 150)

                HStack {
                    Text(records.first?.date ?? "")
                    Spacer()
                    Text("latest \(String(format: "%.1f", records.last?.kg ?? 0)) kg")
                        .foregroundStyle(Theme.bone)
                    Spacer()
                    Text(records.last?.date ?? "")
                }
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.muted)
            }
            .accessibilityElement()
            .accessibilityLabel("Body weight over time, \(records.count) weigh-ins, latest \(String(format: "%.1f", records.last?.kg ?? 0)) kilograms")
        }
    }
}

// MARK: - Consistency

/// Eight weeks of sessions.
///
/// Colour still isn't the only channel a week's status rides on — that
/// finding came out of running the palette validator on the hand-drawn
/// version, and it doesn't stop mattering just because the marks are native
/// now. A week containing days off gets a small airplane mark alongside its
/// count, on top of its own distinct colour, the same reasoning that used a
/// hatch texture before: a red-green colourblind reader, or anyone outside
/// in bright sun, still needs a second channel to tell "away" apart from
/// "just a quiet week."
struct AdherenceChart: View {
    var bars: [Consistency.WeekBar]

    private func tint(_ bar: Consistency.WeekBar) -> Color {
        if bar.daysOff > 0 { return Theme.offBlue }
        if bar.sessions >= 4 { return Theme.green }
        if bar.sessions >= 2 { return Theme.amber }
        return Theme.muted
    }

    var body: some View {
        if bars.allSatisfy({ $0.sessions == 0 }) {
            Note("Complete a session and your weekly consistency lands here.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Chart(bars) { bar in
                    BarMark(x: .value("Week", bar.id), y: .value("Sessions", bar.sessions))
                        .foregroundStyle(tint(bar))
                        .cornerRadius(ChartSpec.barCornerRadius)
                        .annotation(position: .top) {
                            VStack(spacing: 2) {
                                if bar.daysOff > 0 {
                                    Image(systemName: "airplane")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Theme.offBlue)
                                }
                                Text("\(bar.sessions)")
                                    .font(Theme.mono(10, weight: .bold))
                                    .foregroundStyle(Theme.bone)
                            }
                        }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...7)
                .frame(height: 84)

                HStack {
                    Text("8 weeks ago")
                    Spacer()
                    Text("this week")
                }
                .font(Theme.mono(9))
                .foregroundStyle(Theme.muted)

                ChartLegend(items: [
                    .init(tint: Theme.green, label: "4+ sessions"),
                    .init(tint: Theme.amber, label: "2–3"),
                    .init(tint: Theme.muted, label: "under 2"),
                    .init(tint: Theme.offBlue, label: "ill or away", symbol: "airplane"),
                ])
            }
        }
    }
}

// MARK: - Recovery

/// Thirty days of recovery, with the mean drawn across it as a rule.
struct RecoveryChart: View {
    var days: [RecoveryPoint]

    private func tint(_ value: Int) -> Color {
        if value >= 67 { return Theme.green }
        if value >= 34 { return Theme.amber }
        return Theme.red
    }

    var body: some View {
        if days.count < 3 {
            Note("A few days of recovery and the trend lands here.")
        } else {
            let mean = Int((Double(days.reduce(0) { $0 + $1.value }) / Double(days.count)).rounded())

            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(days) { day in
                        BarMark(x: .value("Date", day.date), y: .value("Recovery", day.value))
                            .foregroundStyle(tint(day.value))
                            .cornerRadius(2)
                    }
                    RuleMark(y: .value("Mean", mean))
                        .foregroundStyle(Theme.bone.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...100)
                .frame(height: 70)

                HStack {
                    Text(days.first.map { String($0.date.dropFirst(5)) } ?? "")
                    Spacer()
                    Text("mean \(mean)%").foregroundStyle(Theme.bone)
                }
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.muted)

                ChartLegend(items: [
                    .init(tint: Theme.green, label: "67%+"),
                    .init(tint: Theme.amber, label: "34–66%"),
                    .init(tint: Theme.red, label: "under 34%"),
                ])
            }
            .accessibilityElement()
            .accessibilityLabel("Daily recovery over \(days.count) days, mean \(mean) percent")
        }
    }
}

/// Identity never rests on colour alone, so every status chart carries one
/// of these — a plain SwiftUI view rather than `Chart`'s own generated
/// legend, since these need to mix a colour swatch with an SF Symbol for
/// the one series (time off) that colour alone can't carry.
struct ChartLegend: View {
    struct Item: Identifiable {
        var id: String { label }
        var tint: Color
        var label: String
        var symbol: String? = nil
    }

    var items: [Item]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    if let symbol = item.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 8))
                            .foregroundStyle(item.tint)
                    } else {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(item.tint)
                            .frame(width: 9, height: 9)
                    }
                    Text(item.label)
                        .font(Theme.mono(8.5))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The inline e1RM trend beside a lift's name on Progress. Flat-line safe.
struct MiniSpark: View {
    var values: [Double]

    var body: some View {
        if values.count > 1 {
            let rising = (values.last ?? 0) >= (values.first ?? 0)
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("Index", index), y: .value("Value", value))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                }
            }
            .foregroundStyle(rising ? Theme.green : Theme.muted)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 54, height: 16)
            .accessibilityHidden(true)
        }
    }
}
