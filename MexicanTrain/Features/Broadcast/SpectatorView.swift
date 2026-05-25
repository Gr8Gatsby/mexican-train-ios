import SwiftUI
import SwiftData

/// Joiner-side scoreboard. Drives the live UI from
/// `MexTrainNetSession.latestSnapshot` and also writes each snapshot
/// to local SwiftData via `JoinedGamePersistence` so the joiner gets
/// a persisted memory of the game after they leave.
struct SpectatorView: View {
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let session = coordinator.netSession
        return ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if let snap = session.latestSnapshot {
                    engineStrip(snap: snap)
                    ScrollView {
                        SnapshotTable(snap: snap, myPlayerID: session.myPlayerID)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                        snapshotPhotoGallery(snap: snap)
                            .padding(.horizontal, 8)
                    }
                    addMyScoreCTA(snap: snap, myID: session.myPlayerID)
                } else {
                    Spacer()
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(theme.brand)
                        Text("Waiting for host…")
                            .font(theme.monoFont(size: 12))
                            .tracking(1.4)
                            .foregroundStyle(theme.muted)
                        if !session.roomCode.isEmpty {
                            Text("CODE \(session.roomCode)")
                                .font(theme.displayFont(size: 22))
                                .tracking(4)
                                .foregroundStyle(theme.brand)
                                .padding(.top, 4)
                        }
                    }
                    Spacer()
                }
                footer
            }
            if session.joinState == .reconnecting {
                reconnectingOverlay
            }
            if session.joinState == .hostEnded {
                hostEndedOverlay
            }
        }
        .onChange(of: session.latestSnapshot?.seq) { _, _ in
            persistLatestSnapshot()
        }
        .onAppear { persistLatestSnapshot() }
    }

    private func persistLatestSnapshot() {
        guard let snap = coordinator.netSession.latestSnapshot else { return }
        _ = try? JoinedGamePersistence.upsert(
            in: modelContext,
            snapshot: snap,
            myPlayerID: coordinator.netSession.myPlayerID
        )
    }

    /// CTA that appears when the joiner's claimed slot has no player-
    /// submitted score for the current stop. Per spec §3.6 the CTA hides
    /// once the player themselves has submitted, but stays available if
    /// only the conductor has entered a value (player can override).
    @ViewBuilder
    private func addMyScoreCTA(snap: GameSnapshot, myID: UUID?) -> some View {
        if let myID,
           !snap.isFinished,
           let me = snap.players.first(where: { $0.id == myID }),
           snap.currentStop <= snap.length,
           !mySlotHasPlayerScore(snap: snap, myID: myID, stop: snap.currentStop) {
            VStack(spacing: 4) {
                Button {
                    coordinator.openJoinerCamera(
                        playerID: myID, playerName: me.name,
                        stop: snap.currentStop, lengthStops: snap.length
                    )
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .accessibilityHidden(true)
                        Text("ADD MY SCORE")
                            .font(theme.displayFont(size: 14))
                            .tracking(2.5)
                        Text("STOP \(snap.currentStop)")
                            .font(theme.monoFont(size: 10))
                            .tracking(1.2)
                            .foregroundStyle(theme.ctaText.opacity(0.7))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(theme.ctaText.opacity(0.12), in: Capsule())
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(theme.ctaText)
                    .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                }
                if mySlotHasConductorScore(snap: snap, myID: myID, stop: snap.currentStop) {
                    Text("Conductor already entered a value — your submission will replace it.")
                        .font(theme.monoFont(size: 9))
                        .tracking(1.0)
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
    }

    private func mySlotHasPlayerScore(snap: GameSnapshot, myID: UUID, stop: Int) -> Bool {
        snap.scores.contains { $0.playerID == myID && $0.stop == stop && $0.submittedBy == .player }
    }

    private func mySlotHasConductorScore(snap: GameSnapshot, myID: UUID, stop: Int) -> Bool {
        snap.scores.contains { $0.playerID == myID && $0.stop == stop && $0.submittedBy == .conductor }
    }

    @ViewBuilder
    private func snapshotPhotoGallery(snap: GameSnapshot) -> some View {
        let stops = Set(snap.recentCaptures.map(\.stop)).sorted()
        if !stops.isEmpty {
            ForEach(stops, id: \.self) { stop in
                let capsForStop = snap.recentCaptures.filter { $0.stop == stop }
                if !capsForStop.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("📷 STOP \(stop) · CAMERA ROLL")
                            .font(theme.monoFont(size: 9))
                            .tracking(1.4)
                            .foregroundStyle(theme.muted)
                        let cols = min(max(capsForStop.count, 1), 4)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: cols), spacing: 5) {
                            ForEach(capsForStop, id: \.id) { cap in
                                snapshotPhotoTile(cap: cap, snap: snap)
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
            }
        }
    }

    private func snapshotPhotoTile(cap: CaptureSnapshot, snap: GameSnapshot) -> some View {
        let playerName = snap.players.first(where: { $0.id == cap.playerID })?.name ?? ""
        let score = snap.scores.first(where: { $0.playerID == cap.playerID && $0.stop == cap.stop })
        return ZStack(alignment: .bottomTrailing) {
            if let img = UIImage(data: cap.thumbJPEG) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    theme.cardBg
                    Image(systemName: "camera")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.muted.opacity(0.45))
                }
            }
            VStack(alignment: .leading) {
                HStack {
                    Text(String(playerName.prefix(4)).uppercased())
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
                    .font(theme.monoFont(size: 10))
                    .fontWeight(.bold)
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.4), lineWidth: 1)
        )
    }

    private var header: some View {
        let session = coordinator.netSession
        let snap = session.latestSnapshot
        let me = snap?.players.first(where: { $0.id == session.myPlayerID })
        // Show whatever code we know about — the live snapshot's, or the
        // code we connected with via the join sheet.
        let codeText = (snap?.roomCode.isEmpty == false ? snap?.roomCode : session.roomCode) ?? "----"
        let title = me.map { "Playing as \($0.name)" } ?? "Joining…"
        return AppHeaderBar(
            style: .push,
            title: title,
            subtitle: "CODE \(codeText)",
            onLeading: {
                coordinator.settings.clearActiveJoin()
                coordinator.netSession.leave()
                coordinator.goHome()
            }
        )
    }

    private func engineStrip(snap: GameSnapshot) -> some View {
        let n = Scoring.engineTile(stop: min(snap.currentStop, snap.length),
                                   rules: snap.startingEngine,
                                   length: snap.length)
        let health = coordinator.netSession.connectionHealth
        let healthColor: Color = {
            switch health {
            case .good: return .green
            case .degraded: return .yellow
            case .lost: return .red
            }
        }()
        return HStack(spacing: 8) {
            Text("ENGINE")
                .font(theme.monoFont(size: 9))
                .tracking(1.4)
                .foregroundStyle(theme.muted)
            DominoGlyph(value: n, width: 32, color: theme.ink)
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(healthColor)
                    .frame(width: 8, height: 8)
                if health == .lost {
                    Text("CONNECTION LOST")
                        .font(theme.monoFont(size: 9))
                        .tracking(1.0)
                        .foregroundStyle(.red)
                }
            }
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
            coordinator.settings.clearActiveJoin()
            coordinator.netSession.leave()
            coordinator.goHome()
        } label: { Text("LEAVE") }
            .appSecondaryStyle()
            .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 10)
            .background(theme.subBg)
            .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var reconnectingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(theme.brand)
                Text("Reconnecting...")
                    .font(theme.monoFont(size: 14))
                    .tracking(1.4)
                    .foregroundStyle(theme.ink)
            }
            .padding(24)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 28)
        }
    }

    private var hostEndedOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("Host left the game")
                    .font(theme.displayFont(size: 22))
                    .foregroundStyle(theme.ink)
                Button {
                    coordinator.settings.clearActiveJoin()
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
    var myPlayerID: UUID? = nil
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
                          isMe: p.id == myPlayerID,
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

    private func playerRow(player: PlayerSnapshot, row: [Int?], total: Int, isLeader: Bool, claim: PlayerClaim?, isMe: Bool, isLast: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                if isMe {
                    Text("▸").foregroundStyle(theme.accent).font(.system(size: 10))
                }
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
        .background(isMe ? theme.youBg : Color.clear)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(theme.borderLight).frame(height: 1)
            }
        }
    }
}
