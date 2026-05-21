import SwiftUI

struct ScoreCardTable: View {
    let game: Game
    var onTapScore: (Player, Int) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        let players = game.sortedPlayers
        let stops = game.lengthStops
        let currentStop = game.currentStopIndex
        let grid = Scoring.grid(for: game)
        let standings = Scoring.standings(for: game)
        let leaderID = standings.first?.playerID

        VStack(spacing: 0) {
            header(stops: stops, currentStop: currentStop)
            ForEach(players.indices, id: \.self) { i in
                let p = players[i]
                playerRow(
                    player: p,
                    row: grid[p.id] ?? [],
                    stops: stops,
                    currentStop: currentStop,
                    isLeader: p.id == leaderID,
                    isLast: i == players.count - 1
                )
            }
        }
        .background(theme.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func header(stops: Int, currentStop: Int) -> some View {
        HStack(spacing: 0) {
            Text("PLAYER")
                .font(theme.monoFont(size: 10))
                .tracking(0.8)
                .foregroundStyle(theme.muted)
                .frame(width: 64, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            ForEach(1...stops, id: \.self) { n in
                Text("\(n)")
                    .font(theme.monoFont(size: 10))
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .foregroundStyle(n == currentStop ? theme.bg
                                    : (n < currentStop ? theme.ink : theme.muted))
                    .background(n == currentStop ? theme.accent : Color.clear)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(theme.border).frame(width: 1)
                    }
            }
            Text("TOT")
                .font(theme.monoFont(size: 10))
                .tracking(1)
                .foregroundStyle(theme.muted)
                .frame(width: 38, height: 26)
                .background(theme.subBg)
                .overlay(alignment: .leading) {
                    Rectangle().fill(theme.border).frame(width: 2)
                }
        }
        .background(theme.headerBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }

    private func playerRow(player: Player, row: [Int?], stops: Int, currentStop: Int, isLeader: Bool, isLast: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                if player.isYou {
                    Text("▸").foregroundStyle(theme.accent).font(.system(size: 10))
                }
                Text(player.name)
                    .font(theme.monoFont(size: 11))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                if isLeader {
                    Text("♔").foregroundStyle(theme.brand).font(.system(size: 10))
                }
            }
            .frame(width: 64, alignment: .leading)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .overlay(alignment: .trailing) {
                Rectangle().fill(theme.border).frame(width: 1)
            }

            ForEach(1...stops, id: \.self) { n in
                let s = (n <= row.count) ? row[n-1] : nil
                let isCurrent = n == currentStop
                Button {
                    if s != nil { onTapScore(player, n) }
                } label: {
                    Text(s.map { "\($0)" } ?? "·")
                        .font(theme.monoFont(size: 11))
                        .fontWeight(.semibold)
                        .foregroundStyle(s == nil ? theme.muted : theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(isCurrent ? theme.currentColumn : Color.clear)
                }
                .buttonStyle(.plain)
                .disabled(s == nil)
                .overlay(alignment: .leading) {
                    Rectangle().fill(theme.borderLight).frame(width: 1)
                }
                .accessibilityLabel("\(player.name), stop \(n): \(s.map { "\($0)" } ?? "blank")")
            }

            Text("\(row.compactMap { $0 }.reduce(0,+))")
                .font(theme.monoFont(size: 13))
                .fontWeight(.bold)
                .foregroundStyle(isLeader ? theme.brand : theme.ink)
                .frame(width: 38, height: 28)
                .background(theme.subBg)
                .overlay(alignment: .leading) {
                    Rectangle().fill(theme.border).frame(width: 2)
                }
        }
        .background(player.isYou ? theme.youBg : Color.clear)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(theme.borderLight).frame(height: 1)
            }
        }
    }
}
