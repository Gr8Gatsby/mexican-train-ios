import SwiftUI
import SwiftData

struct AuditView: View {
    let game: Game
    let player: Player
    let stop: Int

    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context

    @State private var value: String

    init(game: Game, player: Player, stop: Int) {
        self.game = game
        self.player = player
        self.stop = stop
        let existing = Scoring.score(for: player.id, stop: stop, in: game)
        _value = State(initialValue: existing.map { String($0.pips) } ?? "0")
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                hero
                pipEditor
                infoBlock
                Spacer(minLength: 0)
                footer
            }
        }
    }

    private var originalPips: Int {
        Scoring.score(for: player.id, stop: stop, in: game)?.pips ?? 0
    }
    private var numeric: Int { Int(value) ?? 0 }
    private var delta: Int { numeric - originalPips }
    private var newTotal: Int {
        Scoring.total(for: player.id, in: game) - originalPips + numeric
    }
    private var existing: Score? {
        Scoring.score(for: player.id, stop: stop, in: game)
    }

    private var header: some View {
        HStack {
            Button {
                coordinator.openScoreboard(game)
            } label: {
                Text("← BACK")
                    .font(theme.monoFont(size: 10))
                    .tracking(1.2)
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(theme.subBg, in: RoundedRectangle(cornerRadius: 14))
            }
            Spacer()
            Text("AUDIT · STOP \(stop)")
                .font(theme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(theme.muted)
            Spacer()
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.headerBg)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var hero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PLAYER")
                    .font(theme.monoFont(size: 9))
                    .tracking(1.8)
                    .foregroundStyle(theme.muted)
                HStack(spacing: 6) {
                    Text(player.name)
                        .font(theme.displayFont(size: 24))
                        .foregroundStyle(theme.ink)
                    if player.isYou {
                        Text("YOU")
                            .font(theme.monoFont(size: 9))
                            .tracking(1.4)
                            .foregroundStyle(theme.accent)
                    }
                }
                HStack(spacing: 6) {
                    Text("ENGINE")
                        .font(theme.monoFont(size: 9))
                        .tracking(1.4)
                        .foregroundStyle(theme.muted)
                    let n = Scoring.engineTile(stop: stop, rules: game.startingEngine, length: game.lengthStops)
                    DominoGlyph(value: n, width: 26, color: theme.ink)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("NEW TOTAL")
                    .font(theme.monoFont(size: 9))
                    .tracking(1.4)
                    .foregroundStyle(theme.muted)
                Text("\(newTotal)")
                    .font(theme.displayFont(size: 28))
                    .foregroundStyle(theme.brand)
                if delta != 0 {
                    Text("\(delta > 0 ? "+" : "")\(delta) vs recorded")
                        .font(theme.monoFont(size: 10))
                        .foregroundStyle(delta > 0 ? Color(hex: 0xB54B2C) : Color(hex: 0x3A7A3A))
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(theme.subBg)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var pipEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PIP COUNT")
                .font(theme.monoFont(size: 9))
                .tracking(1.8)
                .foregroundStyle(theme.muted)

            HStack(spacing: 10) {
                stepButton(label: "−") { adjust(-1) }
                TextField("0", text: $value)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(theme.displayFont(size: 64))
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity)
                stepButton(label: "+") { adjust(+1) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.border, lineWidth: 1)
            )

            HStack(spacing: 6) {
                ForEach([-10, -5, 5, 10], id: \.self) { d in
                    Button {
                        adjust(d)
                    } label: {
                        Text(d > 0 ? "+\(d)" : "\(d)")
                            .font(theme.monoFont(size: 12))
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let s = existing {
                Text(s.source == .scanned ? "ENTERED VIA CAMERA" : "ENTERED MANUALLY")
                    .font(theme.monoFont(size: 9))
                    .tracking(1.6)
                    .foregroundStyle(theme.muted)
            }
            Text("LAST UPDATED \(existing?.updatedAt.formatted(date: .omitted, time: .shortened) ?? "—")")
                .font(theme.monoFont(size: 9))
                .tracking(1.2)
                .foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 14)
    }

    private func stepButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(theme.displayFont(size: 24))
                .foregroundStyle(theme.ink)
                .frame(width: 48, height: 48)
                .background(theme.subBg, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                        .stroke(theme.border, lineWidth: 1)
                )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                coordinator.openScoreboard(game)
            } label: {
                Text("DISCARD")
                    .font(theme.displayFont(size: 13))
                    .tracking(1.6)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(theme.ink)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                            .stroke(theme.border, lineWidth: 1)
                    )
            }
            Button(action: save) {
                Text("SAVE CORRECTION")
                    .font(theme.displayFont(size: 13))
                    .tracking(1.4)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(theme.ctaText)
                    .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 10)
        .background(theme.subBg)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private func adjust(_ delta: Int) {
        let next = max(0, numeric + delta)
        value = String(next)
    }

    private func save() {
        let n = max(0, numeric)
        do {
            try GamePersistence.recordScore(in: context, game: game, player: player,
                                            stop: stop, pips: n,
                                            source: existing?.source ?? .manual,
                                            captureID: existing?.captureID)
            coordinator.openScoreboard(game)
        } catch {
            coordinator.goHome()
        }
    }
}
