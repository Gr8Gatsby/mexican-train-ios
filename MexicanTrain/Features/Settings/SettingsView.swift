import SwiftUI

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var bind = settings
        return ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("DEFAULT GAME LENGTH") {
                            HStack(spacing: 8) {
                                ForEach([7, 10, 13], id: \.self) { n in
                                    Button { bind.defaultLengthStops = n } label: {
                                        Text("\(n)")
                                            .font(theme.displayFont(size: 22))
                                            .frame(maxWidth: .infinity, minHeight: 52)
                                            .foregroundStyle(settings.defaultLengthStops == n ? theme.ctaText : theme.ink)
                                            .background(settings.defaultLengthStops == n ? theme.cta : theme.cardBg,
                                                        in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                                                    .stroke(theme.border, lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                        section("DEFAULT \"YOU\" NAME") {
                            TextField("Your name", text: $bind.defaultYouName)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(theme.borderLight, lineWidth: 1)
                                )
                        }
                        about
                    }
                    .padding(16)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button("← BACK") { coordinator.goHome() }
                .font(theme.monoFont(size: 10))
                .tracking(1.2)
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(theme.subBg, in: RoundedRectangle(cornerRadius: 14))
            Spacer()
            Text("SETTINGS")
                .font(theme.monoFont(size: 11))
                .tracking(2)
                .foregroundStyle(theme.muted)
            Spacer()
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(theme.headerBg)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(theme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(theme.muted)
            content()
        }
    }

    private var about: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return VStack(alignment: .leading, spacing: 4) {
            Text("ABOUT")
                .font(theme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(theme.muted)
            Text("Mexican Train v\(version)")
                .font(theme.displayFont(size: 16))
                .foregroundStyle(theme.ink)
            Text("A toy companion app. Single device, no accounts, no cloud.")
                .font(theme.monoFont(size: 11))
                .foregroundStyle(theme.muted)
        }
    }
}
