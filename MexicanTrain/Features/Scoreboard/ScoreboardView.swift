import SwiftUI
import SwiftData

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
                ScoreCardTable(game: game) { player, stop in
                    coordinator.openAudit(game: game, player: player, stop: stop)
                }
                if game.currentStopIndex > 1 {
                    PhotoGalleryStrip(game: game, stop: game.currentStopIndex - 1)
                }
            }
            .padding(8)
        }
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
