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

    @State private var confettiID = UUID()
    @State private var selectedPhotoData: Data?
    @State private var selectedSnapshotPlayer: PlayerSnapshot?

    var body: some View {
        let session = coordinator.netSession
        return ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if let snap = session.latestSnapshot {
                    if snap.isFinished {
                        let winnerID = snap.winnerPlayerID ?? snap.players.first?.id ?? UUID()
                        celebrationView(snap: snap, winnerID: winnerID)
                    } else if snap.currentStop < 1 {
                        lobbyView(snap: snap)
                    } else {
                        engineStrip(snap: snap)
                        ScrollView {
                            snapshotStandingsView(snap: snap, myID: session.myPlayerID)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                            snapshotPhotoGallery(snap: snap)
                                .padding(.horizontal, 8)
                        }
                        addMyScoreCTA(snap: snap, myID: session.myPlayerID)
                    }
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
        .onChange(of: session.photoCacheVersion) { _, _ in
            persistLatestSnapshot()
        }
        .onAppear { persistLatestSnapshot() }
        .fullScreenCover(isPresented: Binding(
            get: { selectedPhotoData != nil },
            set: { if !$0 { selectedPhotoData = nil } }
        )) {
            SpectatorPhotoZoomOverlay(photoData: selectedPhotoData)
        }
        .sheet(item: $selectedSnapshotPlayer) { player in
            if let snap = coordinator.netSession.latestSnapshot {
                SnapshotPlayerDetailSheet(player: player, snap: snap)
            }
        }
        .alert("Leave game?", isPresented: $showLeaveConfirm) {
            Button("Leave", role: .destructive) { leaveGame() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("You can rejoin later from the home screen.")
        }
    }

    private func persistLatestSnapshot() {
        guard let snap = coordinator.netSession.latestSnapshot else { return }
        _ = try? JoinedGamePersistence.upsert(
            in: modelContext,
            snapshot: snap,
            myPlayerID: coordinator.netSession.myPlayerID,
            photoCache: coordinator.netSession.allCachedPhotos
        )
    }

    /// CTA that appears when the joiner's claimed slot has no player-
    /// submitted score for the current stop. Per spec §3.6 the CTA hides
    /// once the player themselves has submitted, but stays available if
    /// only the conductor has entered a value (player can override).
    /// Hidden when the game hasn't started yet (no scores and on stop 1).
    @ViewBuilder
    private func addMyScoreCTA(snap: GameSnapshot, myID: UUID?) -> some View {
        if let myID,
           !snap.isFinished,
           let me = snap.players.first(where: { $0.id == myID }),
           snap.currentStop <= snap.length,
           !mySlotHasPlayerScore(snap: snap, myID: myID, stop: snap.currentStop) {
            if !snap.scoringOpen {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.muted)
                        Text("Waiting for tiles down...")
                            .font(theme.monoFont(size: 11))
                            .tracking(1.0)
                            .foregroundStyle(theme.muted)
                    }
                    Text("Conductor opens scoring once someone has emptied their hand.")
                        .font(theme.monoFont(size: 9))
                        .tracking(0.8)
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            } else {
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
                    if let pips = conductorEnteredPips(snap: snap, myID: myID, stop: snap.currentStop) {
                        Text("Conductor entered \(pips) — your submission will replace it.")
                            .font(theme.monoFont(size: 9))
                            .tracking(1.0)
                            .foregroundStyle(theme.muted)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 14).padding(.top, 6)
            }
        }
    }

    private func mySlotHasPlayerScore(snap: GameSnapshot, myID: UUID, stop: Int) -> Bool {
        snap.scores.contains { $0.playerID == myID && $0.stop == stop && $0.submittedBy == .player }
    }

    private func mySlotHasConductorScore(snap: GameSnapshot, myID: UUID, stop: Int) -> Bool {
        conductorEnteredPips(snap: snap, myID: myID, stop: stop) != nil
    }

    private func conductorEnteredPips(snap: GameSnapshot, myID: UUID, stop: Int) -> Int? {
        snap.scores
            .first { $0.playerID == myID && $0.stop == stop && $0.submittedBy == .conductor }
            .map(\.pips)
    }

    @ViewBuilder
    private func snapshotStandingsView(snap: GameSnapshot, myID: UUID?) -> some View {
        let scoresByPlayer = Dictionary(grouping: snap.scores, by: { $0.playerID })
        let players = snap.players.filter(\.isActive) + snap.players.filter { !$0.isActive }
        let totals: [(PlayerSnapshot, Int)] = players.map { p in
            let t = (scoresByPlayer[p.id] ?? []).filter { !$0.excluded }.reduce(0) { $0 + $1.pips }
            return (p, t)
        }
        let sorted = totals.sorted { $0.1 < $1.1 }
        // Compute places with tie handling
        let standings: [(player: PlayerSnapshot, total: Int, place: Int)] = {
            var result: [(PlayerSnapshot, Int, Int)] = []
            var lastTotal: Int? = nil
            var lastPlace = 0
            for (index, pair) in sorted.enumerated() {
                let (p, t) = pair
                if lastTotal == nil || lastTotal != t {
                    lastPlace = index + 1
                    lastTotal = t
                }
                result.append((p, t, lastPlace))
            }
            return result
        }()
        let currentStop = snap.currentStop
        let activeCount = snap.players.filter(\.isActive).count
        let drawCount = activeCount <= 4 ? 15 : (activeCount <= 6 ? 12 : 10)
        let engineN = Scoring.engineTile(stop: min(currentStop, snap.length),
                                         rules: snap.startingEngine,
                                         length: snap.length)
        let allDone = snap.players.filter(\.isActive).allSatisfy { p in
            snap.scores.contains { $0.playerID == p.id && $0.stop == currentStop }
        }

        VStack(spacing: 12) {
            // Round instructions when scoring is not open
            if !snap.scoringOpen && !allDone {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.muted)
                        Text("Waiting for tiles down...")
                            .font(theme.monoFont(size: 11))
                            .tracking(1.0)
                            .foregroundStyle(theme.muted)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("ENGINE")
                                .font(theme.monoFont(size: 9))
                                .tracking(1.4)
                                .foregroundStyle(theme.muted)
                            Text("\(engineN)|\(engineN)")
                                .font(theme.displayFont(size: 20))
                                .foregroundStyle(theme.brand)
                        }
                        if snap.startingEngine.isDrawToFind {
                            Text("Draw \(drawCount) dominoes. If no one has the \(engineN)|\(engineN), draw until it's found.")
                                .font(theme.monoFont(size: 11))
                                .foregroundStyle(theme.ink)
                        } else {
                            Text("Remove the \(engineN)|\(engineN), then deal \(drawCount) dominoes each.")
                                .font(theme.monoFont(size: 11))
                                .foregroundStyle(theme.ink)
                        }
                    }
                    .padding(14)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.border, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 6)
            }

            // Standings
            VStack(alignment: .leading, spacing: 8) {
                Text("STANDINGS")
                    .font(theme.monoFont(size: 10))
                    .tracking(2)
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, 6)

                VStack(spacing: 0) {
                    ForEach(Array(standings.enumerated()), id: \.element.player.id) { index, entry in
                        let hasSubmitted = snap.scores.contains {
                            $0.playerID == entry.player.id && $0.stop == currentStop
                        }
                        let isMe = entry.player.id == myID

                        Button {
                            selectedSnapshotPlayer = entry.player
                        } label: {
                            HStack(spacing: 10) {
                                Text(snapshotRankLabel(entry.place))
                                    .font(theme.displayFont(size: 16))
                                    .frame(width: 32, alignment: .center)

                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(entry.player.name)
                                            .font(theme.monoFont(size: 13))
                                            .fontWeight(isMe ? .bold : .regular)
                                            .foregroundStyle(theme.ink)
                                        if isMe {
                                            Text("YOU")
                                                .font(theme.monoFont(size: 8))
                                                .tracking(1.2)
                                                .foregroundStyle(theme.accent)
                                        }
                                    }
                                }

                                Spacer()

                                if hasSubmitted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.green)
                                }

                                Text("\(entry.total)")
                                    .font(theme.displayFont(size: 18))
                                    .foregroundStyle(entry.place == 1 ? theme.brand : theme.ink)
                                    .frame(minWidth: 36, alignment: .trailing)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(theme.muted.opacity(0.5))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .opacity(entry.player.isActive ? 1.0 : 0.4)
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
        }
    }

    private func snapshotRankLabel(_ place: Int) -> String {
        switch place {
        case 1: return "\u{1F947}"
        case 2: return "\u{1F948}"
        case 3: return "\u{1F949}"
        default: return "\(place)th"
        }
    }

    @ViewBuilder
    private func snapshotPhotoGallery(snap: GameSnapshot) -> some View {
        let stops = Set(snap.recentCaptures.map(\.stop)).sorted()
        if !stops.isEmpty {
            ForEach(stops, id: \.self) { stop in
                let capsForStop = snap.recentCaptures.filter { $0.stop == stop }
                if !capsForStop.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("STOP \(stop) · CAMERA ROLL")
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

    private func snapshotPhotoTile(cap: CaptureManifestEntry, snap: GameSnapshot) -> some View {
        let playerName = snap.players.first(where: { $0.id == cap.playerID })?.name ?? ""
        let score = snap.scores.first(where: { $0.playerID == cap.playerID && $0.stop == cap.stop })
        let photoData = coordinator.netSession.cachedPhoto(for: cap.id)
        return Button {
            if let photoData {
                selectedPhotoData = photoData
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let photoData, let img = UIImage(data: photoData) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        theme.cardBg
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(theme.muted.opacity(0.6))
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
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(photoData == nil)
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
                showLeaveConfirm = true
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

    @State private var showLeaveConfirm = false

    private func leaveGame() {
        coordinator.netSession.leave()
        coordinator.goHome()
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

    /// The designated successor is the lowest-seat active player who is NOT the
    /// original conductor (seat 0). Only they see "Become Host", avoiding two
    /// players claiming the host role at once.
    private var isDesignatedSuccessor: Bool {
        guard let snap = coordinator.netSession.latestSnapshot,
              let myID = coordinator.netSession.myPlayerID else { return false }
        let successor = snap.players
            .filter { $0.isActive && !$0.isYou }
            .sorted { $0.seat < $1.seat }
            .first
        return successor?.id == myID
    }

    private var hostEndedOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Host left the game")
                    .font(theme.displayFont(size: 22))
                    .foregroundStyle(theme.ink)
                if isDesignatedSuccessor && !(coordinator.netSession.latestSnapshot?.isFinished ?? false) {
                    Text("You can take over as conductor to keep the game going.")
                        .font(theme.monoFont(size: 11))
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                    Button {
                        becomeHost()
                    } label: {
                        Text("BECOME HOST")
                            .font(theme.monoFont(size: 12))
                            .tracking(1.4)
                            .foregroundStyle(theme.ctaText)
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                    }
                }
                Button {
                    // Don't clear activeJoin — if a successor takes over with
                    // the same room code, the rejoin banner lets them return.
                    coordinator.netSession.leave()
                    coordinator.goHome()
                } label: {
                    Text("BACK TO HOME")
                        .font(theme.monoFont(size: 12))
                        .tracking(1.4)
                        .foregroundStyle(theme.brand)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                }
            }
            .padding(24)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 28)
        }
    }

    private func becomeHost() {
        let session = coordinator.netSession
        guard let snap = session.latestSnapshot,
              let myID = session.myPlayerID else { return }

        // Rebuild the game locally with this player as the conductor.
        guard let game = try? GamePersistence.reconstructForHostMigration(
            in: modelContext,
            snapshot: snap,
            newConductorID: myID,
            photoCache: session.allCachedPhotos,
            photoStore: coordinator.photoStore
        ) else { return }

        // Tear down the joiner session, then start hosting with the SAME room
        // code so the other players' reconnect logic finds us.
        session.leave()
        coordinator.settings.clearActiveJoin()
        let hostSnap = SnapshotBuilder.build(game: game, roomCode: snap.roomCode)
        session.startHosting(initialSnapshot: hostSnap)
        coordinator.openScoreboard(game)
    }

    private func lobbyView(snap: GameSnapshot) -> some View {
        let session = coordinator.netSession
        return ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 20)

                // Room code
                VStack(spacing: 4) {
                    Text("ROOM CODE")
                        .font(theme.monoFont(size: 10))
                        .tracking(2)
                        .foregroundStyle(theme.muted)
                    Text(snap.roomCode)
                        .font(theme.displayFont(size: 36))
                        .foregroundStyle(theme.brand)
                }

                // Game info
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("\(snap.length)")
                            .font(theme.displayFont(size: 22))
                            .foregroundStyle(theme.ink)
                        Text("STOPS")
                            .font(theme.monoFont(size: 9))
                            .tracking(1.5)
                            .foregroundStyle(theme.muted)
                    }
                    VStack(spacing: 2) {
                        let n = Scoring.engineTile(stop: 1, rules: snap.startingEngine, length: snap.length)
                        Text("\(n)|\(n)")
                            .font(theme.displayFont(size: 22))
                            .foregroundStyle(theme.ink)
                        Text("ENGINE")
                            .font(theme.monoFont(size: 9))
                            .tracking(1.5)
                            .foregroundStyle(theme.muted)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border, lineWidth: 1))

                // Players in lobby
                VStack(alignment: .leading, spacing: 8) {
                    Text("PLAYERS")
                        .font(theme.monoFont(size: 10))
                        .tracking(2)
                        .foregroundStyle(theme.muted)

                    ForEach(snap.players.sorted(by: { $0.seat < $1.seat }), id: \.id) { p in
                        let claim = snap.claims.first(where: { $0.playerID == p.id })
                        let isMe = p.id == session.myPlayerID
                        HStack(spacing: 10) {
                            if let data = claim?.photoJPEG ?? session.avatarCache[p.id],
                               let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(theme.border, lineWidth: 1))
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(theme.subBg)
                                        .frame(width: 36, height: 36)
                                        .overlay(Circle().stroke(theme.border, lineWidth: 1))
                                    Text(String(p.name.prefix(2)).uppercased())
                                        .font(theme.displayFont(size: 12))
                                        .foregroundStyle(theme.ink)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(claim?.displayName ?? p.name)
                                        .font(theme.displayFont(size: 16))
                                        .foregroundStyle(theme.ink)
                                    if isMe {
                                        Text("YOU")
                                            .font(theme.monoFont(size: 8))
                                            .tracking(1.2)
                                            .foregroundStyle(theme.accent)
                                    }
                                }
                                Text(p.isYou ? "Conductor" : "Ready")
                                    .font(theme.monoFont(size: 9))
                                    .foregroundStyle(theme.muted)
                            }
                            Spacer()
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }
                        .padding(10)
                        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isMe ? theme.brand.opacity(0.5) : theme.borderLight, lineWidth: isMe ? 1.5 : 1)
                        )
                    }
                }
                .padding(.horizontal, 16)

                // Waiting message
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(theme.brand)
                    Text("Waiting for the conductor to depart...")
                        .font(theme.monoFont(size: 12))
                        .tracking(1.4)
                        .foregroundStyle(theme.muted)
                }
                .padding(.top, 8)

                Spacer().frame(height: 20)
            }
        }
    }

    @ViewBuilder
    private func celebrationView(snap: GameSnapshot, winnerID: UUID) -> some View {
        let winner = snap.players.first(where: { $0.id == winnerID })
        let scoresByPlayer = Dictionary(grouping: snap.scores, by: { $0.playerID })
        let totals = Dictionary(uniqueKeysWithValues: snap.players.map { p in
            (p.id, (scoresByPlayer[p.id] ?? []).reduce(0) { $0 + $1.pips })
        })
        let winnerPips = totals[winnerID] ?? 0
        let sorted = snap.players
            .map { ($0, totals[$0.id] ?? 0) }
            .sorted { $0.1 < $1.1 }
        // Pre-compute places with tie handling
        let standings: [(player: PlayerSnapshot, total: Int, place: Int)] = {
            var result: [(PlayerSnapshot, Int, Int)] = []
            var lastTotal: Int? = nil
            var lastPlace = 0
            for (index, pair) in sorted.enumerated() {
                let (p, t) = pair
                if lastTotal == nil || lastTotal != t {
                    lastPlace = index + 1
                    lastTotal = t
                }
                result.append((p, t, lastPlace))
            }
            return result
        }()

        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 48)

                    Image(systemName: "trophy.fill")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundStyle(theme.brand)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                    Spacer().frame(height: 16)

                    Text(winner?.name ?? "Winner")
                        .font(theme.displayFont(size: 44))
                        .foregroundStyle(theme.brand)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 24)

                    Spacer().frame(height: 4)

                    Text("\(winnerPips) pips")
                        .font(theme.monoFont(size: 14))
                        .foregroundStyle(theme.muted)

                    Spacer().frame(height: 32)

                    VStack(spacing: 0) {
                        ForEach(standings.indices, id: \.self) { i in
                            let s = standings[i]
                            HStack {
                                Text("\(s.place).")
                                    .font(theme.displayFont(size: 18))
                                    .foregroundStyle(theme.ink)
                                    .frame(width: 36, alignment: .leading)
                                Text(s.player.name)
                                    .font(theme.displayFont(size: 18))
                                    .foregroundStyle(theme.ink)
                                Spacer()
                                Text("\(s.total)")
                                    .font(theme.displayFont(size: 22))
                                    .foregroundStyle(theme.ink)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            if i < standings.count - 1 {
                                Rectangle().fill(theme.borderLight).frame(height: 1)
                            }
                        }
                    }
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(theme.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 32)

                    Button {
                        coordinator.settings.clearActiveJoin()
                        coordinator.netSession.leave()
                        coordinator.goHome()
                    } label: {
                        Text("BACK TO HOME")
                    }
                    .appPrimaryStyle()
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 24)
                }
            }
            ConfettiView()
                .id(confettiID)
                .ignoresSafeArea()
                .onAppear { confettiID = UUID() }
        }
    }
}

