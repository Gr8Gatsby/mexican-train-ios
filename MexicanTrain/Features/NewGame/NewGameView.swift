import SwiftUI
import SwiftData

/// New-game "lobby": creates a draft Game immediately, broadcasts it on the
/// local network so people at the table can scan a QR / type a code to join
/// as players (their names/photos populate the slot list live), and lets the
/// conductor manually add players for anyone without a phone. Tapping Start
/// flips the game live and routes to the scoreboard. Backing out deletes the
/// draft.
struct NewGameView: View {
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @State private var game: Game?
    @State private var length: Int = 13
    @State private var engine: StartingEngine = .traditional
    @State private var roomCode: String = ""
    @State private var manualName: String = ""
    @State private var error: String?
    @State private var renamingPlayer: Player?
    @State private var renameDraft: String = ""

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            if let g = game {
                Color.clear.hostBroadcaster(game: g)
            }
            VStack(spacing: 0) {
                AppHeaderBar(
                    style: .push,
                    title: "New game",
                    onLeading: { cancelAndExit() }
                )
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        broadcastBlock
                        section("PLAYERS · TAP TO REMOVE") { playerList }
                        section("ADD PLAYER (NO PHONE)") { manualAdd }
                        section("GAME LENGTH") { lengthPicker }
                        section("STARTING ENGINE") { enginePicker }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        .task {
            await setup()
        }
        .onDisappear {
            // If the user navigated away without starting, clean up.
            if let g = game, g.currentStopIndex == 0 {
                coordinator.netSession.stopHosting()
                try? GamePersistence.delete(game: g, in: context, photoStore: coordinator.photoStore)
            }
        }
    }

