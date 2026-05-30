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
    @State private var showRemovePlayerDialog = false
    @State private var undoableScore: Score?
    @State private var showEditRules = false
    @State private var selectedPlayer: Player?
    @State private var showInstructions = false
    @State private var didShowBroadcastCue = false
    @State private var broadcastCue: String?
    @State private var claimSecondsLeft: Int?
    /// Set to the just-completed stop when the conductor taps ADVANCE and
    /// the blocked-round-cap rule applies. Drives the confirmation dialog.
    @State private var blockedCapPrompt: Int?
    /// Set to the just-completed stop when the conductor taps ADVANCE and
    /// the double-blank penalty rule is active. Drives the "Who had the 0|0?"
    /// dialog, which the user resolves before any blocked-cap check.
    @State private var doubleBlankPrompt: Int?

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
        .sheet(isPresented: $showEditRules) {
            EditRulesSheet(game: game)
        }
        .sheet(item: $selectedPlayer) { player in
            PlayerDetailSheet(game: game, player: player)
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
        .overlay(alignment: .top) {
            if let secs = claimSecondsLeft, pendingClaim != nil {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Auto-dismiss in \(secs)s")
                        .font(theme.monoFont(size: 11))
                        .tracking(1.2)
                }
                .foregroundStyle(theme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.cardBg, in: Capsule())
                .overlay(Capsule().stroke(theme.borderLight, lineWidth: 1))
                .padding(.top, 70)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel("Claim dialog auto-dismisses in \(secs) seconds")
            }
        }
        .overlay(alignment: .bottom) {
            if let c = broadcastCue {
                Button {
                    coordinator.openShareSheet(for: game)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 12, weight: .semibold))
                        Text(c)
                            .font(theme.monoFont(size: 11))
                            .tracking(1.4)
                    }
                    .foregroundStyle(theme.bg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(theme.accent, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityHint("Tap to open share sheet")
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
            // One-shot cue so the conductor (and anyone glancing at the
            // phone) sees that the table can still join via the room code,
            // even though it's now a small badge in the header.
            let session = coordinator.netSession
            if !didShowBroadcastCue,
               session.role == .host,
               !session.roomCode.isEmpty {
                didShowBroadcastCue = true
                withAnimation(.easeOut(duration: 0.3)) {
                    // Room code already shows in the header — keep the cue
                // generic so we're not repeating it on screen.
                broadcastCue = "BROADCASTING · TAP TO SHARE"
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    withAnimation { broadcastCue = nil }
                }
            }
        }
        .onDisappear {
            coordinator.netSession.onScoreSubmissionReceived = nil
            coordinator.netSession.onClaimReceived = nil
        }
        .modifier(DoubleBlankPromptModifier(
            game: game,
            prompt: $doubleBlankPrompt,
            onResolved: { stop in continueAfterDoubleBlank(stop: stop) },
            onPenaltyApplied: { name, delta in
                withAnimation(.easeOut(duration: 0.25)) {
                    toast = "0|0 → \(name) +\(delta)"
                }
                scheduleToastClear()
            }
        ))
        .modifier(BlockedCapPromptModifier(
            game: game,
            prompt: $blockedCapPrompt,
            onAdvance: { stop in advanceStop(closed: stop) },
            onCapped: { name in
                withAnimation(.easeOut(duration: 0.25)) {
                    toast = "Blocked cap → \(name) = 0"
                }
                scheduleToastClear()
            }
        ))
        .confirmationDialog(
            "Remove a player",
            isPresented: $showRemovePlayerDialog
        ) {
            ForEach(game.players.filter { $0.isActive && !$0.isYou }) { player in
                Button("Remove \(player.name)", role: .destructive) {
                    player.isActive = false
                    try? context.save()
                    withAnimation(.easeOut(duration: 0.25)) {
                        toast = "Removed \(player.name)"
                    }
                    scheduleToastClear()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removed players are dimmed on the scoreboard and excluded from future stops.")
        }
        .task(id: pendingClaim?.playerID) {
            guard pendingClaim != nil else {
                claimSecondsLeft = nil
                return
            }
            // Tick down a visible countdown so the conductor knows the
            // dialog will auto-dismiss. Bail early if the user dismissed it.
            for sec in stride(from: 30, through: 1, by: -1) {
                guard !Task.isCancelled, pendingClaim != nil else {
                    claimSecondsLeft = nil
                    return
                }
                claimSecondsLeft = sec
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled, pendingClaim != nil else {
                claimSecondsLeft = nil
                return
            }
            pendingClaim = nil
            showAssignDialog = false
            claimSecondsLeft = nil
        }
        .overlay(alignment: .top) {
            if undoableScore != nil {
                HStack(spacing: 10) {
                    Text("Score saved")
                        .font(theme.monoFont(size: 11))
                        .foregroundStyle(theme.ink)
                    Button("Undo") {
                        if let score = undoableScore {
                            context.delete(score)
                            try? context.save()
                        }
                        undoableScore = nil
                    }
                    .font(theme.monoFont(size: 11))
                    .fontWeight(.bold)
                    .foregroundStyle(theme.brand)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(theme.cardBg, in: Capsule())
                .overlay(Capsule().stroke(theme.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: undoableScore?.id) {
            guard undoableScore != nil else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { undoableScore = nil }
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
                // Push the joiner's thumbnail to all connected peers.
                if let thumbData = thumb {
                    coordinator.netSession.pushPhoto(
                        captureID: game.captures
                            .first(where: { $0.playerID == submission.playerID && $0.stopIndex == submission.stopIndex })?.id ?? UUID(),
                        playerID: submission.playerID,
                        stop: submission.stopIndex,
                        thumbJPEG: thumbData
                    )
                }
                if let p = game.players.first(where: { $0.id == submission.playerID }) {
                    // Find the just-saved score for undo support
                    if let savedScore = game.scores.first(where: {
                        $0.playerID == submission.playerID && $0.stopIndex == submission.stopIndex
                    }) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            undoableScore = savedScore
                        }
                    }
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
        let stop = min(game.currentStopIndex, game.lengthStops)
        let engineN = Scoring.engineTile(stop: stop, rules: game.startingEngine, length: game.lengthStops)
        let code = coordinator.netSession.roomCode

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { coordinator.goHome() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .frame(width: 44, height: 44)
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("STOP \(game.currentStopIndex)/\(game.lengthStops)")
                        .font(theme.monoFont(size: 11))
                        .tracking(1.4)
                        .foregroundStyle(theme.ink)
                    DominoGlyph(value: engineN, width: 44, color: theme.ink)
                        .accessibilityLabel("Engine \(engineN) \(engineN)")
                    if !code.isEmpty {
                        Button {
                            coordinator.openShareSheet(for: game)
                        } label: {
                            Text(code)
                                .font(theme.monoFont(size: 11))
                                .fontWeight(.semibold)
                                .tracking(1.4)
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(theme.accent.opacity(0.12), in: Capsule())
                                .overlay(Capsule().stroke(theme.accent.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Room code \(code)")
                        .accessibilityHint("Opens the share sheet")
                    }
                }
                Spacer()
                Menu {
                    if game.currentStopIndex == 1 {
                        Button("Edit rules") {
                            showEditRules = true
                        }
                    }
                    Button("Share with table") {
                        coordinator.openShareSheet(for: game)
                    }
                    Button("Rename game") {
                        renamingTo = game.displayName
                        renaming = true
                    }
                    if game.players.filter({ $0.isActive && !$0.isYou }).count > 0 {
                        Button("Remove player") {
                            showRemovePlayerDialog = true
                        }
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
            .padding(.horizontal, 6)
            .background(theme.headerBg)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
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
        let stop = game.currentStopIndex
        let allDone = Scoring.nextUnenteredPlayer(stop: stop, in: game) == nil
        let standings = Scoring.standings(for: game)
        let activeCount = game.players.filter(\.isActive).count
        let drawCount = game.effectiveDrawCount(activeCount: activeCount)
        let engineN = Scoring.engineTile(stop: min(stop, game.lengthStops),
                                         rules: game.startingEngine,
                                         length: game.lengthStops)

        return ScrollView {
            VStack(spacing: 12) {
                // Collapsible round instructions
                if !game.scoringOpen && !allDone && !game.isFinished {
                    Button {
                        withAnimation { showInstructions.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.muted)
                            Text("Round setup · Draw \(drawCount) · \(engineN)|\(engineN)")
                                .font(theme.monoFont(size: 11))
                                .foregroundStyle(theme.ink)
                            Spacer()
                            Image(systemName: showInstructions ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.muted)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)

                    if showInstructions {
                        VStack(alignment: .leading, spacing: 6) {
                            if game.startingEngine.isDrawToFind {
                                instructionRow(num: "1", text: "Shuffle all dominoes face down")
                                instructionRow(num: "2", text: "Each player draws \(drawCount) dominoes")
                                instructionRow(num: "3", text: "If no one has the \(engineN)|\(engineN), draw from the boneyard until it's found")
                                instructionRow(num: "4", text: "Play the round")
                                instructionRow(num: "5", text: "Tap TILES DOWN when done")
                            } else {
                                instructionRow(num: "1", text: "Remove the \(engineN)|\(engineN) from the boneyard")
                                instructionRow(num: "2", text: "Shuffle and deal \(drawCount) dominoes each")
                                instructionRow(num: "3", text: "Play the round")
                                instructionRow(num: "4", text: "Tap TILES DOWN when done")
                            }
                        }
                        .padding(12)
                        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.border, lineWidth: 1)
                        )
                        .padding(.horizontal, 6)
                    }
                }

                // Standings list
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(standings.enumerated()), id: \.element.playerID) { index, standing in
                            let player = game.players.first(where: { $0.id == standing.playerID })
                            let currentStopScore = game.scores.first(where: {
                                $0.playerID == standing.playerID && $0.stopIndex == stop
                            })
                            let hasSubmitted = currentStopScore != nil

                            Button {
                                if let player { selectedPlayer = player }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(rankLabel(standing.place))
                                        .font(theme.displayFont(size: 22))
                                        .foregroundStyle(standing.place == 1 ? theme.brand : theme.ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .frame(width: 54, alignment: .center)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(standing.name)
                                                .font(theme.displayFont(size: 18))
                                                .foregroundStyle(theme.ink)
                                            if standing.isYou {
                                                Text("YOU")
                                                    .font(theme.monoFont(size: 9))
                                                    .tracking(1.2)
                                                    .foregroundStyle(theme.accent)
                                            }
                                        }
                                        HStack(spacing: 4) {
                                            if let pips = currentStopScore?.pips {
                                                Text("Stop \(stop): \(pips)")
                                            } else {
                                                Text("Stop \(stop): \u{2014}")
                                            }
                                            if hasSubmitted {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                        .font(theme.monoFont(size: 11))
                                        .foregroundStyle(theme.muted)
                                    }

                                    Spacer()

                                    Text("\(standing.total)")
                                        .font(theme.displayFont(size: 24))
                                        .foregroundStyle(standing.place == 1 ? theme.brand : theme.ink)

                                    VStack(spacing: 1) {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .bold))
                                        Text("AUDIT")
                                            .font(theme.monoFont(size: 7))
                                            .tracking(0.8)
                                    }
                                    .foregroundStyle(theme.muted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                                .opacity(player?.isActive == false ? 0.4 : 1.0)
                            }
                            .buttonStyle(.plain)

                            if index < standings.count - 1 {
                                Rectangle().fill(theme.borderLight).frame(height: 1)
                                    .padding(.leading, 54)
                            }
                        }
                    }
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.border, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 6)

                // Photo galleries
                ForEach(1...max(1, game.currentStopIndex), id: \.self) { galleryStop in
                    if game.captures.contains(where: { $0.stopIndex == galleryStop }) {
                        PhotoGalleryStrip(game: game, stop: galleryStop)
                    }
                }
            }
            .padding(8)
        }
    }

    private func instructionRow(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(num).")
                .font(theme.monoFont(size: 12))
                .foregroundStyle(theme.muted)
                .frame(width: 18, alignment: .trailing)
            Text(text)
                .font(theme.monoFont(size: 12))
                .foregroundStyle(theme.ink)
        }
    }

    private func rankLabel(_ place: Int) -> String {
        ordinal(place)
    }

    private var cta: some View {
        let stop = game.currentStopIndex
        let nextPlayer = Scoring.nextUnenteredPlayer(stop: stop, in: game)
        let allDone = nextPlayer == nil
        return VStack(spacing: 6) {
            if !game.scoringOpen && !allDone && !game.isFinished {
                Button {
                    game.scoringOpen = true
                    try? context.save()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("TILES DOWN")
                            .font(theme.displayFont(size: 14))
                            .tracking(2.5)
                        Text("STOP \(stop)")
                            .font(theme.monoFont(size: 10))
                            .tracking(1.2)
                            .foregroundStyle(theme.ctaText.opacity(0.7))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(theme.ctaText.opacity(0.12), in: Capsule())
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(theme.ctaText)
                    .background(Color.green.opacity(0.8), in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                }
                Text("Tap when someone has emptied their hand. Opens scoring for stop \(stop).")
                    .font(theme.monoFont(size: 10))
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            if game.scoringOpen || allDone {
                Button {
                    if allDone {
                        // Wrap-up chain: double-blank prompt (if rule on) →
                        // blocked-cap prompt (if applicable) → advance.
                        beginRoundWrapUp(stop: stop)
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
                if let p = nextPlayer, game.scoringOpen {
                    Text("Next: \(p.name)")
                        .font(theme.monoFont(size: 9))
                        .tracking(1.4)
                        .foregroundStyle(theme.muted)
                }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 6).padding(.top, 6)
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

    /// Kick off the end-of-stop wrap-up chain. Stages, in order:
    ///   1. Double-blank "Who had the 0|0?" prompt (if rule on)
    ///   2. Blocked-round-cap "set lowest to 0?" prompt (if rule on and
    ///      nobody went out this round)
    ///   3. Actual stop-advance.
    /// Each prompt's "skip"/"apply" action calls back here to continue.
    private func beginRoundWrapUp(stop: Int) {
        if game.doubleBlankPenaltyPips > 0 {
            doubleBlankPrompt = stop
            return
        }
        continueAfterDoubleBlank(stop: stop)
    }

    private func continueAfterDoubleBlank(stop: Int) {
        if game.blockedRoundCapEnabled,
           GamePersistence.wasStopBlocked(stop, in: game) {
            blockedCapPrompt = stop
            return
        }
        advanceStop(closed: stop)
    }

    /// Common close-stop path used by ADVANCE and by both branches of the
    /// blocked-round-cap confirmation.
    private func advanceStop(closed stop: Int) {
        try? GamePersistence.maybeAdvanceStop(in: context, game: game)
        withAnimation(.easeOut(duration: 0.25)) {
            toast = (game.currentStopIndex > stop) ? "Stop \(stop) closed" : "Game complete"
        }
        scheduleToastClear()
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

private struct EditRulesSheet: View {
    @Bindable var game: Game
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                AppHeaderBar(style: .modal, title: "Edit rules", onLeading: nil) {
                    Button("Done") { dismiss() }
                        .appLinkStyle()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        section("GAME LENGTH") {
                            HStack(spacing: 8) {
                                ForEach([7, 10, 13], id: \.self) { n in
                                    Button {
                                        game.lengthStops = n
                                        try? context.save()
                                    } label: {
                                        Text("\(n)")
                                            .font(theme.displayFont(size: 22))
                                            .foregroundStyle(game.lengthStops == n ? theme.ctaText : theme.ink)
                                            .frame(maxWidth: .infinity, minHeight: 52)
                                            .background(game.lengthStops == n ? theme.cta : theme.cardBg,
                                                        in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                                                    .stroke(game.lengthStops == n ? theme.brand : theme.borderLight, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        section("STARTING ENGINE") {
                            ForEach(StartingEngine.allCases) { option in
                                Button {
                                    game.startingEngineRaw = option.rawValue
                                    try? context.save()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: game.startingEngine == option ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(game.startingEngine == option ? theme.brand : theme.muted)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.displayName)
                                                .font(theme.monoFont(size: 13))
                                                .foregroundStyle(theme.ink)
                                            Text(option.description)
                                                .font(theme.monoFont(size: 10))
                                                .foregroundStyle(theme.muted)
                                        }
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(game.startingEngine == option ? theme.brand : theme.borderLight,
                                                    lineWidth: game.startingEngine == option ? 1.5 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        section("HOUSE RULES") {
                            HouseRulesSection(game: game) { try? context.save() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(theme.monoFont(size: 11))
                .tracking(2)
                .foregroundStyle(theme.muted)
            content()
        }
    }
}

private struct PlayerDetailSheet: View {
    let game: Game
    let player: Player
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        let total = Scoring.total(for: player.id, in: game)
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                                .font(theme.monoFont(size: 13))
                        }
                        .foregroundStyle(theme.accent)
                    }
                    Spacer()
                    Text("\(player.name)")
                        .font(theme.displayFont(size: 16))
                        .foregroundStyle(theme.ink)
                    Text("\u{00B7} \(total) total")
                        .font(theme.monoFont(size: 13))
                        .foregroundStyle(theme.muted)
                    Spacer()
                    // Invisible balance element
                    Text("Back")
                        .font(theme.monoFont(size: 13))
                        .hidden()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(theme.subBg)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.border).frame(height: 1)
                }

                // Stop list
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(1...game.lengthStops, id: \.self) { stopNum in
                            let engineN = Scoring.engineTile(
                                stop: stopNum,
                                rules: game.startingEngine,
                                length: game.lengthStops
                            )
                            let score = Scoring.score(for: player.id, stop: stopNum, in: game)
                            let isCurrent = stopNum == game.currentStopIndex

                            Button {
                                coordinator.openAudit(game: game, player: player, stop: stopNum)
                                dismiss()
                            } label: {
                                HStack(spacing: 0) {
                                    Text("Stop \(stopNum)")
                                        .font(theme.monoFont(size: 12))
                                        .fontWeight(isCurrent ? .bold : .regular)
                                        .foregroundStyle(isCurrent ? theme.accent : theme.ink)
                                        .frame(width: 56, alignment: .leading)

                                    Text("(\(engineN)|\(engineN))")
                                        .font(theme.monoFont(size: 11))
                                        .foregroundStyle(theme.muted)
                                        .frame(width: 52, alignment: .leading)

                                    // Dotted filler
                                    GeometryReader { geo in
                                        let dotCount = max(1, Int(geo.size.width / 5))
                                        Text(String(repeating: ".", count: dotCount))
                                            .font(theme.monoFont(size: 11))
                                            .foregroundStyle(theme.borderLight)
                                            .lineLimit(1)
                                    }
                                    .frame(height: 16)

                                    if let score {
                                        Text("\(score.effectivePips)")
                                            .font(theme.monoFont(size: 13))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(isCurrent ? theme.accent : theme.ink)
                                            .frame(width: 40, alignment: .trailing)
                                    } else {
                                        Text("\u{2014}")
                                            .font(theme.monoFont(size: 13))
                                            .foregroundStyle(theme.muted)
                                            .frame(width: 40, alignment: .trailing)
                                    }

                                    if isCurrent {
                                        Text("\u{2190}")
                                            .font(theme.monoFont(size: 12))
                                            .foregroundStyle(theme.accent)
                                            .frame(width: 20, alignment: .center)
                                    } else {
                                        Spacer().frame(width: 20)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isCurrent ? theme.accent.opacity(0.08) : Color.clear)
                            }
                            .buttonStyle(.plain)

                            if stopNum < game.lengthStops {
                                Rectangle().fill(theme.borderLight).frame(height: 1)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.border, lineWidth: 1)
                    )
                    .padding(14)
                }
            }
        }
    }
}

/// "Who had the 0|0?" prompt fired after the last hand of a stop is entered
/// when the double-blank penalty rule is enabled. Conductor picks a player
/// (we apply the penalty) or "Nobody had it" (no-op). Either choice
/// continues the wrap-up chain via `onResolved`.
private struct DoubleBlankPromptModifier: ViewModifier {
    let game: Game
    @Binding var prompt: Int?
    var onResolved: (Int) -> Void
    var onPenaltyApplied: (String, Int) -> Void

    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Who had the 0|0 this round?",
            isPresented: Binding(
                get: { prompt != nil },
                set: { if !$0 { prompt = nil } }
            ),
            presenting: prompt
        ) { stop in
            ForEach(game.players.filter(\.isActive)) { player in
                Button("\(player.name) (+\(game.doubleBlankPenaltyPips))") {
                    let updated = try? GamePersistence.applyDoubleBlankPenalty(
                        stop, to: player.id, in: game, context: context
                    )
                    if updated != nil {
                        onPenaltyApplied(player.name, game.doubleBlankPenaltyPips)
                    }
                    prompt = nil
                    onResolved(stop)
                }
            }
            Button("Nobody had it") {
                prompt = nil
                onResolved(stop)
            }
            Button("Cancel", role: .cancel) { prompt = nil }
        } message: { _ in
            Text("The double-blank penalty (+\(game.doubleBlankPenaltyPips)) is added to whoever was caught with the 0|0 tile.")
        }
    }
}

/// Pulled out of `ScoreboardView.body` because the surrounding view had
/// outgrown the SwiftUI type-checker's expression budget.
private struct BlockedCapPromptModifier: ViewModifier {
    let game: Game
    @Binding var prompt: Int?
    var onAdvance: (Int) -> Void
    var onCapped: (String) -> Void

    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.confirmationDialog(
            prompt.map { "Round \($0) was blocked" } ?? "",
            isPresented: Binding(
                get: { prompt != nil },
                set: { if !$0 { prompt = nil } }
            ),
            presenting: prompt
        ) { stop in
            Button("Set lowest hand to 0 and advance") {
                let capped = try? GamePersistence.applyBlockedRoundCap(stop, in: game, context: context)
                if let capped, let name = game.players.first(where: { $0.id == capped.playerID })?.name {
                    onCapped(name)
                }
                onAdvance(stop)
                prompt = nil
            }
            Button("Advance without capping") {
                onAdvance(stop)
                prompt = nil
            }
            Button("Cancel", role: .cancel) { prompt = nil }
        } message: { _ in
            Text("Nobody went out this round. The blocked-round-cap rule lets the lowest hand count as 0 instead.")
        }
    }
}
