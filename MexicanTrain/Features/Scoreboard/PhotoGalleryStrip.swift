import SwiftUI

struct PhotoGalleryStrip: View {
    let game: Game
    let stop: Int

    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @State private var selectedCapture: Capture?

    var body: some View {
        let players = game.sortedPlayers
        let cols = gridColumns(for: players.count)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("📷 STOP \(stop) · CAMERA ROLL")
                    .font(theme.monoFont(size: 9))
                    .tracking(1.4)
                    .foregroundStyle(theme.muted)
                Spacer()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: cols),
                      spacing: 5) {
                ForEach(players) { p in
                    PhotoTile(game: game, player: p, stop: stop, selectedCapture: $selectedCapture)
                }
            }
        }
        .padding(8)
        .background(theme.subBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.borderLight, lineWidth: 1)
        )
        .fullScreenCover(item: $selectedCapture) { capture in
            PhotoZoomOverlay(capture: capture, game: game)
        }
    }

    private func gridColumns(for n: Int) -> Int {
        switch n {
        case 1...3: return n
        case 4: return 2
        case 5, 6: return 3
        default: return 4
        }
    }
}

private struct PhotoTile: View {
    let game: Game
    let player: Player
    let stop: Int
    @Binding var selectedCapture: Capture?

    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator

    private var capture: Capture? {
        game.captures.first(where: { $0.playerID == player.id && $0.stopIndex == stop })
    }
    private var score: Score? {
        Scoring.score(for: player.id, stop: stop, in: game)
    }

    var body: some View {
        Button {
            if let capture {
                selectedCapture = capture
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                let hasImage = capture != nil && coordinator.photoStore.thumbnail(
                    filename: capture!.filename, gameID: game.id
                ) != nil
                if let capture, let img = coordinator.photoStore.thumbnail(
                    filename: capture.filename, gameID: game.id
                ) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Subtle parchment placeholder — no harsh dark gradient
                    // — so debug-seeded gallery tiles don't look broken.
                    ZStack {
                        theme.cardBg
                        Image(systemName: "camera")
                            .font(.system(size: 18))
                            .foregroundStyle(theme.muted.opacity(0.45))
                    }
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text(String(player.name.prefix(4)).uppercased())
                            .font(theme.monoFont(size: 8))
                            .foregroundStyle(hasImage ? .white.opacity(0.85) : theme.muted)
                            .shadow(color: .black.opacity(hasImage ? 0.6 : 0), radius: 2)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(4)
                if let score {
                    Text("\(score.pips)")
                        .font(theme.monoFont(size: 10))
                        .fontWeight(.bold)
                        .foregroundStyle(hasImage ? theme.accent : theme.ink)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(hasImage ? Color.black.opacity(0.65) : theme.subBg,
                                    in: RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(hasImage ? Color.clear : theme.border, lineWidth: 1)
                        )
                        .padding(4)
                }
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.black.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(capture == nil)
    }
}

private struct PhotoZoomOverlay: View {
    let capture: Capture
    let game: Game
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator

    /// Look up the player this capture belongs to, so we can drop the
    /// conductor straight into AuditView for the right row/stop instead
    /// of forcing them to back out and dig through the standings.
    private var capturePlayer: Player? {
        game.players.first(where: { $0.id == capture.playerID })
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = coordinator.photoStore.thumbnail(filename: capture.filename, gameID: game.id) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
            }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.5), radius: 4)
                    }
                    .padding(16)
                }
                Spacer()
                if let player = capturePlayer {
                    Button {
                        dismiss()
                        coordinator.openAudit(game: game, player: player, stop: capture.stopIndex)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                            Text("EDIT SCORE")
                                .font(theme.displayFont(size: 13))
                                .tracking(2)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 48)
                        .background(theme.accent, in: Capsule())
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                    }
                    .padding(.bottom, 28)
                    .accessibilityLabel("Edit \(player.name)'s score for stop \(capture.stopIndex)")
                }
            }
        }
    }
}