/// Snapshot-driven golf-card table mirroring the host's `ScoreCardTable`
/// but reading from `GameSnapshot` instead of SwiftData models.
struct SnapshotTable: View {
    let snap: GameSnapshot
    var myPlayerID: UUID? = nil
    var avatarCache: [UUID: Data] = [:]
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
                if let data = claim?.photoJPEG ?? avatarCache[player.id],
                   let img = UIImage(data: data) {
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

private struct SpectatorPhotoZoomOverlay: View {
    let photoData: Data?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let photoData, let img = UIImage(data: photoData) {
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
            }
        }
    }
}

private struct SnapshotPlayerDetailSheet: View {
    let player: PlayerSnapshot
    let snap: GameSnapshot
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let scoresByPlayer = Dictionary(grouping: snap.scores, by: { $0.playerID })
        let playerScores = scoresByPlayer[player.id] ?? []
        let total = playerScores.filter { !$0.excluded }.reduce(0) { $0 + $1.pips }

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
                    Text(player.name)
                        .font(theme.displayFont(size: 16))
                        .foregroundStyle(theme.ink)
                    Text("\u{00B7} \(total) total")
                        .font(theme.monoFont(size: 13))
                        .foregroundStyle(theme.muted)
                    Spacer()
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
                        ForEach(1...snap.length, id: \.self) { stopNum in
                            let engineN = Scoring.engineTile(
                                stop: stopNum,
                                rules: snap.startingEngine,
                                length: snap.length
                            )
                            let score = playerScores.first(where: { $0.stop == stopNum })
                            let isCurrent = stopNum == snap.currentStop

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

                                GeometryReader { geo in
                                    let dotCount = max(1, Int(geo.size.width / 5))
                                    Text(String(repeating: ".", count: dotCount))
                                        .font(theme.monoFont(size: 11))
                                        .foregroundStyle(theme.borderLight)
                                        .lineLimit(1)
                                }
                                .frame(height: 16)

                                if let score {
                                    let pips = score.excluded ? 0 : score.pips
                                    Text("\(pips)")
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

                            if stopNum < snap.length {
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
