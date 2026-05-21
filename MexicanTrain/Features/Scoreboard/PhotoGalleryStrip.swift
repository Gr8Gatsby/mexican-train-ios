import SwiftUI

struct PhotoGalleryStrip: View {
    let game: Game
    let stop: Int

    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator

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
                    PhotoTile(game: game, player: p, stop: stop)
                }
            }
        }
        .padding(8)
        .background(theme.subBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.borderLight, lineWidth: 1)
        )
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
            coordinator.openAudit(game: game, player: player, stop: stop)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let capture, let img = coordinator.photoStore.thumbnail(filename: capture.filename, gameID: game.id) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: 0x8B6F47), Color(hex: 0x4A3522)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text(String(player.name.prefix(4)).uppercased())
                            .font(theme.monoFont(size: 8))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.6), radius: 2)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(4)
                if let score {
                    Text("\(score.pips)")
                        .font(theme.monoFont(size: 9))
                        .fontWeight(.bold)
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                } else {
                    Text("—")
                        .font(theme.monoFont(size: 9))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.black.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(score == nil)
    }
}
