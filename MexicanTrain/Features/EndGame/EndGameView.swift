import SwiftUI

struct EndGameView: View {
    let game: Game
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator

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
                actions
            }
        }
    }

    private var endDateText: String {
        let date = game.finishedAt ?? .now
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private func winnerCard(_ s: Standing) -> some View {
        VStack(spacing: 6) {
            Text("ALL ABOARD · WINNER")
                .font(theme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(theme.muted)
            Text("♔")
                .font(.system(size: 34))
                .foregroundStyle(theme.brand)
            Text(s.name)
                .font(theme.displayFont(size: 36))
                .foregroundStyle(theme.brand)
            Text("\(s.total) pips")
                .font(theme.monoFont(size: 13))
                .foregroundStyle(theme.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(theme.brand, lineWidth: 1.5)
        )
    }

    private func standingsList(_ standings: [Standing]) -> some View {
        VStack(spacing: 0) {
            ForEach(standings.indices, id: \.self) { i in
                let s = standings[i]
                HStack {
                    Text("\(s.place).")
                        .font(theme.displayFont(size: 18))
                        .foregroundStyle(theme.ink)
                        .frame(width: 36, alignment: .leading)
                    Text(s.name)
                        .font(theme.displayFont(size: 18))
                        .foregroundStyle(theme.ink)
                    if s.isYou {
                        Text("YOU")
                            .font(theme.monoFont(size: 9))
                            .tracking(1.2)
                            .foregroundStyle(theme.accent)
                    }
                    Spacer()
                    Text("\(s.total)")
                        .font(theme.displayFont(size: 22))
                        .foregroundStyle(theme.ink)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
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

    private var actions: some View {
        VStack(spacing: 10) {
            Button { coordinator.openNewGame() } label: { Text("NEW GAME") }
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
            Button { coordinator.goHome() } label: { Text("BACK TO HOME") }
                .appLinkStyle()
        }
        .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 10)
        .background(theme.subBg)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }
}

struct GameHistoryView: View {
    let game: Game
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @State private var confirmDelete = false

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                AppHeaderBar(
                    style: .push,
                    title: game.displayName,
                    onLeading: { coordinator.goHome() }
                ) {
                    ShareLink(item: GameReport.text(for: game)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Share game report")
                    Button {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Delete game")
                }
                ScrollView {
                    VStack(spacing: 12) {
                        EndGameView.WinnerHero(game: game)
                        ScoreCardTable(game: game) { _, _ in }
                            .padding(.horizontal, 8)
                    }
                    .padding(.vertical, 12)
                }
                footer
            }
        }
        .alert("Delete this game?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                try? GamePersistence.delete(game: game, in: context, photoStore: coordinator.photoStore)
                coordinator.goHome()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All scores and photos for this game will be removed.")
        }
    }

    private var footer: some View {
        Button { coordinator.goHome() } label: { Text("DONE") }
            .appPrimaryStyle()
            .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 10)
            .background(theme.subBg)
            .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
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
