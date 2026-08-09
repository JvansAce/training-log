import SwiftUI
import UIKit

/// The card everything sits in.
struct Panel<Content: View>: View {
    var title: String
    var tag: String?
    var dimmed: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(Theme.display(19))
                    .tracking(0.5)
                    .foregroundStyle(Theme.bone)
                Spacer(minLength: 8)
                if let tag {
                    PTag(tag)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.slate, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        .opacity(dimmed ? 0.55 : 1)
    }
}

/// The small uppercase chip in a panel header.
struct PTag: View {
    var text: String
    var tint: Color = Theme.muted

    init(_ text: String, tint: Color = Theme.muted) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(9.5))
            .tracking(1.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.raise, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Explanatory prose. Small, muted, and never competing with the numbers.
struct Note: View {
    var text: String
    var dimmed: Bool = false

    init(_ text: String, dimmed: Bool = false) {
        self.text = text
        self.dimmed = dimmed
    }

    var body: some View {
        Text(text)
            .font(Theme.body(13))
            .foregroundStyle(dimmed ? Theme.muted.opacity(0.7) : Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The verdict line: one sentence, coloured by whether it is good news.
struct VerdictLine: View {
    var text: String
    var tone: Trend.Verdict

    var body: some View {
        Text(text)
            .font(Theme.body(13.5))
            .foregroundStyle(Theme.bone)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.tone(tone).opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Theme.tone(tone).opacity(0.5), lineWidth: 1)
            )
    }
}

/// A tickable line — an exercise, a mobility drill, a mind practice.
///
/// One tap target across the whole row rather than the box alone: the web
/// version's 24 px checkbox was the single worst thing to hit with a thumb
/// mid-set.
struct TickRow<Detail: View>: View {
    var title: String
    var subtitle: String?
    var rir: String?
    var isOn: Bool
    var enabled: Bool = true
    var toggle: () -> Void
    @ViewBuilder var detail: Detail

    init(title: String, subtitle: String? = nil, rir: String? = nil, isOn: Bool,
         enabled: Bool = true, toggle: @escaping () -> Void,
         @ViewBuilder detail: () -> Detail = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.rir = rir
        self.isOn = isOn
        self.enabled = enabled
        self.toggle = toggle
        self.detail = detail()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 12) {
                    Checkbox(isOn: isOn)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(Theme.body(15, weight: .semibold))
                            .foregroundStyle(Theme.bone)
                            .multilineTextAlignment(.leading)
                        if let subtitle, !subtitle.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(subtitle)
                                    .font(Theme.body(12.5))
                                    .foregroundStyle(Theme.muted)
                                    .multilineTextAlignment(.leading)
                                if let rir {
                                    Text("\(rir) RIR")
                                        .font(Theme.mono(9.5))
                                        .foregroundStyle(Theme.amber)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityAddTraits(isOn ? [.isSelected] : [])

            detail
                .padding(.leading, 34)
        }
        .padding(.vertical, 8)
        .opacity(enabled ? 1 : 0.65)
    }
}

struct Checkbox: View {
    var isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isOn ? Theme.bone : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isOn ? Theme.bone : Theme.line, lineWidth: 1.5))
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
            }
            .frame(width: 22, height: 22)
    }
}

/// The four-up number grid: kcal / protein / carbs / fat, or the build's
/// target band.
struct MacroGrid: View {
    struct Item: Identifiable {
        var id: String { label }
        var value: String
        var label: String
        /// The `/6` in `4/6 sessions`.
        var suffix: String?
        /// A state marker — an SF Symbol beside the number, never a colour on
        /// the number itself. Colouring the text would make the state
        /// invisible to a colourblind reader and illegible at this size; an
        /// arrow says the same thing in a second channel.
        var symbol: String?
        var symbolTint: Color = Theme.green
    }

    var items: [Item]

    private let columns = [GridItem(.flexible()), GridItem(.flexible()),
                           GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items) { item in
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(item.value)
                            .font(Theme.display(22))
                            .foregroundStyle(Theme.bone)
                        if let suffix = item.suffix {
                            Text(suffix)
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.muted)
                        }
                        if let symbol = item.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(item.symbolTint)
                        }
                    }
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    Text(item.label.uppercased())
                        .font(Theme.mono(8.5))
                        .tracking(0.8)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.raise, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

/// The one enormous number at the top of a panel.
struct BigStat: View {
    var value: String
    var unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(Theme.display(52))
                .foregroundStyle(Theme.bone)
            Text(unit)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.muted)
        }
    }
}

struct Chip: View {
    var text: String
    var highlighted: Bool = false

    var body: some View {
        Text(text)
            .font(Theme.body(12))
            .foregroundStyle(highlighted ? Theme.ink : Theme.bone)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(highlighted ? Theme.amber : Theme.raise, in: Capsule())
    }
}

/// Two-column row: a name on the left, a value on the right. The history and
/// streak lists are all built from this.
struct StatRow<Leading: View, Trailing: View>: View {
    var dimmed: Bool = false
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) { leading }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) { trailing }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
        .opacity(dimmed ? 0.45 : 1)
    }
}

/// A button that looks like the web app's, in the two weights it had.
struct ActionButton: View {
    var title: String
    var prominent: Bool = false
    var destructive: Bool = false
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(13, weight: prominent ? .bold : .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(background, in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(prominent ? .clear : Theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var foreground: Color {
        if destructive && !prominent { return Theme.red }
        return Theme.bone
    }

    private var background: Color {
        if destructive && prominent { return Theme.red }
        return prominent ? Theme.red : Theme.raise
    }
}

/// A collapsible section — the web app's `<details>`.
struct Reveal<Content: View>: View {
    var title: String
    var startsOpen: Bool
    var content: Content
    /// nil until the user touches it, so `startsOpen` decides the first state
    /// without a second source of truth. Written out longhand rather than left
    /// to the memberwise initialiser: a property-wrapped stored property with
    /// no initial value becomes a required parameter, and a `private` one
    /// drags the whole initialiser down to `private` with it.
    @State private var isOpen: Bool? = nil

    init(title: String, startsOpen: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.startsOpen = startsOpen
        self.content = content()
    }

    var body: some View {
        let open = isOpen ?? startsOpen
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { isOpen = !open }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(title)
                        .font(Theme.body(13, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.muted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open { content }
        }
    }
}

/// A number field with a label and a commit button, used for weigh-ins, waist,
/// height and year of birth.
struct EntryField: View {
    var placeholder: String
    var buttonTitle: String
    var prominent: Bool
    var keyboard: UIKeyboardType
    var onCommit: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    init(placeholder: String, buttonTitle: String, prominent: Bool = true,
         keyboard: UIKeyboardType = .decimalPad, onCommit: @escaping (String) -> Void) {
        self.placeholder = placeholder
        self.buttonTitle = buttonTitle
        self.prominent = prominent
        self.keyboard = keyboard
        self.onCommit = onCommit
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .focused($focused)
                .font(Theme.body(15))
                .foregroundStyle(Theme.bone)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.raise, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
                .submitLabel(.done)
                .onSubmit(commit)

            ActionButton(title: buttonTitle, prominent: prominent, action: commit)
        }
    }

    private func commit() {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        onCommit(value)
        text = ""
        focused = false
    }
}
