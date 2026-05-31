import SwiftUI
import SwiftData

/// New-game flow. Two explicit phases:
///
/// 1. **Rules** — conductor sets game length, starting engine, and family
///    house rules. Nothing is broadcast yet; the table can't see the room
///    code. Tapping "CALL FOR BOARDING" starts hosting and advances to
///    phase 2.
/// 2. **Lobby** — QR + room code are visible, joiners can claim slots, the
///    conductor can add phone-less players. "Edit rules" sends the
///    conductor back to phase 1 *without* stopping hosting, so any tweak
///    is re-pushed to peers via the snapshot fingerprint.
///
/// Back from .rules deletes the draft and exits. Back from .lobby returns
/// to .rules (host keeps running, room code stays put).
struct NewGameView: View {
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @State private var game: Game?
    @State private var phase: Phase = .rules
    @State private var roomCode: String = ""
    @State private var manualName: String = ""
    @State private var error: String?
    @State private var renamingPlayer: Player?
    @State private var renameDraft: String = ""

    enum Phase { case rules, lobby }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            if let g = game {
                // Broadcaster only fires when the net session is actually
                // hosting, so leaving it mounted across phases is safe.
                Color.clear.hostBroadcaster(game: g)
            }
            VStack(spacing: 0) {
                AppHeaderBar(
                    style: .push,
                    title: phase == .rules ? "Set the rules" : "Call for boarding",
                    onLeading: { onBack() }
                )
                ScrollView {
                    Group {
                        if let g = game {
                            switch phase {
                            case .rules: rulesContent(game: g)
                            case .lobby: lobbyContent(game: g)
                            }
                        } else {
                            ProgressView()
                                .padding(40)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 160)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)
                footer
            }
        }
        .task { await setup() }
        .onDisappear {
            // If the user navigated away without departing, clean up.
            // Guard: only if still in setup (stop 0) AND not transitioning
            // to scoreboard (which sets currentStopIndex = 1).
            if let g = game, g.currentStopIndex == 0, g.finishedAt == nil,
               coordinator.netSession.role == .host {
                coordinator.netSession.stopHosting()
                try? GamePersistence.delete(game: g, in: context, photoStore: coordinator.photoStore)
            }
        }
    }

    // MARK: - Phase: rules

    @ViewBuilder
    private func rulesContent(game: Game) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIntro(
                step: "STEP 1 OF 2",
                title: "Set the rules",
                body: "Pick the game length, starting engine, and any family rules. We'll start broadcasting on the next step."
            )
            section("GAME LENGTH") { lengthPicker(game: game) }
            section("STARTING ENGINE") { enginePicker(game: game) }
            section("HOUSE RULES") {
                HouseRulesSection(game: game) { try? context.save() }
            }
        }
    }

    private func lengthPicker(game: Game) -> some View {
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
                                .stroke(theme.border, lineWidth: 1)
                        )
                }
            }
        }
    }

    private func enginePicker(game: Game) -> some View {
        VStack(spacing: 6) {
            ForEach(StartingEngine.allCases) { option in
                Button {
                    game.startingEngineRaw = option.rawValue
                    try? context.save()
                } label: {
                    HStack(alignment: .top) {
                        Image(systemName: game.startingEngine == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(game.startingEngine == option ? theme.brand : theme.muted)
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
                            .stroke(game.startingEngine == option ? theme.brand : theme.borderLight,
                                    lineWidth: game.startingEngine == option ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Phase: lobby

    @ViewBuilder
    private func lobbyContent(game: Game) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIntro(
                step: "STEP 2 OF 2",
                title: "Call for boarding",
                body: "Share the room code so the table can join, or add anyone without a phone manually."
            )
            broadcastBlock
            section("PLAYERS · TAP TO RENAME") { playerList }
            section("ADD PLAYER (NO PHONE)") { manualAdd }
            editRulesShortcut(game: game)
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
                Text("\(coordinator.netSession.playerClaims.count) joined on local network")
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

    private func editRulesShortcut(game: Game) -> some View {
        Button {
            withAnimation { phase = .rules }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                Text("EDIT RULES")
                    .font(theme.monoFont(size: 11))
                    .fontWeight(.semibold)
                    .tracking(1.4)
                Spacer()
                rulesSummary(game: game)
                    .font(theme.monoFont(size: 10))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(theme.brand)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.borderLight, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit rules")
    }

    private func rulesSummary(game: Game) -> Text {
        var parts: [String] = ["\(game.lengthStops) stops", game.startingEngine.displayName]
        if game.goingOutBonus != .none { parts.append("bonus \(game.goingOutBonus.displayName)") }
        if game.doublesPenaltyPips > 0 { parts.append("+\(game.doublesPenaltyPips) dbl") }
        if let d = game.drawCountOverride { parts.append("draw \(d)") }
        if game.blockedRoundCapEnabled { parts.append("blocked cap") }
        return Text(parts.joined(separator: " · "))
    }

    // MARK: - Shared list/manual-add pieces

    private var playerList: some View {
        let claims = coordinator.netSession.playerClaims
        return VStack(spacing: 6) {
            if let g = game {
                ForEach(g.sortedPlayers) { p in
                    let inLobby = !p.isYou && claims[p.id] != nil
                    HStack(spacing: 10) {
                        avatar(for: p)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(theme.border, lineWidth: 1))
                            .overlay(alignment: .bottomTrailing) {
                                if inLobby {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 10, height: 10)
                                        .overlay(Circle().stroke(theme.cardBg, lineWidth: 2))
                                        .offset(x: 2, y: 2)
                                }
                            }
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                Text(p.name.isEmpty ? "(no name)" : p.name)
                                    .font(theme.displayFont(size: 16))
                                    .foregroundStyle(theme.ink)
                                if p.isYou {
                                    Text("CONDUCTOR")
                                        .font(theme.monoFont(size: 8))
                                        .tracking(1.2)
                                        .foregroundStyle(theme.accent)
                                }
                                if inLobby {
                                    Text("IN LOBBY")
                                        .font(theme.monoFont(size: 8))
                                        .tracking(1.2)
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(p.isYou ? "Tap to rename"
                                 : (inLobby ? "Waiting for you to depart"
                                    : (p.avatarFilename != nil ? "Joined · tap to rename" : "Tap to rename")))
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
                            .stroke(inLobby ? Color.green.opacity(0.5) : theme.borderLight,
                                    lineWidth: inLobby ? 1.5 : 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        renameDraft = p.name
                        renamingPlayer = p
                    }
                }
            }
        }
        .alert("Player name", isPresented: Binding(
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
            Text("This name appears on the scoreboard.")
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
                .onChange(of: manualName) { _, new in
                    if new.count > 20 { manualName = String(new.prefix(20)) }
                }
                .submitLabel(.done)
                .onSubmit { addManualPlayer() }
            Button {
                addManualPlayer()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("ADD")
                        .font(theme.monoFont(size: 13))
                        .fontWeight(.bold)
                        .tracking(1.6)
                }
                .foregroundStyle(theme.ctaText)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(canAddManual ? theme.cta : theme.muted,
                            in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!canAddManual)
            .opacity(canAddManual ? 1 : 0.65)
            .accessibilityLabel("Add player")
        }
    }

    private var canAddManual: Bool {
        !manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (game?.players.count ?? 0) < 8
    }

    // MARK: - Layout helpers

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

    private func stepIntro(step: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(step)
                .font(theme.monoFont(size: 9))
                .tracking(1.8)
                .foregroundStyle(theme.accent)
            Text(title)
                .font(theme.displayFont(size: 22))
                .foregroundStyle(theme.brand)
            Text(body)
                .font(theme.monoFont(size: 11))
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer (phase-dependent)

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .rules: rulesFooter
        case .lobby: lobbyFooter
        }
    }

    private var rulesFooter: some View {
        VStack(spacing: 8) {
            if let error {
                Text(error)
                    .font(theme.monoFont(size: 11))
                    .foregroundStyle(theme.brand)
            }
            Button(action: callForBoarding) {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .semibold))
                    Text("CALL FOR BOARDING")
                }
            }
            .appPrimaryStyle(enabled: game != nil)
            .disabled(game == nil)
            Text("Locks in the rules and starts broadcasting so the table can join.")
                .font(theme.monoFont(size: 10))
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 10)
        .background(theme.subBg)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var lobbyFooter: some View {
        let lobbyCount = coordinator.netSession.playerClaims.count
        return VStack(spacing: 8) {
            if let error {
                Text(error)
                    .font(theme.monoFont(size: 11))
                    .foregroundStyle(theme.brand)
            }
            if (game?.players.count ?? 0) < 2 {
                Text("Add at least one more player to start")
                    .font(theme.monoFont(size: 11))
                    .foregroundStyle(theme.muted)
            } else if lobbyCount > 0 {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("\(lobbyCount) \(lobbyCount == 1 ? "player is" : "players are") waiting in the lobby")
                        .font(theme.monoFont(size: 11))
                        .foregroundStyle(theme.ink)
                }
            }
            Button(action: start) { Text("DEPART") }
                .appPrimaryStyle(enabled: canStart)
                .disabled(!canStart)
            if canStart {
                Text("Locks the lineup. You'll score each stop on the next screen.")
                    .font(theme.monoFont(size: 10))
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 10)
        .background(theme.subBg)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var canStart: Bool {
        guard let g = game else { return false }
        if g.players.count < 2 || g.players.count > 8 { return false }
        // Names: non-empty + unique (case-insensitive).
        let names = g.players.map { $0.name.lowercased().trimmingCharacters(in: .whitespaces) }
        if names.contains(where: \.isEmpty) { return false }
        if Set(names).count != names.count { return false }
        return true
    }

    // MARK: - Lifecycle

    private func setup() async {
        // Identity from device. `loadCurrentIdentity()` returns nil for
        // generic strings like "iPhone 17", so we land on "Conductor" by
        // default — the conductor can tap their row to rename.
        let identity = await DeviceIdentity.loadCurrentIdentity()
        let conductorName: String = {
            if !settings.defaultYouName.isEmpty { return settings.defaultYouName }
            if let n = identity.displayName, !n.isEmpty { return n }
            return "Conductor"
        }()

        // Create the draft game with the conductor as Player 0. We mark
        // currentStopIndex = 0 to flag this as still-in-setup; DEPART moves
        // it to 1. Defaults come from AppSettings; the conductor can change
        // them in the rules phase before broadcasting.
        do {
            let g = try GamePersistence.createGame(
                in: context,
                length: settings.defaultLengthStops,
                startingEngine: settings.lastStartingEngine,
                playerNames: [conductorName], youIndex: 0, name: nil
            )
            g.currentStopIndex = 0
            if let data = settings.defaultYouPhotoJPEG,
               let img = UIImage(data: data),
               let conductor = g.players.first(where: { $0.isYou }),
               let filename = try? coordinator.photoStore.save(
                image: img, gameID: g.id, captureID: conductor.id) {
                conductor.avatarFilename = filename
            }
            try context.save()
            game = g
            // Do NOT start hosting yet — wait for "Call for boarding".
        } catch {
            self.error = "Couldn't create draft: \(error.localizedDescription)"
        }
    }

    private func callForBoarding() {
        guard let g = game else { return }
        // Persist current selections as defaults for next time.
        settings.defaultLengthStops = g.lengthStops
        settings.lastStartingEngine = g.startingEngine
        // Begin hosting and surface the room code so the QR can render.
        let code = RoomCode.generate()
        roomCode = code
        let snap = SnapshotBuilder.build(game: g, roomCode: code)
        coordinator.netSession.onClaimReceived = { claim in
            handleClaim(claim)
        }
        coordinator.netSession.startHosting(initialSnapshot: snap)
        withAnimation { phase = .lobby }
    }

    private func onBack() {
        switch phase {
        case .rules:
            cancelAndExit()
        case .lobby:
            // Returning to rules keeps hosting active so the room code
            // stays valid for joiners already on the radar.
            withAnimation { phase = .rules }
        }
    }

    private func handleClaim(_ claim: PlayerClaim) {
        guard let g = game else { return }
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
        g.currentStopIndex = 1
        try? context.save()
        if let conductor = g.players.first(where: { $0.isYou }),
           conductor.name != "Conductor" {
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

// MARK: - House rules picker

/// Reusable rules picker used in the new-game flow's rules phase and in the
/// mid-game `EditRulesSheet`. Writes directly to the bound `Game`; the
/// `onChange` closure lets the caller persist + re-broadcast as needed.
struct HouseRulesSection: View {
    @Bindable var game: Game
    var onChange: () -> Void = {}

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 16) {
            rule(title: "Going-out bonus",
                 description: "Subtract from the round score when a player empties their hand.") {
                segmented(
                    options: GoingOutBonus.allCases.map { ($0.rawValue, $0.displayName) },
                    selection: Binding(
                        get: { game.goingOutBonusRaw },
                        set: { game.goingOutBonusRaw = $0; onChange() }
                    )
                )
            }
            divider
            rule(title: "Doubles penalty",
                 description: "Add to your round score if you can't satisfy a double you played.") {
                segmented(
                    options: DoublesPenalty.presetOptions.map { ($0, $0 == 0 ? "None" : "+\($0)") },
                    selection: Binding(
                        get: { game.doublesPenaltyPips },
                        set: { game.doublesPenaltyPips = $0; onChange() }
                    )
                )
            }
            divider
            rule(title: "Draw count",
                 description: "Tiles each player draws to start a round.") {
                drawCountPicker
            }
            divider
            rule(title: "Double-blank penalty",
                 description: "Add to your round score if you're caught with the 0|0 tile.") {
                segmented(
                    options: DoubleBlankPenalty.presetOptions.map { ($0, $0 == 0 ? "None" : "+\($0)") },
                    selection: Binding(
                        get: { game.doubleBlankPenaltyPips },
                        set: { game.doubleBlankPenaltyPips = $0; onChange() }
                    )
                )
            }
            divider
            rule(title: "Doubles count double",
                 description: "Doubles left in hand count 2× their pip value (a 6|6 counts as 24, not 12).") {
                Toggle(isOn: Binding(
                    get: { game.doublesCountDouble },
                    set: { game.doublesCountDouble = $0; onChange() }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                .tint(theme.accent)
            }
            divider
            rule(title: "Any-blank penalty",
                 description: "Each blank tile half left in hand counts as the chosen value instead of 0.") {
                segmented(
                    options: AnyBlankPenalty.presetOptions.map { ($0, $0 == 0 ? "None" : "+\($0)") },
                    selection: Binding(
                        get: { game.anyBlankPenaltyPips },
                        set: { game.anyBlankPenaltyPips = $0; onChange() }
                    )
                )
            }
            divider
            rule(title: "Blocked-round cap",
                 description: "When nobody goes out, set the lowest hand to 0 instead.") {
                Toggle(isOn: Binding(
                    get: { game.blockedRoundCapEnabled },
                    set: { game.blockedRoundCapEnabled = $0; onChange() }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                .tint(theme.accent)
            }
        }
        .padding(14)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle().fill(theme.borderLight).frame(height: 1)
    }

    @ViewBuilder
    private var drawCountPicker: some View {
        // Options: Auto, then the four preset draw counts.
        let options: [(Int?, String)] = [(Optional<Int>.none, "Auto")] +
            DrawCount.presetOptions.map { (Optional($0), "\($0)") }
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let isSelected = opt.0 == game.drawCountOverride
                Button {
                    game.drawCountOverride = opt.0
                    onChange()
                } label: {
                    Text(opt.1)
                        .font(theme.monoFont(size: 12))
                        .fontWeight(.semibold)
                        .frame(minWidth: 32, minHeight: 32)
                        .padding(.horizontal, 8)
                        .foregroundStyle(isSelected ? theme.ctaText : theme.ink)
                        .background(isSelected ? theme.cta : theme.subBg,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func rule<Control: View>(title: String, description: String,
                                     @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(theme.displayFont(size: 15))
                    .foregroundStyle(theme.ink)
                Spacer()
                control()
            }
            Text(description)
                .font(theme.monoFont(size: 10))
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func segmented<T: Hashable>(
        options: [(T, String)],
        selection: Binding<T>
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let isSelected = opt.0 == selection.wrappedValue
                Button {
                    selection.wrappedValue = opt.0
                } label: {
                    Text(opt.1)
                        .font(theme.monoFont(size: 12))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .foregroundStyle(isSelected ? theme.ctaText : theme.ink)
                        .background(isSelected ? theme.cta : theme.subBg,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
