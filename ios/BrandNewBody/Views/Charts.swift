import SwiftUI

/// Every chart here is hand-drawn rather than built on Swift Charts, for the
/// same reason the web version was hand-drawn SVG: the specs below — 2px
/// lines, a 10% area wash, 4px rounded bar caps square at the baseline, a 2px
/// surface gap between neighbours, hairline *solid* gridlines — are the design,
/// and fighting a framework's defaults to reach them costs more than drawing
/// four small shapes.
///
/// One inherited defect is fixed on the way across. The web app coloured a
/// week containing days off `#4C5878` and a bad week `#2E3750`: two blues 12.4
/// ΔE apart, which is under the threshold at which normal colour vision can
/// separate them, and the second sat at 1.36:1 on the panel — a bad week read
/// as no week at all. Time off is now a **hatch** rather than a hue, so the
/// distinction survives both colour blindness and a phone held at arm's length
/// in a dark gym, and the low-session colour is a step that is actually
/// visible.
enum ChartSpec {
    static let lineWidth: CGFloat = 2
    static let areaOpacity: Double = 0.12
    static let markerRadius: CGFloat = 4
    /// Marks carry a ring in the surface colour so they stay legible where
    /// they cross the line.
    static let ringWidth: CGFloat = 2
    static let barCornerRadius: CGFloat = 4
    static let gridWidth: CGFloat = 1
}

/// Rounded at the data end, square at the baseline — a bar grows from the
/// axis, so rounding the foot would lift it off.
private struct BarShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 45° hatch, used so "this week contained days off" is a texture rather than
/// a second blue nobody can distinguish from the first.
private struct Hatch: View {
    var color: Color

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let step: CGFloat = 5
                let extent = geo.size.width + geo.size.height
                var x = -geo.size.height
                while x < extent {
                    path.move(to: CGPoint(x: x, y: geo.size.height))
                    path.addLine(to: CGPoint(x: x + geo.size.height, y: 0))
                    x += step
                }
            }
            .stroke(color, lineWidth: 1.5)
        }
    }
}

/// Normalised points for a series, oldest first.
private func points(_ values: [Double], in size: CGSize, padding: Double) -> [CGPoint] {
    guard values.count > 1 else { return [] }
    let low = (values.min() ?? 0) - padding
    let high = (values.max() ?? 0) + padding
    let span = high - low
    guard span > 0 else {
        // A flat series would divide by zero and blank the chart. Draw it
        // through the middle instead, which is the truth: nothing changed.
        return values.enumerated().map { index, _ in
            CGPoint(x: size.width * Double(index) / Double(values.count - 1), y: size.height / 2)
        }
    }
    return values.enumerated().map { index, value in
        CGPoint(x: size.width * Double(index) / Double(values.count - 1),
                y: size.height * (1 - (value - low) / span))
    }
}

private func line(through points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() { path.addLine(to: point) }
    return path
}

/// The same line closed down to the baseline, for the area wash. Built here
/// rather than inline because a `ViewBuilder` body is not a place to mutate a
/// `Path`.
private func area(under points: [CGPoint], in size: CGSize) -> Path {
    var path = line(through: points)
    guard !points.isEmpty else { return path }
    path.addLine(to: CGPoint(x: size.width, y: size.height))
    path.addLine(to: CGPoint(x: 0, y: size.height))
    path.closeSubpath()
    return path
}

/// One day's recovery reading. A named struct rather than a tuple because
/// `ForEach(_:id:)` needs a key path, and Swift has no key paths into tuple
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
        GeometryReader { geo in
            let pts = points(values, in: geo.size, padding: 0.4)
            if pts.count > 1 {
                ZStack {
                    area(under: pts, in: geo.size)
                        .fill(tint.opacity(ChartSpec.areaOpacity))
                    line(through: pts)
                        .stroke(tint, style: StrokeStyle(lineWidth: ChartSpec.lineWidth,
                                                         lineCap: .round, lineJoin: .round))
                    if let last = pts.last {
                        Circle()
                            .fill(Theme.bone)
                            .overlay(Circle().stroke(Theme.slate, lineWidth: ChartSpec.ringWidth))
                            .frame(width: ChartSpec.markerRadius * 2, height: ChartSpec.markerRadius * 2)
                            .position(last)
                    }
                }
            }
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }
}

// MARK: - Body weight

