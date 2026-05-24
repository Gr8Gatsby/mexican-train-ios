import SwiftUI
import SwiftData
import UIKit

struct ScoreboardView: View {
    let game: Game
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var menuOpen = false
    @State private var renamingTo = ""
    @State private var renaming = false
    @State private var confirmDelete = false
    @State private var toast: String?
    @State private var overrideTarget: OverrideTarget?
    @State private var overrideConfirm: OverrideTarget?
    @State private var pendingClaim: PlayerClaim?
    @State private var showAssignDialog = false

    struct OverrideTarget: Identifiable, Equatable {
        let player: Player
        let stop: Int
        var id: String { "\(player.id)-\(stop)" }
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                engineStrip
                if let _ = game.players.first(where: { $0.isYou }) { youStrip }
                tableArea
                cta
            }
        }
        .alert("Rename game", isPresented: $renaming) {
            TextField("Name", text: $renamingTo)
            Button("Save") {
                if !renamingTo.isEmpty {
                    try? GamePersistence.renameGame(game, to: renamingTo, in: context)
                }
            }
            Button("Cancel", role: .cancel) {}
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
        .overlay(alignment: .bottom) {
            if let t = toast {
                Text("✓ \(t)")
                    .font(theme.monoFont(size: 11))
                    .tracking(1.4)
                    .foregroundStyle(theme.bg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(theme.ink, in: Capsule())
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .onChange(of: game.currentStopIndex) { _, _ in
            // If we just advanced past the final stop, route to end-of-game.
            if game.isFinished {
                coordinator.openEndGame(game)
            }
        }
        .hostBroadcaster(game: game)
        .confirmationDialog(
            overrideConfirm.map { "Submit on behalf of \($0.player.name)?" } ?? "",
            isPresented: Binding(
                get: { overrideConfirm != nil },
                set: { if !$0 { overrideConfirm = nil } }
            ),
            presenting: overrideConfirm
        ) { target in
            Button("Open Camera as \(target.player.name)") {
                coordinator.openCamera(
                    game: game, player: target.player, stop: target.stop,
                    topBarSubject: "AS \(target.player.name.uppercased()) · STOP \(target.stop)/\(game.lengthStops)"
                )
                overrideConfirm = nil
            }
            Button("Enter Manually") {
                coordinator.openManualEntry(
                    game: game, player: target.player, stop: target.stop,
                    topBarSubject: "AS \(target.player.name.uppercased()) · STOP \(target.stop)/\(game.lengthStops)"
                )
                overrideConfirm = nil
            }
            Button("Cancel", role: .cancel) { overrideConfirm = nil }
        } message: { target in
            Text("Submitting on behalf is recorded in the audit history. \(target.player.name) can still submit their own score from their phone and it will take priority.")
        }
        .confirmationDialog(
            pendingClaim.map { "\($0.displayName) wants to join" } ?? "",
            isPresented: $showAssignDialog,
            presenting: pendingClaim
        ) { claim in
            ForEach(game.sortedPlayers) { player in
                Button("Assign to \(player.name)") {
                    assignClaim(claim, to: player)
                    pendingClaim = nil
                }
            }
            Button("Reject", role: .destructive) {
                pendingClaim = nil
            }
            Button("Cancel", role: .cancel) {
                pendingClaim = nil
            }
        } message: { _ in
            Text("Assign to an existing player or reject")
        }
        .onAppear {
            coordinator.netSession.onScoreSubmissionReceived = { submission in
                Task { @MainActor in
                    handleIncomingSubmission(submission)
                }
            }
            coordinator.netSession.onClaimReceived = { claim in
                Task { @MainActor in
                    handleIncomingClaim(claim)
                }
            }
        }
        .onDisappear {
            coordinator.netSession.onScoreSubmissionReceived = nil
            coordinator.netSession.onClaimReceived = nil
        }
    }

    /// Handle a `PlayerClaim` from a joiner while the game is already in
    /// progress. If scoring hasn't started yet, new UUIDs become new player
    /// slots. Once scores exist, new players must be assigned to an existing
    /// seat by the conductor (to prevent strangers from joining mid-game).
    private func handleIncomingClaim(_ claim: PlayerClaim) {
        // Existing slot: update name + photo.
        if let existing = game.players.first(where: { $0.id == claim.playerID }) {
            existing.name = claim.displayName
            if let photo = claim.photoJPEG, let img = UIImage(data: photo),
               let filename = try? coordinator.photoStore.save(
                image: img, gameID: game.id, captureID: existing.id) {
                existing.avatarFilename = filename
            }
            try? context.save()
            return
        }

        // If scores exist, block auto-add and ask the conductor to assign.
        if !game.scores.isEmpty {
            pendingClaim = claim
            showAssignDialog = true
            return
        }

        // No scores yet: auto-add as a fresh player, capped at the 8-player limit.
        guard game.players.count < 8 else { return }
        let seat = (game.sortedPlayers.last?.seat ?? -1) + 1
        let newPlayer = Player(id: claim.playerID, name: claim.displayName, seat: seat)
        newPlayer.game = game
        context.insert(newPlayer)
        if let photo = claim.photoJPEG, let img = UIImage(data: photo),
           let filename = try? coordinator.photoStore.save(
            image: img, gameID: game.id, captureID: newPlayer.id) {
            newPlayer.avatarFilename = filename
        }
        // Prior stops: excluded 0s so isStopComplete stays true (we already
        // advanced past them) and the late joiner doesn't appear to lead
        // with a 0 total. They start scoring from the current stop forward.
        let firstActiveStop = max(1, game.currentStopIndex)
        if firstActiveStop > 1 {
            for s in 1..<firstActiveStop {
                let score = Score(playerID: newPlayer.id, stopIndex: s, pips: 0,
                                  source: .manual, submittedBy: .conductor)
                score.excluded = true
                score.game = game
                context.insert(score)
            }
        }
        try? context.save()
        withAnimation(.easeOut(duration: 0.25)) {
            toast = "\(newPlayer.name) joined as a player"
        }
        scheduleToastClear()
    }

    /// Assign a pending claim to an existing player slot, updating their
    /// name and avatar to match the joiner's identity.
    private func assignClaim(_ claim: PlayerClaim, to player: Player) {
        let previousName = player.name
        player.name = claim.displayName
        if let photo = claim.photoJPEG, let img = UIImage(data: photo),
           let filename = try? coordinator.photoStore.save(
            image: img, gameID: game.id, captureID: player.id) {
            player.avatarFilename = filename
        }
        try? context.save()
        withAnimation(.easeOut(duration: 0.25)) {
            toast = "\(claim.displayName) assigned to \(previousName)"
        }
        scheduleToastClear()
    }

    private func handleIncomingSubmission(_ submission: ScoreSubmission) {
        let photoStore = coordinator.photoStore
        let thumb = submission.thumbJPEG
        let gameID = game.id
        do {
            let outcome = try GamePersistence.handleScoreSubmission(
                in: context, game: game, submission: submission,
                saveCapture: { captureID in
                    guard let data = thumb, let img = UIImage(data: data) else { return }
                    try photoStore.save(image: img, gameID: gameID, captureID: captureID)
                }
            )
            switch outcome {
            case .created, .overrodeConductor:
                if let p = game.players.first(where: { $0.id == submission.playerID }) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        toast = "\(p.name) submitted \(submission.pips)"
                    }
                    scheduleToastClear()
                }
            case .ignored, .rejected:
                break
            }
        } catch {
            // Surface persistence errors silently for v1; the joiner sees no toast.
        }
    }

    private var header: some View {
        AppHeaderBar(
            style: .push,
            title: game.displayName,
            onLeading: { coordinator.goHome() }
        ) {
            Menu {
                Button("Share with table") {
                    coordinator.openShareSheet(for: game)
                }
                Button("Rename game") {
                    renamingTo = game.displayName
                    renaming = true
                }
                Button("End game early") {
                    try? GamePersistence.endGameEarly(game, in: context)
                }
                Button("Delete game", role: .destructive) {
                    confirmDelete = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Game menu")
        }
    }

    private var engineStrip: some View {
        let n = Scoring.engineTile(stop: min(game.currentStopIndex, game.lengthStops),
                                   rules: game.startingEngine,
                                   length: game.lengthStops)
        return HStack(spacing: 8) {
            Text("ENGINE")
                .font(theme.monoFont(size: 9))
                .tracking(1.4)
                .foregroundStyle(theme.muted)
            DominoGlyph(value: n, width: 32, color: theme.ink)
            Spacer()
            Text("● \(game.players.count) ABOARD")
                .font(theme.monoFont(size: 9))
                .tracking(1.4)
                .foregroundStyle(theme.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(theme.subBg)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var youStrip: some View {
        let standings = Scoring.standings(for: game)
        let you = standings.first(where: { $0.isYou })
        let leader = standings.first
        let behind = (you?.total ?? 0) - (leader?.total ?? 0)
        return VStack(spacing: 0) {
            if let you {
                HStack(alignment: .center, spacing: 10) {
                    Text(ordinal(you.place))
                        .font(theme.displayFont(size: 28))
                        .foregroundStyle(you.place == 1 ? theme.brand : theme.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YOU · \(you.name)")
                            .font(theme.monoFont(size: 9))
                            .tracking(1.6)
                            .foregroundStyle(theme.muted)
                        Group {
                            if behind == 0 {
                                Text("LEADING THE TRAIN ♔")
                                    .foregroundStyle(theme.brand)
                            } else if let leader {
                                Text("\(behind) pts behind \(leader.name)")
                            }
                        }
                        .font(theme.monoFont(size: 10))
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.ink)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("YOUR TOTAL")
                            .font(theme.monoFont(size: 9))
                            .tracking(1.6)
                            .foregroundStyle(theme.muted)
                        Text("\(you.total)")
                            .font(theme.displayFont(size: 22))
                            .foregroundStyle(theme.ink)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(theme.youBg)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
            }
        }
    }

    private var tableArea: some View {
        ScrollView {
            VStack(spacing: 8) {
                ScoreCardTable(
                    game: game,
                    onTapScore: { player, stop in
                        coordinator.openAudit(game: game, player: player, stop: stop)
                    },
                    onTapAddOverride: { player, stop in
                        // First override teaches the affordance — flip the
                        // pulse off so it doesn't keep grabbing attention.
                        if !settings.hasUsedConductorOverride {
                            settings.hasUsedConductorOverride = true
                        }
                        overrideConfirm = OverrideTarget(player: player, stop: stop)
                    },
                    pulseOverride: !settings.hasUsedConductorOverride
                )
                legend
                if game.currentStopIndex > 1 {
                    PhotoGalleryStrip(game: game, stop: game.currentStopIndex - 1)
                }
            }
            .padding(8)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("♔ LEADER  ▸ YOU")
                Spacer()
                Text("+ SUBMIT FOR PLAYER")
            }
            HStack {
                Spacer()
                Text("TAP A SCORE TO AUDIT")
            }
        }
        .font(theme.monoFont(size: 9))
        .tracking(1.2)
        .foregroundStyle(theme.muted)
        .padding(.horizontal, 6)
    }

    private var cta: some View {
        let stop = game.currentStopIndex
        let nextPlayer = Scoring.nextUnenteredPlayer(stop: stop, in: game)
        let allDone = nextPlayer == nil
        return VStack(spacing: 6) {
            Button {
                if allDone {
                    try? GamePersistence.maybeAdvanceStop(in: context, game: game)
                    withAnimation(.easeOut(duration: 0.25)) {
                        toast = (game.currentStopIndex > stop) ? "Stop \(stop) closed" : "Game complete"
                    }
                    scheduleToastClear()
                } else if let p = nextPlayer {
                    coordinator.openCamera(game: game, player: p, stop: stop)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: allDone ? "arrow.right.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .accessibilityHidden(true)
                    Text(allDone
                         ? (stop >= game.lengthStops ? "FINISH GAME" : "ADVANCE TO STOP \(stop+1)")
                         : "ADD SCORE")
                        .font(theme.displayFont(size: 14))
                        .tracking(2.5)
                    if !allDone {
                        Text("STOP \(stop)")
                            .font(theme.monoFont(size: 10))
                            .tracking(1.2)
                            .foregroundStyle(theme.ctaText.opacity(0.7))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(theme.ctaText.opacity(0.12), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(theme.ctaText)
                .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
            }
            .accessibilityLabel(
                allDone
                ? (stop >= game.lengthStops ? "Finish game" : "Advance to stop \(stop + 1)")
                : "Add score for \(nextPlayer?.name ?? "next player"), stop \(stop)"
            )
            if let p = nextPlayer {
                Text("Next: \(p.name)")
                    .font(theme.monoFont(size: 9))
                    .tracking(1.4)
                    .foregroundStyle(theme.muted)
            }
            broadcastStrip
        }
        .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 8)
        .background(theme.subBg)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    /// Bottom-of-screen broadcast status. Replaces the old header-side pill
    /// so the game title can sit centered. Tappable target for the share
    /// sheet; visual treatment intensifies once a peer is actually connected.
    private var broadcastStrip: some View {
        let session = coordinator.netSession
        let isHosting = session.role == .host
        let peers = session.connectedPeerCount
        let active = peers > 0
        return Button {
            coordinator.openShareSheet(for: game)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: active ? "person.fill" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                if active {
                    Text("\(peers) joined")
                        .font(theme.monoFont(size: 11))
                        .fontWeight(.semibold)
                        .tracking(1.2)
                } else {
                    Text(isHosting ? "Code \(session.roomCode)" : "Share game")
                        .font(theme.monoFont(size: 11))
                        .fontWeight(.semibold)
                        .tracking(1.2)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.6)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(active ? theme.accent : theme.muted)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                Capsule().fill(active ? theme.accent.opacity(0.12) : Color.clear)
            )
            .overlay(
                Capsule().stroke(active ? theme.accent.opacity(0.35) : theme.borderLight,
                                 lineWidth: 1)
            )
        }
        .accessibilityLabel(isHosting
                            ? "Room code \(session.roomCode). \(peers) joined. Tap to share."
                            : "Share game")
    }

    private func scheduleToastClear() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { toast = nil }
        }
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: "1st"
        case 2: "2nd"
        case 3: "3rd"
        default: "\(n)th"
        }
    }
}
