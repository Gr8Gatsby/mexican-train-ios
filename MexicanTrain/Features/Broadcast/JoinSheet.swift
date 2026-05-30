import SwiftUI
import PhotosUI
import UIKit

struct JoinSheet: View {
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var initialCode: String?

    @State private var code: String = ""
    @State private var prefill: ContactPrefill?
    @State private var editedName: String = ""
    @State private var showScanner: Bool = false
    @State private var scannerHint: String?
    @State private var pickerItem: PhotosPickerItem?
    /// User-picked photo (compressed, ≤ 32 KB). When set, takes precedence
    /// over the silent Contacts Me-card photo for the outgoing claim.
    @State private var pickedPhotoData: Data?
    /// Which train-color swatch is currently selected, if any. Setting
    /// this also writes a rendered JPEG into `pickedPhotoData`. Cleared
    /// whenever the user picks a real photo from their library.
    @State private var trainIndex: Int?
    @State private var directIP: String = ""
    @State private var directPort: String = "5111"
    @State private var didPrefillIP = false
    @State private var wantsToBoard = false

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                AppHeaderBar(
                    style: .modal,
                    title: "Join game",
                    onLeading: nil
                ) {
                    Button {
                        coordinator.netSession.leave()
                        dismiss()
                    } label: { Text("CANCEL") }
                        .appLinkStyle()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        identityBlock
                        if coordinator.netSession.joinState != .connected {
                            let hasNearby = !coordinator.netSession.availableHosts.isEmpty
                            hostList
                            if !hasNearby {
                                codeEntry
                            }
                            advancedSection
                        } else {
                            slotPicker
                        }
                    }
                    .padding(.horizontal, 16)
                }
                joinButton
            }
            .padding(.vertical, 12)
        }
        .onAppear {
            if coordinator.netSession.role != .joiner {
                coordinator.netSession.startBrowsing()
            }
            if let initialCode { code = initialCode }
            if !didPrefillIP, let savedIP = settings.activeJoinHostIP, !savedIP.isEmpty {
                directIP = savedIP
                didPrefillIP = true
            }
            Task { await loadPrefill() }
        }
        .sheet(isPresented: $showScanner) {
            qrScannerSheet
        }
    }

    private var qrScannerSheet: some View {
        ZStack(alignment: .topTrailing) {
            QRScannerView(
                onCode: { raw in
                    if let url = URL(string: raw), let parsed = JoinURL.decode(url) {
                        code = parsed
                        scannerHint = "Scanned code \(parsed). Boarding…"
                        showScanner = false
                        if let host = coordinator.netSession.availableHosts.first(where: { $0.roomCode == parsed }) {
                            wantsToBoard = true
                            coordinator.netSession.connect(to: host)
                        }
                    } else if RoomCode.isValid(raw) {
                        code = raw
                        scannerHint = "Scanned code \(raw). Boarding…"
                        showScanner = false
                        if let host = coordinator.netSession.availableHosts.first(where: { $0.roomCode == raw }) {
                            wantsToBoard = true
                            coordinator.netSession.connect(to: host)
                        }
                    } else {
                        scannerHint = "QR didn't contain a Mexican Train invite."
                    }
                },
                onError: { msg in
                    scannerHint = msg
                    showScanner = false
                }
            )
            .ignoresSafeArea()
            Button("Close") { showScanner = false }
                .font(theme.monoFont(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(16)
        }
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ROOM CODE")
                    .font(theme.monoFont(size: 12))
                    .tracking(2)
                    .foregroundStyle(theme.muted)
                Spacer()
                Button {
                    showScanner = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 14, weight: .semibold))
                        Text("SCAN QR")
                    }
                }
                .appPillStyle()
                .accessibilityLabel("Scan host QR code")
            }
            TextField("", text: $code, prompt: Text("0000").foregroundColor(theme.muted.opacity(0.4)))
                .keyboardType(.numberPad)
                .font(theme.displayFont(size: 40, relativeTo: .title))
                .tracking(6)
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.border, lineWidth: 1)
                )
                .onChange(of: code) { _, new in
                    code = String(new.filter(\.isNumber).prefix(4))
                }
            if let hint = scannerHint {
                Text(hint)
                    .font(theme.monoFont(size: 12))
                    .foregroundStyle(theme.brand)
            }
        }
    }

    @ViewBuilder
    private var hostList: some View {
        if !coordinator.netSession.availableHosts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("NEARBY")
                    .font(theme.monoFont(size: 12))
                    .tracking(2)
                    .foregroundStyle(theme.muted)
                ForEach(coordinator.netSession.availableHosts) { host in
                    Button {
                        code = host.roomCode
                        wantsToBoard = true
                        coordinator.netSession.connect(to: host)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(host.displayLabel)
                                    .font(theme.displayFont(size: 18))
                                    .foregroundStyle(theme.ink)
                                Text("\(host.playerCount) players · code \(host.roomCode)")
                                    .font(theme.monoFont(size: 12))
                                    .foregroundStyle(theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.green.opacity(0.7))
                        }
                        .padding(14)
                        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.6), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(theme.muted)
                Text("Searching for nearby hosts…")
                    .font(theme.monoFont(size: 12))
                    .foregroundStyle(theme.muted)
            }
        }
    }

    @State private var showAdvanced = false

    private var advancedSection: some View {
        let hasNearby = !coordinator.netSession.availableHosts.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation { showAdvanced.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("ADVANCED")
                        .font(theme.monoFont(size: 12))
                        .tracking(2)
                        .foregroundStyle(theme.muted)
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.muted)
                }
            }
            .buttonStyle(.plain)

            if showAdvanced {
                if hasNearby {
                    codeEntry
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("CONNECT BY IP")
                        .font(theme.monoFont(size: 12))
                        .tracking(2)
                        .foregroundStyle(theme.muted)
                    HStack(spacing: 8) {
                        TextField("", text: $directIP, prompt: Text("IP Address").foregroundColor(theme.muted.opacity(0.4)))
                            .keyboardType(.numbersAndPunctuation)
                            .font(theme.monoFont(size: 14))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 48)
                            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                        TextField("", text: $directPort, prompt: Text("5111").foregroundColor(theme.muted.opacity(0.4)))
                            .keyboardType(.numberPad)
                            .font(theme.monoFont(size: 14))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 48)
                            .frame(width: 80)
                            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                    }
                    Button {
                        let host = directIP.trimmingCharacters(in: .whitespacesAndNewlines)
                        let port = UInt16(directPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 5111
                        guard !host.isEmpty else { return }
                        if coordinator.netSession.role != .joiner {
                            coordinator.netSession.startBrowsing()
                        }
                        wantsToBoard = true
                        coordinator.netSession.connectDirect(host: host, port: port)
                    } label: {
                        Text("Connect")
                            .font(theme.monoFont(size: 12))
                            .fontWeight(.semibold)
                            .tracking(1.4)
                            .foregroundStyle(theme.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .background(theme.cardBg, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(theme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @State private var showTrainPicker = false

    @ViewBuilder
    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR IDENTITY")
                .font(theme.monoFont(size: 12))
                .tracking(2)
                .foregroundStyle(theme.muted)

            HStack(spacing: 12) {
                photoAvatar
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        PhotosPicker(
                            selection: $pickerItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            HStack(spacing: 6) {
                                Image(systemName: "photo")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("PHOTO")
                            }
                            .font(theme.monoFont(size: 11))
                            .fontWeight(.semibold)
                            .tracking(1.2)
                            .foregroundStyle(theme.ink)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 38)
                            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                        }
                        .accessibilityLabel("Pick a photo")
                        Button {
                            showTrainPicker.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "tram.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("TRAIN")
                            }
                            .font(theme.monoFont(size: 11))
                            .fontWeight(.semibold)
                            .tracking(1.2)
                            .foregroundStyle(theme.ink)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 38)
                            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                        }
                    }
                    if currentPhotoData != nil {
                        Button {
                            pickedPhotoData = nil
                            pickerItem = nil
                            trainIndex = nil
                            if let p = prefill {
                                prefill = ContactPrefill(displayName: p.displayName, imageData: nil)
                            }
                        } label: { Text("REMOVE") }
                            .appLinkStyle()
                    }
                }
                Spacer()
            }

            if showTrainPicker {
                TrainColorPicker(selection: trainIndex) { idx, data in
                    trainIndex = idx
                    pickedPhotoData = data
                    pickerItem = nil
                    showTrainPicker = false
                }
            }

            TextField("Name", text: $editedName)
                .font(theme.monoFont(size: 14))
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.borderLight, lineWidth: 1)
                )
                .onChange(of: editedName) { _, new in
                    if new.count > 20 { editedName = String(new.prefix(20)) }
                }
        }
        .onChange(of: pickerItem) { _, newItem in
            Task { await loadPickedPhoto(newItem) }
        }
    }

    /// Source-of-truth for the photo we'll send: prefer user-picked, then
    /// silent Contacts, then nil (slot shows initials only).
    private var currentPhotoData: Data? {
        pickedPhotoData ?? prefill?.imageData
    }

    @ViewBuilder
    private var photoAvatar: some View {
        ZStack {
            Circle()
                .fill(theme.cardBg)
                .overlay(Circle().stroke(theme.border, lineWidth: 1))
            if let data = currentPhotoData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Text(initialsFallback)
                    .font(theme.displayFont(size: 18))
                    .foregroundStyle(theme.muted)
            }
        }
        .frame(width: 56, height: 56)
    }

    private var initialsFallback: String {
        let parts = editedName.split(separator: " ")
        let first = parts.first.flatMap { $0.first.map(String.init) } ?? ""
        let last = parts.dropFirst().first.flatMap { $0.first.map(String.init) } ?? ""
        let joined = (first + last).uppercased()
        return joined.isEmpty ? "?" : joined
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let raw = try? await item.loadTransferable(type: Data.self) else { return }
        let compressed = DeviceIdentity.compressPhoto(raw)
        await MainActor.run {
            // If REMOVE (or another picker) ran while we were resolving the
            // image data, the user's later choice should win — drop the
            // stale result instead of clobbering the cleared state.
            guard pickerItem == item else { return }
            pickedPhotoData = compressed
            trainIndex = nil  // real photo wins over the train fallback
        }
    }

    @State private var hasSentClaim = false

    @ViewBuilder
    private var slotPicker: some View {
        if let snap = coordinator.netSession.latestSnapshot {
            if hasSentClaim {
                // Claim sent — show lobby-style waiting state
                VStack(spacing: 16) {
                    Spacer().frame(height: 8)
                    VStack(spacing: 4) {
                        Text("ROOM CODE")
                            .font(theme.monoFont(size: 10))
                            .tracking(2)
                            .foregroundStyle(theme.muted)
                        Text(snap.roomCode)
                            .font(theme.displayFont(size: 28))
                            .foregroundStyle(theme.brand)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("PLAYERS")
                            .font(theme.monoFont(size: 10))
                            .tracking(2)
                            .foregroundStyle(theme.muted)
                        ForEach(snap.players.sorted(by: { $0.seat < $1.seat }), id: \.id) { p in
                            let isMe = p.id == coordinator.netSession.myPlayerID
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text(p.name)
                                    .font(theme.monoFont(size: 13))
                                    .foregroundStyle(theme.ink)
                                if isMe {
                                    Text("YOU")
                                        .font(theme.monoFont(size: 8))
                                        .tracking(1.2)
                                        .foregroundStyle(theme.accent)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isMe ? theme.brand.opacity(0.5) : theme.borderLight, lineWidth: 1)
                            )
                        }
                    }

                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(theme.brand)
                        Text("Waiting for the conductor to depart...")
                            .font(theme.monoFont(size: 12))
                            .tracking(1.4)
                            .foregroundStyle(theme.muted)
                    }
                    .padding(.top, 8)
                }
                .onChange(of: coordinator.netSession.latestSnapshot?.scores.count) { _, count in
                    if let count, count > 0 {
                        coordinator.dismissSheet()
                        coordinator.openSpectator()
                    }
                }
                .onChange(of: coordinator.netSession.latestSnapshot?.currentStop) { _, stop in
                    if let stop, stop >= 1 {
                        coordinator.dismissSheet()
                        coordinator.openSpectator()
                    }
                }
                .task {
                    // .onChange only fires on *changes*. If the snapshot
                    // already reflects an in-progress game when this view
                    // first appears (late joiner — host departed before us),
                    // there's no change to fire. Mirror the same dismissal
                    // logic here so the late joiner doesn't get stuck.
                    if let snap = coordinator.netSession.latestSnapshot,
                       snap.currentStop > 0 || !snap.scores.isEmpty {
                        coordinator.dismissSheet()
                        coordinator.openSpectator()
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("You'll join as a player with the name above.")
                        .font(theme.monoFont(size: 12))
                        .foregroundStyle(theme.muted)
                }
            }
        }
    }


    private var joinButton: some View {
        let state = coordinator.netSession.joinState
        return Group {
            switch state {
            case .browsing, .disconnected:
                Button {
                    wantsToBoard = true
                    if let host = coordinator.netSession.availableHosts.first(where: { $0.roomCode == code }) {
                        coordinator.netSession.connect(to: host)
                    }
                } label: {
                    joinButtonLabel(text: "BOARD", enabled: connectEnabled && canConfirm)
                }
                .disabled(!(connectEnabled && canConfirm))
            case .connecting, .reconnecting:
                joinButtonLabel(text: "BOARDING…", enabled: false)
            case .connected:
                if hasSentClaim {
                    joinButtonLabel(text: "ABOARD ✓", enabled: false)
                } else {
                    // Fallback (e.g. no name was prefilled): let them board
                    // once a name is entered.
                    Button(action: confirm) {
                        joinButtonLabel(text: "BOARD", enabled: canConfirm)
                    }
                    .disabled(!canConfirm)
                }
            case .hostEnded:
                joinButtonLabel(text: "HOST LEFT", enabled: false)
            }
        }
        .padding(.horizontal, 16)
        .onChange(of: coordinator.netSession.joinState) { _, newState in
            // Once connected after tapping BOARD, auto-send the claim so the
            // player lands directly in the lobby — no second tap.
            if newState == .connected, wantsToBoard, !hasSentClaim {
                wantsToBoard = false
                confirm()
            }
        }
    }

    private func joinButtonLabel(text: String, enabled: Bool) -> some View {
        Text(text)
            .font(theme.displayFont(size: 14))
            .tracking(2.5)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(theme.ctaText)
            .background(enabled ? theme.cta : theme.muted,
                        in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
            .opacity(enabled ? 1 : 0.5)
    }

    private var connectEnabled: Bool {
        RoomCode.isValid(code) &&
        coordinator.netSession.availableHosts.contains(where: { $0.roomCode == code })
    }

    private var canConfirm: Bool {
        !editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadPrefill() async {
        let p = await DeviceIdentity.loadCurrentIdentity()
        prefill = p
        // Settings-saved name wins over the device-derived name when
        // present — it's the user's explicit identity choice.
        if editedName.isEmpty {
            let saved = settings.defaultYouName
            if !saved.isEmpty && saved != "Conductor" {
                editedName = saved
            } else if let n = p.displayName, !n.isEmpty {
                editedName = n
            }
        }
        // And the settings-saved photo wins over no-photo. The user can
        // still tap CHANGE PHOTO to override, or REMOVE to clear.
        if pickedPhotoData == nil, let saved = settings.defaultYouPhotoJPEG {
            pickedPhotoData = saved
        }
    }

    private func confirm() {
        guard !hasSentClaim, canConfirm else { return }
        let photo = pickedPhotoData ?? DeviceIdentity.compressPhoto(prefill?.imageData)

        let snapshotGameID = coordinator.netSession.latestSnapshot?.gameID
        let savedGameID = coordinator.settings.activeJoinGameID
        let rejoinID: UUID? = (snapshotGameID != nil && snapshotGameID == savedGameID)
            ? coordinator.settings.activeJoinPlayerID
            : nil

        let claim = PlayerClaim(playerID: rejoinID ?? UUID(),
                                displayName: editedName.trimmingCharacters(in: .whitespacesAndNewlines),
                                photoJPEG: photo)
        coordinator.netSession.sendClaim(claim)

        coordinator.settings.activeJoinPlayerID = claim.playerID
        coordinator.settings.activeJoinPlayerName = claim.displayName
        coordinator.settings.activeJoinRoomCode = code.isEmpty ? coordinator.netSession.latestSnapshot?.roomCode ?? "" : code
        coordinator.settings.activeJoinGameID = snapshotGameID
        // Persist as the user's default identity so the joiner doesn't have
        // to retype after a cancel-and-rejoin. Mirrors what the conductor
        // does on DEPART (NewGameView.start).
        coordinator.settings.defaultYouName = claim.displayName
        if let photo, !photo.isEmpty {
            coordinator.settings.defaultYouPhotoJPEG = photo
        }

        let snap = coordinator.netSession.latestSnapshot
        // Game has already started if scoring has produced any rows OR the
        // host has advanced past stop 0 (i.e. tapped DEPART). The latter
        // catches the "late joiner" case where the host departed before
        // anyone submitted a score.
        let gameStarted = snap != nil && (snap!.currentStop > 0 || !snap!.scores.isEmpty)

        if gameStarted {
            coordinator.dismissSheet()
            coordinator.openSpectator()
        } else {
            hasSentClaim = true
        }
    }
}
