import SwiftUI
import UIKit

/// The card everything sits in.
///
/// The title used to be set in the same heavy, tracked, all-caps display face
/// as a hero number — which meant every single card on a page announced
/// itself at the same volume the one real headline number should have had
/// to itself, and a page of ten panels read as ten equally loud shouts
/// rather than one page with a shape to it. That face is reserved for actual
/// hero numbers now (`BigStat`, the primary figure in `MacroGrid`); a panel
/// title is a plain bold system label, the same weight class the platform's
/// own section headers use. The border is gone too, in favour of a soft
/// shadow — a hard 1px outline around a flat fill is what a `<div>` looks
/// like; a native card is lifted off the page, not outlined on it.
struct Panel<Content: View>: View {
    var title: String
    var tag: String?
    var dimmed: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.body(16, weight: .bold))
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
        .background(Theme.slate, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 4)
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
         @ViewBuilder detail: () -> Detail) {
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

/// Delays a store write until typing pauses.
///
/// Every mutation on `AppStore` ends in `reload()`, which re-fetches all ten
/// SwiftData model types to rebuild `LogState` from scratch — cheap for a
/// button tap, not cheap fired once per character. A text field wired
/// straight to `onChange` does exactly that: typing a paragraph into the
/// journal, or a rep count into a set, was triggering a full reload on every
/// keystroke. This holds a single cancellable `Task` so only the last
/// keystroke in a burst survives to actually write.
///
/// Deliberately dumb about *what* it's debouncing — callers own the "is
/// there really something pending" check (usually "does this loaded value
/// still belong to the date I'm about to write to"), because that's specific
/// to each field and this only needs to manage timing.
@MainActor
final class Debouncer {
    private var task: Task<Void, Never>?
    private let delayMilliseconds: Int

    init(delayMilliseconds: Int = 450) {
        self.delayMilliseconds = delayMilliseconds
    }

    func schedule(_ action: @escaping () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    /// Cancels whatever was pending and runs `action` immediately — for
    /// leaving a field, backgrounding the app, or anything else that can't
    /// wait out the debounce window.
    func flush(_ action: () -> Void) {
        task?.cancel()
        task = nil
        action()
    }
}

extension TickRow where Detail == EmptyView {
    /// The common case: a line with nothing under it.
    ///
    /// A constrained extension rather than `detail: () -> Detail = {
    /// EmptyView() }` on the main initialiser, because a default argument
    /// cannot bind a generic parameter the caller never mentions — omitting it
    /// leaves `Detail` uninferrable. There is no ambiguity between the two:
    /// this one has no `detail` parameter at all, so a call with a trailing
    /// detail closure can only match the other.
    init(title: String, subtitle: String? = nil, rir: String? = nil, isOn: Bool,
         enabled: Bool = true, toggle: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, rir: rir, isOn: isOn,
                  enabled: enabled, toggle: toggle) { EmptyView() }
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

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(Theme.line).frame(width: 1, height: 30)
                }
                VStack(spacing: 3) {
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
/// A thin wrapper over `DisclosureGroup` — the platform's own expand/collapse
/// control, complete with its own chevron rotation and animation, rather than
/// a hand-built `Button` + `Image(systemName: "chevron.right")` doing an
/// impression of one. The public API (`title`, `startsOpen`, a trailing
/// `content` closure) is unchanged, so nothing that already used this needed
/// to change with it.
struct Reveal<Content: View>: View {
    var title: String
    var content: Content
    @State private var isOpen: Bool

    init(title: String, startsOpen: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        _isOpen = State(initialValue: startsOpen)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            content.padding(.top, 6)
        } label: {
            Text(title)
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .tint(Theme.muted)
    }
}

/// A number field with a label and a commit button, used for weigh-ins, waist,
/// height and year of birth.
struct EntryField: View {
    var placeholder: String
    var buttonTitle: String
    var prominent: Bool
    var keyboard: UIKeyboardType
    /// Returns false to reject the entry — out of range, unparseable. The
    /// field then keeps what was typed instead of clearing it, because
    /// swallowing a rejected weigh-in looks exactly like a successful one and
    /// is how a log quietly ends up with a missing morning.
    var onCommit: (String) -> Bool

    @State private var text = ""
    @State private var rejected = false
    @FocusState private var focused: Bool

    init(placeholder: String, buttonTitle: String, prominent: Bool = true,
         keyboard: UIKeyboardType = .decimalPad, onCommit: @escaping (String) -> Bool) {
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
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(rejected ? Theme.red : Theme.line, lineWidth: 1)
                )
                .submitLabel(.done)
                .onSubmit(commit)
                .onChange(of: text) { _, _ in rejected = false }

            ActionButton(title: buttonTitle, prominent: prominent, action: commit)
        }
    }

    private func commit() {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        guard onCommit(value) else {
            // Keep the text, mark the field, let them correct it.
            rejected = true
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        rejected = false
        text = ""
        focused = false
    }
}
