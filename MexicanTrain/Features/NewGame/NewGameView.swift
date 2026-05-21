import SwiftUI
import SwiftData

struct NewGameView: View {
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @State private var length: Int = 13
    @State private var engine: StartingEngine = .traditional
    @State private var playerNames: [String] = ["", ""]
    @State private var youIndex: Int? = nil
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("GAME LENGTH") { lengthPicker }
                        section("STARTING ENGINE") { enginePicker }
                        section("PLAYERS") { playerList }
                    }
                    .padding(16)
                }
                footer
            }
        }
        .onAppear {
            length = settings.defaultLengthStops
            engine = settings.lastStartingEngine
            if playerNames.allSatisfy(\.isEmpty), !settings.defaultYouName.isEmpty {
                playerNames[0] = settings.defaultYouName
                youIndex = 0
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
            Text("NEW GAME")
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

    private var lengthPicker: some View {
        HStack(spacing: 8) {
            ForEach([7, 10, 13], id: \.self) { n in
                Button { length = n } label: {
                    Text("\(n)")
                        .font(theme.displayFont(size: 22))
                        .foregroundStyle(length == n ? theme.ctaText : theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(length == n ? theme.cta : theme.cardBg,
                                    in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                                .stroke(theme.border, lineWidth: 1)
                        )
                }
            }
        }
    }

    private var enginePicker: some View {
        VStack(spacing: 6) {
            ForEach(StartingEngine.allCases) { option in
                Button { engine = option } label: {
                    HStack(alignment: .top) {
                        Image(systemName: engine == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(engine == option ? theme.brand : theme.muted)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.displayName)
                                .font(theme.displayFont(size: 16))
                                .foregroundStyle(theme.ink)
                            Text(option.description)
                                .font(theme.monoFont(size: 10))
                                .tracking(1)
                                .foregroundStyle(theme.muted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(engine == option ? theme.brand : theme.borderLight,
                                    lineWidth: engine == option ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var playerList: some View {
        VStack(spacing: 6) {
            ForEach(playerNames.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Button {
                        youIndex = (youIndex == i) ? nil : i
                    } label: {
                        Image(systemName: youIndex == i ? "person.fill" : "person")
                            .foregroundStyle(youIndex == i ? theme.accent : theme.muted)
                    }
                    .accessibilityLabel(youIndex == i ? "You" : "Mark as you")

                    TextField("Player \(i+1)", text: $playerNames[i])
                        .textInputAutocapitalization(.words)
                        .padding(10)
                        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(theme.borderLight, lineWidth: 1)
                        )

                    if playerNames.count > 1 {
                        Button {
                            playerNames.remove(at: i)
                            if let y = youIndex {
                                if y == i { youIndex = nil }
                                else if y > i { youIndex = y - 1 }
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(theme.muted)
                        }
                        .accessibilityLabel("Remove player")
                    }
                }
            }
            if playerNames.count < 8 {
                Button {
                    playerNames.append("")
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add player")
                    }
                    .font(theme.monoFont(size: 12))
                    .tracking(1)
                    .foregroundStyle(theme.brand)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(theme.subBg, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if let error {
                Text(error)
                    .font(theme.monoFont(size: 10))
                    .foregroundStyle(theme.brand)
            }
            Button(action: start) {
                Text("START GAME")
                    .font(theme.displayFont(size: 14))
                    .tracking(2.5)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(theme.ctaText)
                    .background(canStart ? theme.cta : theme.muted,
                                in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
            }
            .disabled(!canStart || saving)
            .opacity(canStart ? 1 : 0.55)
        }
        .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 10)
        .background(theme.subBg)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var canStart: Bool { validate() == nil }

    private func validate() -> String? {
        let trimmed = playerNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if trimmed.contains(where: \.isEmpty) { return "Every player needs a name." }
        let lower = trimmed.map { $0.lowercased() }
        if Set(lower).count != lower.count { return "Names must be unique." }
        if trimmed.count < 1 || trimmed.count > 8 { return "1 to 8 players." }
        return nil
    }

    private func start() {
        if let msg = validate() { error = msg; return }
        saving = true
        defer { saving = false }
        do {
            let game = try GamePersistence.createGame(
                in: context,
                length: length,
                startingEngine: engine,
                playerNames: playerNames,
                youIndex: youIndex
            )
            settings.defaultLengthStops = length
            settings.lastStartingEngine = engine
            if let y = youIndex {
                settings.defaultYouName = playerNames[y]
            }
            coordinator.openScoreboard(game)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