/// The full weigh-in history, with the floor and ceiling of the range called
/// out. Gridlines are hairline and solid — dashing them adds noise and reads
/// as a second kind of line.
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
                GeometryReader { geo in
                    let pts = points(values, in: geo.size, padding: 1)
                    ZStack(alignment: .topLeading) {
                        // Range rules, one step off the surface so they stay
                        // recessive.
                        VStack {
                            Rectangle().fill(Theme.line).frame(height: ChartSpec.gridWidth)
                            Spacer()
                            Rectangle().fill(Theme.line).frame(height: ChartSpec.gridWidth)
                        }

                        area(under: pts, in: geo.size)
                            .fill(Theme.red.opacity(ChartSpec.areaOpacity))

                        line(through: pts)
                            .stroke(Theme.red, style: StrokeStyle(lineWidth: ChartSpec.lineWidth,
                                                                  lineCap: .round, lineJoin: .round))
                        if let last = pts.last {
                            Circle()
                                .fill(Theme.bone)
                                .overlay(Circle().stroke(Theme.slate, lineWidth: ChartSpec.ringWidth))
                                .frame(width: ChartSpec.markerRadius * 2 + 2,
                                       height: ChartSpec.markerRadius * 2 + 2)
                                .position(last)
                        }
                    }
                }
                .frame(height: 150)

                // Axis text wears a text token, never the series colour.
                HStack {
                    Text("\(Lifts.fmt(low)) – \(Lifts.fmt(high)) kg")
                    Spacer()
                    // The endpoint is the one value worth labelling directly.
                    Text("latest \(String(format: "%.1f", records.last?.kg ?? 0)) kg")
                }
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.muted)

                HStack {
                    Text(records.first?.date ?? "")
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
/// The count sits on every cap, which is deliberate and is why there is no
/// y-axis: with eight bars and single-digit values the labels *are* the axis,
/// and they double as the secondary encoding that lets the green/amber pair
/// stay legible for a red-green colourblind reader (they sit 6.4 ΔE apart
/// under protanopia — legal only alongside a non-colour channel).
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom, spacing: 6) {   // the 2px+ surface gap between neighbours
                    ForEach(bars) { bar in
                        VStack(spacing: 5) {
                            Text("\(bar.sessions)")
                                .font(Theme.mono(11, weight: .bold))
                                .foregroundStyle(Theme.bone)
                            BarShape(radius: ChartSpec.barCornerRadius)
                                .fill(tint(bar).opacity(bar.daysOff > 0 ? 0.22 : 1))
                                .overlay {
                                    if bar.daysOff > 0 {
                                        Hatch(color: Theme.offBlue)
                                            .clipShape(BarShape(radius: ChartSpec.barCornerRadius))
                                    }
                                }
                                .frame(maxWidth: 24)
                                .frame(height: max(3, CGFloat(min(bar.sessions, 6)) / 6 * 64))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 84, alignment: .bottom)

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
                    .init(tint: Theme.offBlue, label: "ill or away", hatched: true),
                ])
            }
        }
    }
}

// MARK: - Recovery

/// Thirty days of recovery, with the mean drawn across it.
///
/// Thirty bars is too many to label, so the value rides the bar's *height* and
/// the colour band is redundant reinforcement rather than the only channel —
/// which is what makes the three status hues safe here. The legend names the
/// bands so nothing depends on recognising the colours.
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
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 1.5) {
                        ForEach(days) { day in
                            BarShape(radius: 2)
                                .fill(tint(day.value))
                                .frame(height: max(2, CGFloat(day.value) / 100 * 70))
                        }
                    }
                    .frame(height: 70, alignment: .bottom)

                    // Solid hairline, not dashed: a dashed rule reads as a
                    // second kind of data rather than as chrome.
                    Rectangle()
                        .fill(Theme.bone.opacity(0.5))
                        .frame(height: ChartSpec.gridWidth)
                        .offset(y: -CGFloat(mean) / 100 * 70)
                }
                .frame(height: 70)

                HStack {
                    Text(days.first.map { String($0.date.dropFirst(5)) } ?? "")
                    Spacer()
                    Text("mean \(mean)%")
                        .foregroundStyle(Theme.bone)
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

/// Identity never rests on colour alone, so every status chart carries one of
/// these.
struct ChartLegend: View {
    struct Item: Identifiable {
        var id: String { label }
        var tint: Color
        var label: String
        var hatched: Bool = false
    }

    var items: [Item]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.tint.opacity(item.hatched ? 0.22 : 1))
                        .overlay {
                            if item.hatched {
                                Hatch(color: item.tint)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                            }
                        }
                        .frame(width: 9, height: 9)
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
        GeometryReader { geo in
            let pts = points(values, in: geo.size, padding: 0)
            if pts.count > 1 {
                let rising = (values.last ?? 0) >= (values.first ?? 0)
                line(through: pts)
                    .stroke(rising ? Theme.green : Theme.muted,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: 54, height: 16)
        .accessibilityHidden(true)
    }
}