    @ViewBuilder
    private var broadcastBlock: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ROOM CODE")
                        .font(theme.monoFont(size: 9))
                        .tracking(1.8)
                        .foregroundStyle(theme.muted)
                    Text(roomCode.isEmpty ? "----" : roomCode)
                        .font(theme.displayFont(size: 40, relativeTo: .title))
                        .tracking(6)
                        .foregroundStyle(theme.brand)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Share with the table to add players.")
                        .font(theme.monoFont(size: 10))
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !roomCode.isEmpty {
                    QRCodeView(payload: JoinURL.encode(roomCode: roomCode).absoluteString)
                        .frame(width: 110, height: 110)
                        .padding(6)
                        .background(.white, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.border, lineWidth: 1)
                        )
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "wifi")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.muted)
                    .accessibilityHidden(true)
                Text("\(coordinator.netSession.connectedPeerCount) connected on local network")
                    .font(theme.monoFont(size: 10))
                    .foregroundStyle(theme.muted)
                Spacer()
            }
        }
        .padding(14)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(theme.monoFont(size: 11))
                .tracking(2)
                .foregroundStyle(theme.muted)
            content()
        }
    }

    private var playerList: some View {
        VStack(spacing: 6) {
            if let g = game {
                ForEach(g.sortedPlayers) { p in
                    HStack(spacing: 10) {
                        avatar(for: p)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(theme.border, lineWidth: 1))
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 4) {
                                Text(p.name.isEmpty ? "(no name)" : p.name)
                                    .font(theme.displayFont(size: 16))
                                    .foregroundStyle(theme.ink)
                                if p.isYou {
                                    Text("CONDUCTOR")
                                        .font(theme.monoFont(size: 8))
                                        .tracking(1.2)
                                        .foregroundStyle(theme.accent)
                                }
                                if p.isYou {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 10))
                                        .foregroundStyle(theme.muted)
                                }
                            }
                            Text(p.isYou ? "You · tap to rename" : (p.avatarFilename != nil ? "Joined from phone" : "Manual entry"))
                                .font(theme.monoFont(size: 9))
                                .foregroundStyle(theme.muted)
                        }
                        Spacer()
                        if !p.isYou {
                            Button { removePlayer(p) } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(theme.muted)
                            }
                            .accessibilityLabel("Remove \(p.name)")
                        }
                    }
                    .padding(10)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.borderLight, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard p.isYou else { return }
                        renameDraft = p.name
                        renamingPlayer = p
                    }
                }
            }
        }
        .alert("Your name", isPresented: Binding(
            get: { renamingPlayer != nil },
            set: { if !$0 { renamingPlayer = nil } }
        )) {
            TextField("Name", text: $renameDraft)
                .textInputAutocapitalization(.words)
            Button("Save") {
                if let p = renamingPlayer {
                    let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        p.name = trimmed
                        try? context.save()
                    }
                }
                renamingPlayer = nil
            }
            Button("Cancel", role: .cancel) { renamingPlayer = nil }
        } message: {
            Text("Other phones at the table will see this name.")
        }
    }

    @ViewBuilder
    private func avatar(for player: Player) -> some View {
        if let f = player.avatarFilename,
           let g = game,
           let img = coordinator.photoStore.load(filename: f, gameID: g.id) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                theme.subBg
                Text(initials(of: player.name))
                    .font(theme.displayFont(size: 12))
                    .foregroundStyle(theme.ink)
            }
        }
    }

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var manualAdd: some View {
        HStack(spacing: 8) {
            TextField("Player name", text: $manualName)
                .textInputAutocapitalization(.words)
                .font(theme.monoFont(size: 14))
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.borderLight, lineWidth: 1)
                )
            Button {
                addManualPlayer()
            } label: {
                Text("ADD")
            }
            .appPillStyle(prominent: true)
            .disabled(!canAddManual)
            .opacity(canAddManual ? 1 : 0.55)
        }
    }

    private var canAddManual: Bool {
        !manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (game?.players.count ?? 0) < 8
    }

    private var lengthPicker: some View {
        HStack(spacing: 8) {
            ForEach([7, 10, 13], id: \.self) { n in
                Button { length = n } label: {
                    Text("\(n)")
                        .font(theme.displayFont(size: 22))
                        .foregroundStyle(length == n ? theme.ctaText : theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(length == n ? theme.cta : theme.cardBg,
                                    in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                                .stroke(theme.border, lineWidth: 1)
                        )
                }
            }
        }
    }

    private var enginePicker: some View {
        VStack(spacing: 6) {
            ForEach(StartingEngine.allCases) { option in
                Button { engine = option } label: {
                    HStack(alignment: .top) {
                        Image(systemName: engine == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(engine == option ? theme.brand : theme.muted)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.displayName)
                                .font(theme.displayFont(size: 16))
                                .foregroundStyle(theme.ink)
                            Text(option.description)
                                .font(theme.monoFont(size: 10))
                                .tracking(1)
                                .foregroundStyle(theme.muted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(engine == option ? theme.brand : theme.borderLight,
                                    lineWidth: engine == option ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let error {
                Text(error)
                    .font(theme.monoFont(size: 11))
                    .foregroundStyle(theme.brand)
            }
            Button(action: start) { Text("START GAME") }
                .appPrimaryStyle(enabled: canStart)
                .disabled(!canStart)
        }
        .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 10)
        .background(theme.subBg)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var canStart: Bool {
        guard let g = game else { return false }
        if g.players.count < 1 || g.players.count > 8 { return false }
        // Names: non-empty + unique (case-insensitive).
        let names = g.players.map { $0.name.lowercased().trimmingCharacters(in: .whitespaces) }
        if names.contains(where: \.isEmpty) { return false }
        if Set(names).count != names.count { return false }
        return true
    }

    // MARK: - Lifecycle

    private func setup() async {
        // Reuse settings as starting defaults.
        length = settings.defaultLengthStops
        engine = settings.lastStartingEngine

        // Identity from device. `loadCurrentIdentity()` now returns nil for
        // generic strings like "iPhone 17", so we land on "Conductor" by
        // default — the conductor can tap their row to rename inline.
        let identity = await DeviceIdentity.loadCurrentIdentity()
        let conductorName: String = {
            if !settings.defaultYouName.isEmpty { return settings.defaultYouName }
            if let n = identity.displayName, !n.isEmpty { return n }
            return "Conductor"
        }()

        // Create the draft game with the conductor as Player 0. We mark
        // currentStopIndex = 0 to flag this as still-in-setup; tapping Start
        // moves it to 1.
        do {
            let g = try GamePersistence.createGame(
                in: context, length: length, startingEngine: engine,
                playerNames: [conductorName], youIndex: 0, name: nil
            )
            g.currentStopIndex = 0
            // Reuse the persisted "you" photo as the conductor's avatar so
            // the lobby shows their face immediately. Stored once per
            // game's photoStore namespace alongside captures.
            if let data = settings.defaultYouPhotoJPEG,
               let img = UIImage(data: data),
               let conductor = g.players.first(where: { $0.isYou }),
               let filename = try? coordinator.photoStore.save(
                image: img, gameID: g.id, captureID: conductor.id) {
                conductor.avatarFilename = filename
            }
            try context.save()
            game = g

            // Begin hosting and surface the room code so the QR can render.
            let code = RoomCode.generate()
            roomCode = code
            let snap = SnapshotBuilder.build(game: g, photoStore: coordinator.photoStore, roomCode: code)
            coordinator.netSession.onClaimReceived = { claim in
                handleClaim(claim)
            }
            coordinator.netSession.startHosting(initialSnapshot: snap)
        } catch {
            self.error = "Couldn't start lobby: \(error.localizedDescription)"
        }
    }

    private func handleClaim(_ claim: PlayerClaim) {
        guard let g = game else { return }
        // If the claim references an existing player, just update it.
        if let existing = g.players.first(where: { $0.id == claim.playerID }) {
            existing.name = claim.displayName
            if let photo = claim.photoJPEG, let img = UIImage(data: photo) {
                if let filename = try? coordinator.photoStore.save(image: img,
                                                                   gameID: g.id,
                                                                   captureID: existing.id) {
                    existing.avatarFilename = filename
                }
            }
            try? context.save()
            return
        }
        // Otherwise add a new Player slot.
        guard g.players.count < 8 else { return }
        let seat = (g.sortedPlayers.last?.seat ?? -1) + 1
        let player = Player(id: claim.playerID, name: claim.displayName, seat: seat)
        player.game = g
        context.insert(player)
        if let photo = claim.photoJPEG, let img = UIImage(data: photo),
           let filename = try? coordinator.photoStore.save(image: img,
                                                           gameID: g.id,
                                                           captureID: player.id) {
            player.avatarFilename = filename
        }
        try? context.save()
    }

    private func addManualPlayer() {
        guard let g = game else { return }
        let trimmed = manualName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, g.players.count < 8 else { return }
        let seat = (g.sortedPlayers.last?.seat ?? -1) + 1
        let player = Player(name: trimmed, seat: seat)
        player.game = g
        context.insert(player)
        try? context.save()
        manualName = ""
    }

    private func removePlayer(_ player: Player) {
        context.delete(player)
        try? context.save()
    }

    private func start() {
        guard let g = game, canStart else { return }
        g.lengthStops = length
        g.startingEngineRaw = engine.rawValue
        g.currentStopIndex = 1
        try? context.save()
        settings.defaultLengthStops = length
        settings.lastStartingEngine = engine
        if let conductor = g.players.first(where: { $0.isYou }) {
            settings.defaultYouName = conductor.name
        }
        coordinator.netSession.onClaimReceived = nil  // scoreboard owns broadcast from here
        coordinator.openScoreboard(g)
    }

    private func cancelAndExit() {
        if let g = game {
            coordinator.netSession.stopHosting()
            coordinator.netSession.onClaimReceived = nil
            try? GamePersistence.delete(game: g, in: context, photoStore: coordinator.photoStore)
        }
        coordinator.goHome()
    }
}
