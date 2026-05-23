import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @Query(sort: \JoinedGameRecord.lastUpdatedAt, order: .reverse) private var joinedGames: [JoinedGameRecord]
    @State private var pendingDelete: Game?

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
        .alert(
            "Delete this game?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { game in
            Button("Delete", role: .destructive) {
                try? GamePersistence.delete(game: game, in: modelContext, photoStore: coordinator.photoStore)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("All scores and photos for this game will be removed.")
        }
    }

    private var header: some View {
        HStack {
            Text("MEX·TRAIN")
                .font(theme.displayFont(size: 24))
                .tracking(2)
                .foregroundStyle(theme.brand)
            Spacer()
            Button {
                coordinator.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if games.isEmpty && joinedGames.isEmpty {
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
                            SwipeToDelete(
                                onDelete: { pendingDelete = g },
                                accessibilityLabel: "Delete \(g.displayName)"
                            ) {
                                HistoryRow(game: g) {
                                    coordinator.openGameHistory(g)
                                }
                            }
                        }
                    }
                    if !joinedGames.isEmpty {
                        sectionLabel("JOINED")
                        ForEach(joinedGames) { record in
                            JoinedGameRow(record: record) {
                                coordinator.openJoinedGameDetail(record.gameID)
                            }
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
                .font(theme.displayFont(size: 28, relativeTo: .title))
                .foregroundStyle(theme.ink)
            Text("All aboard. Tap below to start your first game.")
                .font(theme.monoFont(size: 12, relativeTo: .footnote))
                .tracking(1.4)
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .combine)
    }

    private var cta: some View {
        VStack(spacing: 10) {
            Button {
                coordinator.openNewGame()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .accessibilityHidden(true)
                    Text("NEW GAME")
                }
            }
            .appPrimaryStyle()
            Button {
                coordinator.openJoinSheet()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 14, weight: .semibold))
                    Text("JOIN NEARBY GAME")
                }
            }
            .appSecondaryStyle()
            .accessibilityLabel("Join a nearby game")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, 10)
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

private struct JoinedGameRow: View {
    let record: JoinedGameRecord
    let onOpen: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.hostName)
                            .font(theme.monoFont(size: 13))
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if usesFallbackName {
                                Text(timeText)
                            } else {
                                Text(record.gameName)
                                Text("·")
                                Text(dateText)
                            }
                            Text("·")
                            Text(record.isFinished ? "final" : "in progress")
                                .foregroundStyle(record.isFinished ? theme.muted : theme.accent)
                        }
                        .font(theme.monoFont(size: 10))
                        .tracking(0.8)
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.muted)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let snap = record.snapshot {
                ShareLink(item: GameReport.text(snapshot: snap)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.muted)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Share \(record.gameName) report")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Slightly lighter background so JOINED rows visually sit under
        // the user's own IN PROGRESS / HISTORY entries.
        .background(theme.subBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.borderLight, lineWidth: 1)
        )
    }

    /// `gameName` falls back to `Game.displayName` (a formatted date) when
    /// the host never set a name. In that case we'd rather show the join
    /// time as the distinguishing piece of metadata.
    private var usesFallbackName: Bool {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.date(from: record.gameName) != nil
    }

    private var dateText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: record.lastUpdatedAt)
    }

    private var timeText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: record.lastUpdatedAt)
    }
}

private struct HistoryRow: View {
    let game: Game
    let onOpen: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let standings = Scoring.standings(for: game)
        let winner = standings.first
        HStack(spacing: 0) {
            Button(action: onOpen) {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ShareLink(item: GameReport.text(for: game)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.brand)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Share \(game.displayName) report")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.borderLight, lineWidth: 1)
        )
    }
}
