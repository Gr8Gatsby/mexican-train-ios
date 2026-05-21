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
                header
                ScrollView {
                    VStack(spacing: 14) {
                        if let winner = standings.first {
                            winnerCard(winner)
                        }
                        standingsList(standings)
                    }
                    .padding(16)
                }
                actions
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                coordinator.goHome()
            } label: {
                Image(systemName: "chevron.left").foregroundStyle(theme.ink).padding(8)
            }
            .accessibilityLabel("Back")
            Spacer()
            Text("FINAL STOP")
                .font(theme.monoFont(size: 11))
                .tracking(2)
                .foregroundStyle(theme.muted)
            Spacer()
            Color.clear.frame(width: 40)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(theme.headerBg)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
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
        VStack(spacing: 8) {
            Button {
                coordinator.openNewGame()
            } label: {
                Text("NEW GAME")
                    .font(theme.displayFont(size: 14))
                    .tracking(2.5)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(theme.ctaText)
                    .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
            }
            Button {
                coordinator.goHome()
            } label: {
                Text("BACK TO HOME")
                    .font(theme.monoFont(size: 11))
                    .tracking(1.6)
                    .foregroundStyle(theme.muted)
            }
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
                header
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

    private var header: some View {
        HStack {
            Button {
                coordinator.goHome()
            } label: {
                Image(systemName: "chevron.left").foregroundStyle(theme.ink).padding(8)
            }
            Text(game.displayName)
                .font(theme.displayFont(size: 16))
                .foregroundStyle(theme.brand)
            Spacer()
            Button {
                confirmDelete = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(theme.muted)
                    .padding(8)
            }
            .accessibilityLabel("Delete game")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(theme.headerBg)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var footer: some View {
        Button {
            coordinator.goHome()
        } label: {
            Text("DONE")
                .font(theme.displayFont(size: 14))
                .tracking(2.5)
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(theme.ctaText)
                .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
        }
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
