import SwiftUI

struct ShareGameSheet: View {
    let game: Game
    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var roomCode: String = ""

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                AppHeaderBar(
                    style: .modal,
                    title: "Share game",
                    onLeading: nil
                ) {
                    Button { dismiss() } label: { Text("DONE") }
                        .appLinkStyle()
                }
                VStack(spacing: 16) {
                    code
                    qr
                    claimsList
                    Spacer()
                    stopButton
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
        }
        .onAppear {
            if coordinator.netSession.role != .host {
                start()
            } else {
                roomCode = coordinator.netSession.roomCode
            }
        }
    }

    private var code: some View {
        VStack(spacing: 4) {
            Text("ROOM CODE")
                .font(theme.monoFont(size: 12))
                .tracking(2)
                .foregroundStyle(theme.muted)
            Text(roomCode)
                .font(theme.displayFont(size: 48, relativeTo: .largeTitle))
                .tracking(8)
                .foregroundStyle(theme.brand)
                .accessibilityLabel("Room code \(roomCode.map { String($0) }.joined(separator: " "))")
            Text("\(coordinator.netSession.connectedPeerCount) joined")
                .font(theme.monoFont(size: 12))
                .tracking(1.2)
                .foregroundStyle(theme.muted)
        }
    }

    private var qr: some View {
        VStack(spacing: 8) {
            Text("SCAN OR ENTER CODE")
                .font(theme.monoFont(size: 12))
                .tracking(2)
                .foregroundStyle(theme.muted)
            if !roomCode.isEmpty {
                QRCodeView(payload: JoinURL.encode(roomCode: roomCode).absoluteString)
                    .frame(maxWidth: 220, maxHeight: 220)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(theme.border, lineWidth: 1)
                    )
            }
        }
    }

    private var claimsList: some View {
        let claims = coordinator.netSession.playerClaims
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("JOINED PLAYERS")
                    .font(theme.monoFont(size: 12))
                    .tracking(2)
                    .foregroundStyle(theme.muted)
                if claims.isEmpty {
                    ProgressView()
                        .scaleEffect(0.65)
                        .tint(theme.muted)
                }
                Spacer()
            }
            if claims.isEmpty {
                Text("No one yet. Share the QR or room code.")
                    .font(theme.monoFont(size: 12))
                    .foregroundStyle(theme.muted)
            } else {
                ForEach(Array(claims.values)) { claim in
                    HStack {
                        Text(claim.displayName)
                            .font(theme.displayFont(size: 16))
                            .foregroundStyle(theme.ink)
                        Spacer()
                        Button {
                            coordinator.netSession.revokeClaim(playerID: claim.playerID)
                        } label: { Text("REVOKE") }
                            .appLinkStyle()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var stopButton: some View {
        Button {
            coordinator.netSession.stopHosting()
            dismiss()
        } label: { Text("STOP SHARING") }
            .appSecondaryStyle()
    }

    private func start() {
        let code = RoomCode.generate()
        roomCode = code
        let snap = SnapshotBuilder.build(game: game, photoStore: coordinator.photoStore, roomCode: code)
        coordinator.netSession.startHosting(initialSnapshot: snap)
    }
}
