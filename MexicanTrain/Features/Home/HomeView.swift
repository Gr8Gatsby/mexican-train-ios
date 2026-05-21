import SwiftUI

struct HomeView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer()
                emptyState
                Spacer()
                cta
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var header: some View {
        HStack {
            Text("MEX·TRAIN")
                .font(theme.displayFont(size: 22))
                .tracking(2)
                .foregroundStyle(theme.brand)
            Spacer()
            Text("v0.1")
                .font(theme.monoFont(size: 11))
                .foregroundStyle(theme.muted)
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No games yet")
                .font(theme.displayFont(size: 28))
                .foregroundStyle(theme.ink)
            Text("All aboard. Tap below to start your first game.")
                .font(theme.monoFont(size: 12))
                .tracking(1.4)
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var cta: some View {
        Button(action: {}) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("NEW GAME")
                    .font(theme.displayFont(size: 14))
                    .tracking(2.5)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(theme.ctaText)
            .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
        }
        .disabled(true)
        .opacity(0.55)
    }
}

#Preview {
    HomeView()
        .environment(\.theme, .caboose)
}
