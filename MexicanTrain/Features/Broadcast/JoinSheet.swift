import SwiftUI
import PhotosUI
import UIKit

struct JoinSheet: View {
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    var initialCode: String?

    @State private var code: String = ""
    @State private var prefill: ContactPrefill?
    @State private var editedName: String = ""
    @State private var roleChoice: RoleChoice = .player
    @State private var showScanner: Bool = false
    @State private var scannerHint: String?
    @State private var pickerItem: PhotosPickerItem?
    /// User-picked photo (compressed, ≤ 32 KB). When set, takes precedence
    /// over the silent Contacts Me-card photo for the outgoing claim.
    @State private var pickedPhotoData: Data?
    enum RoleChoice: String, CaseIterable, Identifiable {
        case player, spectator
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                header
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

    private var header: some View {
        HStack {
            Text("JOIN GAME")
                .font(theme.monoFont(size: 11))
                .tracking(2)
                .foregroundStyle(theme.muted)
            Spacer()
            Button("Cancel") {
                coordinator.netSession.leave()
                dismiss()
            }
            .font(theme.monoFont(size: 12))
            .foregroundStyle(theme.brand)
        }
        .padding(.horizontal, 16)
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ROOM CODE")
                    .font(theme.monoFont(size: 10))
                    .tracking(2)
                    .foregroundStyle(theme.muted)
                Spacer()
                Button {
                    showScanner = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                        Text("SCAN QR")
                            .font(theme.monoFont(size: 10))
                            .tracking(1.4)
                    }
                    .foregroundStyle(theme.brand)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.border, lineWidth: 1)
                    )
                }
                .accessibilityLabel("Scan host QR code")
            }
            TextField("0000", text: $code)
                .keyboardType(.numberPad)
                .font(theme.displayFont(size: 36, relativeTo: .title))
                .tracking(6)
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
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
                    .font(theme.monoFont(size: 10))
                    .foregroundStyle(theme.brand)
            }
        }
    }

    @ViewBuilder
    private var hostList: some View {
        if !coordinator.netSession.availableHosts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("NEARBY")
                    .font(theme.monoFont(size: 10))
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
                                    .font(theme.monoFont(size: 10))
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
            Text("Searching for nearby hosts…")
                .font(theme.monoFont(size: 11))
                .foregroundStyle(theme.muted)
        }
    }

    @ViewBuilder
    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR IDENTITY")
                .font(theme.monoFont(size: 10))
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
                        Text(currentPhotoData == nil ? "PICK PHOTO" : "CHANGE PHOTO")
                            .font(theme.monoFont(size: 11))
                            .tracking(1.4)
                            .foregroundStyle(theme.ink)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                    }
                    .accessibilityLabel(currentPhotoData == nil ? "Pick a photo" : "Change photo")
                    if currentPhotoData != nil {
                        Button {
                            pickedPhotoData = nil
                            pickerItem = nil
                            // Also blank out the auto-prefill so Remove
                            // really removes the photo, instead of
                            // silently reverting to the Contacts photo.
                            if let p = prefill {
                                prefill = ContactPrefill(displayName: p.displayName, imageData: nil)
                            }
                        } label: {
                            Text("REMOVE")
                                .font(theme.monoFont(size: 10))
                                .tracking(1.2)
                                .foregroundStyle(theme.brand)
                        }
                    }
                }
                Spacer()
            }

            TextField("Name", text: $editedName)
                .padding(10)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.borderLight, lineWidth: 1)
                )

            Text("Name is prefilled from this device — edit before joining if you like. Photo is optional; tap PICK PHOTO to choose one (iCloud Photo Library is surfaced automatically).")
                .font(theme.monoFont(size: 10))
                .foregroundStyle(theme.muted)
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
        }
    }

    @ViewBuilder
    private var slotPicker: some View {
        if coordinator.netSession.latestSnapshot != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("ROLE")
                    .font(theme.monoFont(size: 10))
                    .tracking(2)
                    .foregroundStyle(theme.muted)
                HStack {
                    rolePill(.player, label: "JOIN AS PLAYER")
                    rolePill(.spectator, label: "SPECTATE")
                }
                if roleChoice == .player {
                    Text("You'll be added to the conductor's player list with the name above.")
                        .font(theme.monoFont(size: 10))
                        .foregroundStyle(theme.muted)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func rolePill(_ value: RoleChoice, label: String) -> some View {
        Button { roleChoice = value } label: {
            Text(label)
                .font(theme.monoFont(size: 11))
                .tracking(1.4)
                .foregroundStyle(roleChoice == value ? theme.ctaText : theme.ink)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(roleChoice == value ? theme.cta : theme.cardBg,
                            in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                        .stroke(theme.border, lineWidth: 1)
                )
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
                    joinButtonLabel(text: "JOIN", enabled: canConfirm)
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
            .opacity(enabled ? 1 : 0.55)
    }

    private var connectEnabled: Bool {
        RoomCode.isValid(code) &&
        coordinator.netSession.availableHosts.contains(where: { $0.roomCode == code })
    }

    private var canConfirm: Bool {
        let nameOK = !editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if roleChoice == .player {
            return nameOK
        }
        return true
    }

    private func loadPrefill() async {
        let p = await DeviceIdentity.loadCurrentIdentity()
        prefill = p
        if editedName.isEmpty, let n = p.displayName { editedName = n }
    }

    private func confirm() {
        switch roleChoice {
        case .player:
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
        case .spectator:
            break
        }
        coordinator.openSpectator()
        dismiss()
    }
}
