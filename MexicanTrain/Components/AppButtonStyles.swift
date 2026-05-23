import SwiftUI

/// Three canonical action styles used app-wide. Replaces the previous
/// drift across `display 14 t=2.5 56pt cta` (primary), `display 13 t=2
/// 50pt cardBg` (secondary-A), `mono 12 t=1.8 44pt cardBg` (secondary-B),
/// and a swarm of `mono 9-11` "pills" wedged into headers and forms.
///
/// Tap targets are at least 44pt (Apple HIG minimum) — many old pills
/// were 28-34pt and easy to miss.

// MARK: - Primary

/// Big, ink-dark CTA. Use for the screen's main commit action
/// ("NEW GAME", "ADD SCORE", "SAVE CORRECTION", "JOIN").
struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.displayFont(size: 14))
            .tracking(2.5)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(theme.ctaText)
            .background(enabled ? theme.cta : theme.muted,
                        in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.55)
    }
}

// MARK: - Secondary

/// Outlined parchment button. Use for screen-level secondary actions
/// ("SHARE REPORT", "STOP SHARING", "LEAVE", "BACK TO HOME", "EXPORT
/// LABELED PHOTOS"). 44pt min height; readable from across the table.
struct AppSecondaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.monoFont(size: 13))
            .fontWeight(.semibold)
            .tracking(1.6)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(theme.ink)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                    .stroke(theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Pill (chip-sized accessory)

/// Compact accessory pill used inline in headers and rows — e.g. the
/// "SCAN QR" chip next to the room-code field, the "PICK PHOTO" chip
/// next to an avatar, the "RE-SCAN" chip on the audit reference photo.
/// Still 44pt-tall (tappable) but visually compact horizontally so it
/// sits inline alongside other content.
struct AppPillButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    var prominent: Bool = false   // true → brand color text on accent fill

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.monoFont(size: 12))
            .fontWeight(.semibold)
            .tracking(1.4)
            .foregroundStyle(prominent ? theme.ctaText : theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(prominent ? theme.brand : theme.cardBg,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(prominent ? Color.clear : theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// MARK: - Link (no chrome, brand text)

/// Tertiary text-link action. Use sparingly for inline secondary nav
/// ("BACK TO HOME", "JOIN NEARBY GAME"). Min 44pt tap target.
struct AppLinkButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.monoFont(size: 12))
            .fontWeight(.semibold)
            .tracking(1.6)
            .foregroundStyle(theme.brand)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Modifiers for convenience

extension View {
    func appPrimaryStyle(enabled: Bool = true) -> some View {
        self.buttonStyle(AppPrimaryButtonStyle(enabled: enabled))
    }
    func appSecondaryStyle() -> some View {
        self.buttonStyle(AppSecondaryButtonStyle())
    }
    func appPillStyle(prominent: Bool = false) -> some View {
        self.buttonStyle(AppPillButtonStyle(prominent: prominent))
    }
    func appLinkStyle() -> some View {
        self.buttonStyle(AppLinkButtonStyle())
    }
}
