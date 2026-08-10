import SwiftUI

extension Color {
    /// `"E23B3B"` or `"#E23B3B"`. Falls back to clear rather than trapping —
    /// a mistyped hex in the plan table should show up as an invisible dot,
    /// not as a crash on the Week page.
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .clear
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// The palette and type scale, carried across from `app.css` so the two
/// versions look like the same product.
///
/// Deliberately one fixed dark scheme rather than a light/dark pair: the app
/// is read in a badly-lit gym at arm's length, and the whole design — a bone
/// display face on near-black, one red accent — was drawn for that. A light
/// mode would be a different design, not a recolouring.
enum Theme {
    static let ink = Color(hex: "141824")
    static let slate = Color(hex: "1B2130")
    static let raise = Color(hex: "222A3C")
    static let line = Color(hex: "2E3750")
    static let bone = Color(hex: "EDE7DB")
    static let muted = Color(hex: "868FA6")
    static let red = Color(hex: "E23B3B")
    static let blue = Color(hex: "4C7BE8")
    static let green = Color(hex: "4FB477")
    static let amber = Color(hex: "D9A13B")
    /// The colour a bar gets when the week contained days off — deliberately
    /// neither the pass green nor the fail grey.
    static let offBlue = Color(hex: "4C5878")

    /// Condensed and heavy, for the masthead and the big numbers. The web app
    /// used Big Shoulders Display; the nearest thing every iPhone already has
    /// is a wide-tracked, heavy rounded face, and shipping a webfont for four
    /// headings is not worth the launch cost.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Colour for a verdict line.
    static func tone(_ verdict: Trend.Verdict) -> Color {
        switch verdict {
        case .slow: return amber
        case .fast: return red
        case .ok: return green
        case .unknown: return muted
        }
    }
}
