import SwiftUI
import SwiftData
import UIKit

struct ScoreboardView: View {
    let game: Game
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @State private var menuOpen = false
    @State private var renamingTo = ""
    @State private var renaming = false
    @State private var confirmDelete = false
    @State private var toast: String?
    @State private var overrideTarget: OverrideTarget?
    @State private var overrideConfirm: OverrideTarget?

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
        .onAppear {
            coordinator.netSession.onScoreSubmissionReceived = { submission in
                Task { @MainActor in
                    handleIncomingSubmission(submission)
                }
            }
        }
        .onDisappear {
            coordinator.netSession.onScoreSubmissionReceived = nil
        }
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
                try? GamePersistence.maybeAdvanceStop(in: context, game: game)
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
        HStack {
            Button {
                coordinator.goHome()
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(theme.ink)
                    .padding(8)
            }
            .accessibilityLabel("Back")

            Text("MEX·TRAIN")
                .font(theme.displayFont(size: 16))
                .tracking(2)
                .foregroundStyle(theme.brand)
            Spacer()

            broadcastPill

            HStack(spacing: 4) {
                Text("STOP")
                    .font(theme.monoFont(size: 9))
                    .tracking(1.4)
                    .foregroundStyle(theme.muted)
                Text("\(min(game.currentStopIndex, game.lengthStops))")
                    .font(theme.displayFont(size: 18))
                    .foregroundStyle(theme.ink)
                Text("/\(game.lengthStops)")
                    .font(theme.displayFont(size: 12))
                    .foregroundStyle(theme.muted)
            }

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
                    .foregroundStyle(theme.muted)
                    .padding(8)
            }
            .accessibilityLabel("Game menu")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(theme.headerBg)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    /// Compact farkle-style broadcast indicator: room code when nobody's
    /// joined, viewer count when someone has. Tap opens the share sheet.
    private var broadcastPill: some View {
        let session = coordinator.netSession
        let isHosting = session.role == .host
        let peers = session.connectedPeerCount
        return Button {
            coordinator.openShareSheet(for: game)
        } label: {
            HStack(spacing: 4) {
                if peers > 0 {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("\(peers)")
                        .font(theme.monoFont(size: 11))
                        .fontWeight(.bold)
                } else {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(isHosting ? session.roomCode : "SHARE")
                        .font(theme.monoFont(size: 11))
                        .fontWeight(.bold)
                        .tracking(0.6)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .foregroundStyle(peers > 0 ? theme.ctaText : theme.ink)
            .background(peers > 0 ? theme.brand : theme.subBg,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.border, lineWidth: 1)
            )
        }
        .accessibilityLabel(isHosting
                            ? "Room code \(session.roomCode). \(peers) joined."
                            : "Share game")
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
                        overrideConfirm = OverrideTarget(player: player, stop: stop)
                    }
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
        HStack {
            Text("♔ LEADER  ▸ YOU")
                .font(theme.monoFont(size: 9))
                .tracking(1.2)
                .foregroundStyle(theme.muted)
            Spacer()
            Text("+ SUBMIT FOR PLAYER · TAP SCORE TO AUDIT")
                .font(theme.monoFont(size: 9))
                .tracking(1.2)
                .foregroundStyle(theme.muted)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
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
        }
        .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 8)
        .background(theme.subBg)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
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
