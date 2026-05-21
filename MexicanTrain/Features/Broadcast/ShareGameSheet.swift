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
                header
                code
                qr
                claimsList
                Spacer()
                stopButton
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .onAppear {
            if coordinator.netSession.role != .host {
                start()
            } else {
                roomCode = coordinator.netSession.roomCode
            }
        }
    }

    private var header: some View {
        HStack {
            Text("SHARE GAME")
                .font(theme.monoFont(size: 11))
                .tracking(2)
                .foregroundStyle(theme.muted)
            Spacer()
            Button("Done") { dismiss() }
                .font(theme.monoFont(size: 12))
                .foregroundStyle(theme.brand)
        }
    }

    private var code: some View {
        VStack(spacing: 4) {
            Text("ROOM CODE")
                .font(theme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(theme.muted)
            Text(roomCode)
                .font(theme.displayFont(size: 48, relativeTo: .largeTitle))
                .tracking(8)
                .foregroundStyle(theme.brand)
                .accessibilityLabel("Room code \(roomCode.map { String($0) }.joined(separator: " "))")
            Text("\(coordinator.netSession.connectedPeerCount) joined")
                .font(theme.monoFont(size: 10))
                .tracking(1.2)
                .foregroundStyle(theme.muted)
        }
    }

    private var qr: some View {
        VStack(spacing: 8) {
            Text("SCAN OR ENTER CODE")
                .font(theme.monoFont(size: 10))
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
            HStack {
                Text("JOINED PLAYERS")
                    .font(theme.monoFont(size: 10))
                    .tracking(2)
                    .foregroundStyle(theme.muted)
                Spacer()
            }
            if claims.isEmpty {
                Text("No one yet. Share the QR or code.")
                    .font(theme.monoFont(size: 11))
                    .foregroundStyle(theme.muted)
            } else {
                ForEach(Array(claims.values)) { claim in
                    HStack {
                        Text(claim.displayName)
                            .font(theme.displayFont(size: 14))
                            .foregroundStyle(theme.ink)
                        Spacer()
                        Button {
                            coordinator.netSession.revokeClaim(playerID: claim.playerID)
                        } label: {
                            Text("REVOKE")
                                .font(theme.monoFont(size: 9))
                                .tracking(1.2)
                                .foregroundStyle(theme.brand)
                        }
                    }
                    .padding(8)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var stopButton: some View {
        Button {
            coordinator.netSession.stopHosting()
            dismiss()
        } label: {
            Text("STOP SHARING")
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
    }

    private func start() {
        let code = RoomCode.generate()
        roomCode = code
        let snap = SnapshotBuilder.build(game: game, photoStore: coordinator.photoStore, roomCode: code)
        coordinator.netSession.startHosting(initialSnapshot: snap)
    }
}
