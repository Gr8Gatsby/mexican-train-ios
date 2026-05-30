import SwiftUI
import UIKit

struct EndGameView: View {
    let game: Game
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @State private var confettiID = UUID()

    var body: some View {
        let standings = Scoring.standings(for: game)
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                AppHeaderBar(
                    style: .push,
                    title: game.displayName,
                    subtitle: "FINAL · \(endDateText)",
                    onLeading: { coordinator.goHome() }
                )
                ScrollView {
                    VStack(spacing: 14) {
                        if let winner = standings.first {
                            winnerCard(winner)
                        }
                        standingsList(standings)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                actions(standings: standings)
            }
            ConfettiView()
                .id(confettiID)
                .ignoresSafeArea()
        }
        .onAppear { confettiID = UUID() }
    }

    private var endDateText: String {
        let date = game.finishedAt ?? .now
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private func winnerCard(_ s: Standing) -> some View {
        WinnerCard(name: s.name, total: s.total, gameName: game.displayName,
                   dateText: endDateText, theme: theme)
    }

    private func standingsList(_ standings: [Standing]) -> some View {
        VStack(spacing: 0) {
            ForEach(standings.indices, id: \.self) { i in
                let s = standings[i]
                HStack(spacing: 6) {
                    Text("\(s.place).")
                        .font(theme.displayFont(size: 15))
                        .foregroundStyle(s.place == 1 ? theme.brand : theme.muted)
                        .frame(width: 28, alignment: .leading)
                    Text(s.name)
                        .font(theme.displayFont(size: 16))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    if s.isYou {
                        Text("YOU")
                            .font(theme.monoFont(size: 9))
                            .tracking(1.2)
                            .foregroundStyle(theme.accent)
                    }
                    Spacer()
                    Text("\(s.total)")
                        .font(theme.displayFont(size: 18))
                        .foregroundStyle(s.place == 1 ? theme.brand : theme.ink)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(s.isYou ? theme.youBg : Color.clear)
                if i < standings.count - 1 {
                    Rectangle().fill(theme.borderLight).frame(height: 1)
                }
            }
        }
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func actions(standings: [Standing]) -> some View {
        VStack(spacing: 10) {
            Button { coordinator.openNewGame() } label: { Text("NEW GAME") }
                .appPrimaryStyle()
            if let winner = standings.first,
               let image = renderWinnerImage(name: winner.name, total: winner.total) {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview("\(winner.name) wins!", image: Image(uiImage: image))
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                        Text("SHARE WINNER")
                    }
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
                }
                .accessibilityLabel("Share winner image")
            }
            Button { coordinator.goHome() } label: { Text("BACK TO HOME") }
                .appLinkStyle()
        }
        .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 10)
        .background(theme.subBg)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    @MainActor
    private func renderWinnerImage(name: String, total: Int) -> UIImage? {
        let card = WinnerCard(name: name, total: total, gameName: game.displayName,
                              dateText: endDateText, theme: theme, shareMode: true)
            .frame(width: 600)
        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

struct GameHistoryView: View {
    let game: Game
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                AppHeaderBar(
                    style: .push,
                    title: game.displayName,
                    onLeading: { coordinator.goHome() }
                )
                ScrollView {
                    VStack(spacing: 12) {
                        EndGameView.WinnerHero(game: game)
                        RulesInPlayCard(game: game)
                            .padding(.horizontal, 12)
                        ScoreCardTable(game: game,
                                       onTapScore: { _, _ in },
                                       density: .spacious)
                            .padding(.horizontal, 8)
                    }
                    .padding(.vertical, 12)
                }
                footer
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button { coordinator.goHome() } label: { Text("DONE") }
                .appPrimaryStyle()
            ShareLink(item: GameReport.text(for: game)) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                    Text("SHARE REPORT")
                }
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
            }
            .accessibilityLabel("Share game report")
        }
        .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 10)
        .background(theme.subBg)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }
}

/// Compact summary of every non-default rule that was active when the game
/// was played. Rendered on the past-game view so totals can be interpreted
/// in context (e.g. "12 went out with −5 bonus" or "round 4 capped at 0").
struct RulesInPlayCard: View {
    let game: Game
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RULES IN PLAY")
                .font(theme.monoFont(size: 10))
                .tracking(1.8)
                .foregroundStyle(theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                ruleLine("Game length", value: "\(game.lengthStops) stops")
                ruleLine("Starting engine", value: game.startingEngine.displayName)
                ForEach(houseRulesSummary, id: \.self) { line in
                    ruleLine(line.label, value: line.value, highlight: true)
                }
                if houseRulesSummary.isEmpty {
                    ruleLine("House rules", value: "Defaults")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func ruleLine(_ label: String, value: String, highlight: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(theme.monoFont(size: 11))
                .foregroundStyle(theme.muted)
            Spacer()
            Text(value)
                .font(theme.monoFont(size: 11))
                .fontWeight(highlight ? .semibold : .regular)
                .foregroundStyle(highlight ? theme.brand : theme.ink)
        }
    }

    private struct SummaryLine: Hashable { let label: String; let value: String }

    private var houseRulesSummary: [SummaryLine] {
        var lines: [SummaryLine] = []
        if game.goingOutBonus != .none {
            lines.append(.init(label: "Going-out bonus", value: game.goingOutBonus.displayName))
        }
        if game.doublesPenaltyPips > 0 {
            lines.append(.init(label: "Doubles penalty", value: "+\(game.doublesPenaltyPips)"))
        }
        if game.doubleBlankPenaltyPips > 0 {
            lines.append(.init(label: "Double-blank penalty", value: "+\(game.doubleBlankPenaltyPips)"))
        }
        if game.doublesCountDouble {
            lines.append(.init(label: "Doubles count double", value: "On"))
        }
        if game.anyBlankPenaltyPips > 0 {
            lines.append(.init(label: "Any-blank penalty", value: "+\(game.anyBlankPenaltyPips) each"))
        }
        if let d = game.drawCountOverride {
            lines.append(.init(label: "Draw count", value: "\(d)"))
        }
        if game.blockedRoundCapEnabled {
            lines.append(.init(label: "Blocked-round cap", value: "On"))
        }
        return lines
    }
}

extension EndGameView {
    /// Re-uses the winner-card visual for the history view.
    struct WinnerHero: View {
        let game: Game
        @Environment(\.theme) private var theme
        var body: some View {
            let standings = Scoring.standings(for: game)
            if let s = standings.first {
                VStack(spacing: 4) {
                    Text("WINNER")
                        .font(theme.monoFont(size: 10))
                        .tracking(2)
                        .foregroundStyle(theme.muted)
                    Text(s.name)
                        .font(theme.displayFont(size: 28))
                        .foregroundStyle(theme.brand)
                    Text("\(s.total) pips · \(game.players.count) players")
                        .font(theme.monoFont(size: 11))
                        .foregroundStyle(theme.muted)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.border, lineWidth: 1)
                )
                .padding(.horizontal, 12)
            }
        }
    }
}
