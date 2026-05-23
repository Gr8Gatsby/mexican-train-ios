import SwiftUI

/// Hero card celebrating the winner. Used both as the on-screen card in
/// `EndGameView` and as the source for a shareable PNG (via
/// `ImageRenderer`) when the conductor taps SHARE WINNER. In share mode
/// we render slightly larger type + a full opaque background so the image
/// reads on any chat surface.
struct WinnerCard: View {
    let name: String
    let total: Int
    let gameName: String
    let dateText: String
    let theme: Theme
    var shareMode: Bool = false

    var body: some View {
        VStack(spacing: shareMode ? 14 : 10) {
            Text("ALL ABOARD · WINNER")
                .font(theme.monoFont(size: shareMode ? 14 : 11))
                .tracking(2.4)
                .foregroundStyle(theme.muted)

            Image(systemName: "trophy.fill")
                .font(.system(size: shareMode ? 120 : 88, weight: .bold))
                .foregroundStyle(theme.brand)
                .shadow(color: theme.brand.opacity(0.25),
                        radius: shareMode ? 6 : 4, x: 0, y: 2)

            Text(name)
                .font(theme.displayFont(size: shareMode ? 56 : 44))
                .foregroundStyle(theme.brand)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .lineLimit(2)

            Text("\(total) pips")
                .font(theme.monoFont(size: shareMode ? 18 : 14))
                .tracking(1.4)
                .foregroundStyle(theme.ink)

            if shareMode {
                Divider().overlay(theme.borderLight).padding(.horizontal, 40)
                VStack(spacing: 2) {
                    Text(gameName)
                        .font(theme.monoFont(size: 14))
                        .foregroundStyle(theme.muted)
                    Text(dateText)
                        .font(theme.monoFont(size: 12))
                        .foregroundStyle(theme.muted)
                }
            }
        }
        .padding(shareMode ? 32 : 22)
        .frame(maxWidth: .infinity)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: shareMode ? 18 : 14))
        .overlay(
            RoundedRectangle(cornerRadius: shareMode ? 18 : 14)
                .stroke(theme.brand, lineWidth: shareMode ? 2 : 1.5)
        )
        .background(shareMode ? theme.bg : Color.clear)
    }
}
