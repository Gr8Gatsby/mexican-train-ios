import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]

    private var inProgress: Game? { games.first(where: { !$0.isFinished }) }
    private var finished: [Game] { games.filter { $0.isFinished } }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                content
                cta
            }
        }
    }

    private var header: some View {
        HStack {
            Text("MEX·TRAIN")
                .font(theme.displayFont(size: 22))
                .tracking(2)
                .foregroundStyle(theme.brand)
            Spacer()
            Button {
                coordinator.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.muted)
                    .padding(8)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if games.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let g = inProgress {
                        sectionLabel("IN PROGRESS")
                        InProgressCard(game: g)
                            .onTapGesture { coordinator.openScoreboard(g) }
                    }
                    if !finished.isEmpty {
                        sectionLabel("HISTORY")
                        ForEach(finished) { g in
                            HistoryRow(game: g)
                                .onTapGesture { coordinator.openGameHistory(g) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s)
            .font(theme.monoFont(size: 10))
            .tracking(2)
            .foregroundStyle(theme.muted)
            .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("No games yet")
                .font(theme.displayFont(size: 28))
                .foregroundStyle(theme.ink)
            Text("All aboard. Tap below to start your first game.")
                .font(theme.monoFont(size: 12))
                .tracking(1.4)
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var cta: some View {
        VStack(spacing: 8) {
            Button {
                coordinator.openNewGame()
            } label: {
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
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .padding(.top, 8)
        .background(theme.subBg)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }
}

private struct InProgressCard: View {
    let game: Game
    @Environment(\.theme) private var theme

    var body: some View {
        let standings = Scoring.standings(for: game)
        let leader = standings.first
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(game.displayName)
                    .font(theme.displayFont(size: 18))
                    .foregroundStyle(theme.ink)
                Spacer()
                Text("STOP \(game.currentStopIndex)/\(game.lengthStops)")
                    .font(theme.monoFont(size: 10))
                    .tracking(1.5)
                    .foregroundStyle(theme.accent)
            }
            HStack(spacing: 6) {
                Text("\(game.players.count) aboard")
                    .font(theme.monoFont(size: 10))
                    .tracking(1.2)
                    .foregroundStyle(theme.muted)
                if let l = leader {
                    Text("·")
                        .foregroundStyle(theme.muted)
                    Text("\(l.name) leads \(l.total)")
                        .font(theme.monoFont(size: 10))
                        .tracking(1.2)
                        .foregroundStyle(theme.muted)
                }
                Spacer()
                Text("Resume ›")
                    .font(theme.monoFont(size: 11))
                    .tracking(1.4)
                    .foregroundStyle(theme.brand)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.border, lineWidth: 1)
        )
    }
}

private struct HistoryRow: View {
    let game: Game
    @Environment(\.theme) private var theme

    var body: some View {
        let standings = Scoring.standings(for: game)
        let winner = standings.first
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(game.displayName)
                    .font(theme.displayFont(size: 16))
                    .foregroundStyle(theme.ink)
                HStack(spacing: 4) {
                    Text("\(game.players.count) players")
                    Text("·")
                    if let w = winner {
                        Text("Winner: \(w.name) (\(w.total))")
                    }
                }
                .font(theme.monoFont(size: 10))
                .tracking(1)
                .foregroundStyle(theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.borderLight, lineWidth: 1)
        )
    }
}
