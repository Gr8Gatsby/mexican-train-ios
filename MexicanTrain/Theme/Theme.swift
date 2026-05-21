import SwiftUI

struct Theme: Equatable {
    let bg: Color
    let headerBg: Color
    let subBg: Color
    let cardBg: Color
    let ink: Color
    let muted: Color
    let border: Color
    let borderLight: Color
    let brand: Color
    let accent: Color
    let youBg: Color
    let currentColumn: Color
    let cta: Color
    let ctaText: Color

    let displayFontName: String
    let monoFontName: String

    let buttonCornerRadius: CGFloat
}

extension Theme {
    static let caboose = Theme(
        bg:            Color(hex: 0xF4EAD5),
        headerBg:      Color(hex: 0xEAD5A8),
        subBg:         Color(hex: 0xEDE0BD),
        cardBg:        Color(hex: 0xFBF4E2),
        ink:           Color(hex: 0x2A1D10),
        muted:         Color(hex: 0x8A6D44),
        border:        Color(hex: 0xC2A778),
        borderLight:   Color(hex: 0xD9C294),
        brand:         Color(hex: 0x8C2A1A),
        accent:        Color(hex: 0xC8541D),
        youBg:         Color(red: 140/255, green: 42/255, blue: 26/255, opacity: 0.07),
        currentColumn: Color(red: 200/255, green: 84/255, blue: 29/255, opacity: 0.10),
        cta:           Color(hex: 0x2A1D10),
        ctaText:       Color(hex: 0xF4EAD5),
        displayFontName: "Rye-Regular",
        monoFontName:    "SpecialElite-Regular",
        buttonCornerRadius: 16
    )
}

extension Theme {
    /// Display font with a graceful fallback to a bold serif when the bundled
    /// TTF is missing. Custom path is anchored via `relativeTo:` so it scales
    /// with Dynamic Type; system fallback scales natively.
    func displayFont(size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        if UIFont(name: displayFontName, size: size) != nil {
            return .custom(displayFontName, size: size, relativeTo: style)
        }
        return .system(size: size, weight: .bold, design: .serif)
    }

    func monoFont(size: CGFloat, relativeTo style: Font.TextStyle = .footnote) -> Font {
        if UIFont(name: monoFontName, size: size) != nil {
            return .custom(monoFontName, size: size, relativeTo: style)
        }
        return .system(size: size, weight: .regular, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, opacity: opacity)
    }
}
