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
                        // Identity always visible — joiner can fill name +
                        // photo while picking a host. Previously this only
                        // appeared after connection, which felt like a
                        // surprise extra step.
                        identityBlock
                        if coordinator.netSession.joinState != .connected {
                            codeEntry
                            hostList
                            connectByIPSection
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
            // Kick off prefill immediately so the name field has a default
            // by the time the user starts editing.
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
                        scannerHint = "Scanned code \(parsed). Connecting…"
                        showScanner = false
                        if let host = coordinator.netSession.availableHosts.first(where: { $0.roomCode == parsed }) {
                            coordinator.netSession.connect(to: host)
                        }
                    } else if RoomCode.isValid(raw) {
                        code = raw
                        scannerHint = "Scanned code \(raw). Connecting…"
                        showScanner = false
                        if let host = coordinator.netSession.availableHosts.first(where: { $0.roomCode == raw }) {
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
                        coordinator.netSession.connect(to: host)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(host.hostName)
                                    .font(theme.displayFont(size: 14))
                                    .foregroundStyle(theme.ink)
                                Text("\(host.gameName) · \(host.playerCount) players · code \(host.roomCode)")
                                    .font(theme.monoFont(size: 12))
                                    .foregroundStyle(theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(theme.muted)
                        }
                        .padding(10)
                        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
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

    private var connectByIPSection: some View {
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
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.system(size: 13, weight: .semibold))
                            Text(currentPhotoData == nil ? "PICK PHOTO" : "CHANGE PHOTO")
                        }
                        .font(theme.monoFont(size: 12))
                        .fontWeight(.semibold)
                        .tracking(1.4)
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(theme.border, lineWidth: 1)
                        )
                    }
                    .accessibilityLabel(currentPhotoData == nil ? "Pick a photo" : "Change photo")
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

            TextField("Name", text: $editedName)
                .font(theme.monoFont(size: 14))
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.borderLight, lineWidth: 1)
                )

            Text("Name is prefilled from this device — edit before joining if you like. Photo is optional; tap PICK PHOTO to choose one (iCloud Photo Library is surfaced automatically), or pick a train below.")
                .font(theme.monoFont(size: 12))
                .foregroundStyle(theme.muted)

            TrainColorPicker(selection: trainIndex) { idx, data in
                trainIndex = idx
                pickedPhotoData = data
                pickerItem = nil
            }
            .padding(.top, 2)
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
            pickedPhotoData = compressed
            trainIndex = nil  // real photo wins over the train fallback
        }
    }

    @ViewBuilder
    private var slotPicker: some View {
        if coordinator.netSession.latestSnapshot != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("You'll join as a player with the name above.")
                    .font(theme.monoFont(size: 12))
                    .foregroundStyle(theme.muted)
            }
        }
    }


    private var joinButton: some View {
        let state = coordinator.netSession.joinState
        return Group {
            switch state {
            case .browsing, .disconnected:
                Button {
                    if let host = coordinator.netSession.availableHosts.first(where: { $0.roomCode == code }) {
                        coordinator.netSession.connect(to: host)
                    }
                } label: {
                    joinButtonLabel(text: "CONNECT", enabled: connectEnabled)
                }
                .disabled(!connectEnabled)
            case .connecting:
                joinButtonLabel(text: "CONNECTING…", enabled: false)
            case .connected:
                Button(action: confirm) {
                    joinButtonLabel(text: "JOIN AS PLAYER", enabled: canConfirm)
                }
                .disabled(!canConfirm)
            case .hostEnded:
                joinButtonLabel(text: "HOST LEFT", enabled: false)
            }
        }
        .padding(.horizontal, 16)
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
        // Prefer the user-picked photo (already compressed by
        // loadPickedPhoto). Fall back to the silent Contacts photo,
        // which still goes through compressPhoto so the wire-size
        // contract holds. Nil → slot shows initials only.
        let photo = pickedPhotoData ?? DeviceIdentity.compressPhoto(prefill?.imageData)
        // Fresh UUID — the host treats unknown IDs as "add me as a new
        // player slot" (lobby) or as a claim against an existing slot
        // matching this id (in-progress games).
        let claim = PlayerClaim(playerID: UUID(),
                                displayName: editedName.trimmingCharacters(in: .whitespacesAndNewlines),
                                photoJPEG: photo)
        coordinator.netSession.sendClaim(claim)
        // Dismiss the sheet first, then navigate. Using dismissSheet()
        // rather than the environment dismiss() to avoid a SwiftUI timing
        // race where the sheet animation could reset the route change.
        coordinator.dismissSheet()
        coordinator.openSpectator()
    }
}
