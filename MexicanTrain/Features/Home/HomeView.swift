import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @Query(sort: \JoinedGameRecord.lastUpdatedAt, order: .reverse) private var joinedGames: [JoinedGameRecord]
    @State private var pendingDelete: Game?
    @State private var pendingDeleteJoined: JoinedGameRecord?

    private var inProgress: [Game] { games.filter { !$0.isFinished } }
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
        .onAppear {
            if coordinator.netSession.role == .idle {
                coordinator.netSession.startBrowsing()
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
        .alert(
            "Delete this joined game?",
            isPresented: Binding(
                get: { pendingDeleteJoined != nil },
                set: { if !$0 { pendingDeleteJoined = nil } }
            ),
            presenting: pendingDeleteJoined
        ) { record in
            Button("Delete", role: .destructive) {
                modelContext.delete(record)
                try? modelContext.save()
                pendingDeleteJoined = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteJoined = nil }
        } message: { _ in
            Text("This removes the local record of this joined game.")
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
        if games.isEmpty && joinedGames.isEmpty && settings.activeJoinPlayerID == nil {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    rejoinBanner
                    if !inProgress.isEmpty {
                        sectionLabel("IN PROGRESS")
                        ForEach(inProgress) { g in
                            SwipeToDelete(
                                onDelete: { pendingDelete = g },
                                accessibilityLabel: "Delete \(g.displayName)"
                            ) {
                                InProgressCard(game: g)
                                    .onTapGesture { coordinator.openScoreboard(g) }
                            }
                        }
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
                            SwipeToDelete(
                                onDelete: { pendingDeleteJoined = record },
                                accessibilityLabel: "Delete \(record.gameName)"
                            ) {
                                JoinedGameRow(record: record, onOpen: {
                                    if !record.isFinished, let snap = record.snapshot, !snap.roomCode.isEmpty {
                                        coordinator.openJoinSheet(code: snap.roomCode)
                                    } else {
                                        coordinator.openJoinedGameDetail(record.gameID)
                                    }
                                }, onDelete: {
                                    pendingDeleteJoined = record
                                })
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
            rejoinBanner
                .padding(.horizontal, 16)
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

    @ViewBuilder
    private var rejoinBanner: some View {
        if let playerName = settings.activeJoinPlayerName,
           let roomCode = settings.activeJoinRoomCode,
           coordinator.netSession.availableHosts.contains(where: { $0.roomCode == roomCode }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rejoin as \(playerName)?")
                            .font(theme.displayFont(size: 16))
                            .foregroundStyle(theme.ink)
                        Text("CODE \(roomCode)")
                            .font(theme.monoFont(size: 11))
                            .tracking(1.4)
                            .foregroundStyle(theme.accent)
                    }
                    Spacer()
                    Button {
                        coordinator.openJoinSheet(code: roomCode)
                    } label: {
                        Text("REJOIN")
                            .font(theme.monoFont(size: 12))
                            .fontWeight(.semibold)
                            .tracking(1.4)
                            .foregroundStyle(theme.ctaText)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                    }
                }
                Button {
                    settings.clearActiveJoin()
                } label: {
                    Text("Dismiss")
                        .font(theme.monoFont(size: 11))
                        .foregroundStyle(theme.muted)
                }
            }
            .padding(14)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.brand.opacity(0.5), lineWidth: 1)
            )
        }
    }

    private var cta: some View {
        let hosts = coordinator.netSession.availableHosts
        let nearbyHost = hosts.first
        // When the Rejoin banner already promotes this same nearby host,
        // suppress the host-rich variant of the bottom tile so the user
        // sees a single bright rejoin affordance instead of two competing
        // ones. The tile reverts to the neutral QR "JOIN GAME" path for
        // joining a different game.
        let rejoinBannerShownFor: String? = {
            guard let code = settings.activeJoinRoomCode,
                  hosts.contains(where: { $0.roomCode == code }) else { return nil }
            return code
        }()
        let promoteNearby = nearbyHost != nil && nearbyHost?.roomCode != rejoinBannerShownFor
        return HStack(spacing: 0) {
            // Left: Join
            Button {
                if promoteNearby, let host = nearbyHost {
                    coordinator.openJoinSheet(code: host.roomCode)
                } else {
                    coordinator.openJoinSheet()
                }
            } label: {
                VStack(spacing: 8) {
                    if promoteNearby, let host = nearbyHost {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                        Text(host.displayLabel)
                            .font(theme.displayFont(size: 14))
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                        Text("\(host.playerCount) players")
                            .font(theme.monoFont(size: 10))
                            .foregroundStyle(theme.muted)
                        Text("JOIN")
                            .font(theme.monoFont(size: 11))
                            .fontWeight(.bold)
                            .tracking(2)
                            .foregroundStyle(theme.brand)
                    } else {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(theme.muted)
                        Text("JOIN")
                            .font(theme.monoFont(size: 11))
                            .fontWeight(.bold)
                            .tracking(2)
                            .foregroundStyle(theme.ink)
                        Text("GAME")
                            .font(theme.monoFont(size: 11))
                            .fontWeight(.bold)
                            .tracking(2)
                            .foregroundStyle(theme.ink)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(promoteNearby ? theme.cardBg : theme.subBg)
                .overlay(
                    Rectangle().fill(theme.border).frame(width: 0.5),
                    alignment: .trailing
                )
            }
            .buttonStyle(.plain)

            // Right: New Game
            Button {
                coordinator.openNewGame()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(theme.ctaText)
                    Text("NEW")
                        .font(theme.monoFont(size: 11))
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(theme.ctaText)
                    Text("GAME")
                        .font(theme.monoFont(size: 11))
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(theme.ctaText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.cta)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 110)
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
    var onDelete: (() -> Void)? = nil
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
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.muted)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Delete \(record.gameName)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
