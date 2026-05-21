import SwiftUI

/// Joiner-side scoreboard. Drives entirely from the most recent broadcast
/// snapshot — no SwiftData on this device.
struct SpectatorView: View {
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        let session = coordinator.netSession
        return ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if let snap = session.latestSnapshot {
                    engineStrip(snap: snap)
                    ScrollView {
                        SnapshotTable(snap: snap)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                } else {
                    Spacer()
                    Text("Waiting for host…")
                        .font(theme.monoFont(size: 12))
                        .tracking(1.4)
                        .foregroundStyle(theme.muted)
                    Spacer()
                }
                footer
            }
            if session.joinState == .hostEnded {
                hostEndedOverlay
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                coordinator.netSession.leave()
                coordinator.goHome()
            } label: {
                Image(systemName: "chevron.left").foregroundStyle(theme.ink).padding(8)
            }
            Text("MEX·TRAIN")
                .font(theme.displayFont(size: 16))
                .tracking(2)
                .foregroundStyle(theme.brand)
            Spacer()
            Text("SPECTATING · CODE \(coordinator.netSession.latestSnapshot?.roomCode ?? "----")")
                .font(theme.monoFont(size: 9))
                .tracking(1.4)
                .foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(theme.headerBg)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private func engineStrip(snap: GameSnapshot) -> some View {
        let n = Scoring.engineTile(stop: min(snap.currentStop, snap.length),
                                   rules: snap.startingEngine,
                                   length: snap.length)
        return HStack(spacing: 8) {
            Text("ENGINE")
                .font(theme.monoFont(size: 9))
                .tracking(1.4)
                .foregroundStyle(theme.muted)
            DominoGlyph(value: n, width: 32, color: theme.ink)
            Spacer()
            Text("STOP \(min(snap.currentStop, snap.length))/\(snap.length)")
                .font(theme.monoFont(size: 10))
                .tracking(1.4)
                .foregroundStyle(theme.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(theme.subBg)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var footer: some View {
        Button {
            coordinator.netSession.leave()
            coordinator.goHome()
        } label: {
            Text("LEAVE")
                .font(theme.displayFont(size: 13))
                .tracking(2)
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(theme.ink)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                        .stroke(theme.border, lineWidth: 1)
                )
        }
        .padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 10)
        .background(theme.subBg)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var hostEndedOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("Host left the game")
                    .font(theme.displayFont(size: 22))
                    .foregroundStyle(.white)
                Button {
                    coordinator.netSession.leave()
                    coordinator.goHome()
                } label: {
                    Text("BACK TO HOME")
                        .font(theme.monoFont(size: 12))
                        .tracking(1.4)
                        .foregroundStyle(theme.ctaText)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(theme.brand, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                }
            }
            .padding(24)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 28)
        }
    }
}

/// Snapshot-driven golf-card table mirroring the host's `ScoreCardTable`
/// but reading from `GameSnapshot` instead of SwiftData models.
struct SnapshotTable: View {
    let snap: GameSnapshot
    @Environment(\.theme) private var theme

    var body: some View {
        let players = snap.players.sorted(by: { $0.seat < $1.seat })
        let stops = snap.length
        let current = snap.currentStop
        let scoresByPlayer = Dictionary(grouping: snap.scores, by: { $0.playerID })
        let totals = Dictionary(uniqueKeysWithValues: players.map { p in
            (p.id, (scoresByPlayer[p.id] ?? []).reduce(0) { $0 + $1.pips })
        })
        let leaderID = totals.min(by: { $0.value < $1.value })?.key

        return VStack(spacing: 0) {
            header(stops: stops, current: current)
            ForEach(players.indices, id: \.self) { i in
                let p = players[i]
                let row = (1...stops).map { stop in
                    (scoresByPlayer[p.id] ?? []).first(where: { $0.stop == stop })?.pips
                }
                let claim = snap.claims.first(where: { $0.playerID == p.id })
                playerRow(player: p, row: row, total: totals[p.id] ?? 0,
                          isLeader: p.id == leaderID, claim: claim,
                          isLast: i == players.count - 1)
            }
        }
        .background(theme.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func header(stops: Int, current: Int) -> some View {
        HStack(spacing: 0) {
            Text("PLAYER")
                .font(theme.monoFont(size: 10))
                .foregroundStyle(theme.muted)
                .frame(width: 80, alignment: .leading)
                .padding(.horizontal, 6).padding(.vertical, 6)
            ForEach(1...stops, id: \.self) { n in
                Text("\(n)")
                    .font(theme.monoFont(size: 10))
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .foregroundStyle(n == current ? theme.bg : (n < current ? theme.ink : theme.muted))
                    .background(n == current ? theme.accent : Color.clear)
                    .overlay(alignment: .leading) { Rectangle().fill(theme.border).frame(width: 1) }
            }
            Text("TOT")
                .font(theme.monoFont(size: 10))
                .tracking(1)
                .foregroundStyle(theme.muted)
                .frame(width: 38, height: 26)
                .background(theme.subBg)
        }
        .background(theme.headerBg)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private func playerRow(player: PlayerSnapshot, row: [Int?], total: Int, isLeader: Bool, claim: PlayerClaim?, isLast: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                if let data = claim?.photoJPEG, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                }
                Text(claim?.displayName ?? player.name)
                    .font(theme.monoFont(size: 11))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                if isLeader {
                    Text("♔").foregroundStyle(theme.brand).font(.system(size: 10))
                }
            }
            .frame(width: 80, alignment: .leading)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .overlay(alignment: .trailing) {
                Rectangle().fill(theme.border).frame(width: 1)
            }
            ForEach(row.indices, id: \.self) { i in
                Text(row[i].map { "\($0)" } ?? "·")
                    .font(theme.monoFont(size: 11))
                    .fontWeight(.semibold)
                    .foregroundStyle(row[i] == nil ? theme.muted : theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(theme.borderLight).frame(width: 1)
                    }
            }
            Text("\(total)")
                .font(theme.monoFont(size: 13))
                .fontWeight(.bold)
                .foregroundStyle(isLeader ? theme.brand : theme.ink)
                .frame(width: 38, height: 28)
                .background(theme.subBg)
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(theme.borderLight).frame(height: 1)
            }
        }
    }
}
