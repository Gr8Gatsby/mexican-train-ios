import SwiftUI

/// Attach to any view that owns the game; rebuilds + broadcasts a snapshot
/// whenever the game's salient state changes. Borrowed pattern from
/// `~/code/farkle/Farkle/Features/Multipeer/HostBroadcaster.swift`.
struct HostBroadcasterModifier: ViewModifier {
    let game: Game
    @Environment(AppCoordinator.self) private var coordinator

    func body(content: Content) -> some View {
        content
            .onChange(of: fingerprint) { _, _ in broadcastIfHosting() }
            .onAppear { broadcastIfHosting() }
    }

    private var fingerprint: String {
        let playerFP = game.sortedPlayers.map { "\($0.id):\($0.name)" }.joined(separator: "|")
        let scoreFP = game.scores
            .sorted { $0.updatedAt < $1.updatedAt }
            .map { "\($0.playerID):\($0.stopIndex):\($0.pips)" }
            .joined(separator: ",")
        let captureFP = "\(game.captures.count)"
        let endFP = game.finishedAt.map { String($0.timeIntervalSince1970) } ?? "-"
        return "\(game.currentStopIndex)#\(playerFP)#\(scoreFP)#\(captureFP)#\(endFP)"
    }

    private func broadcastIfHosting() {
        guard coordinator.netSession.role == .host else { return }
        let snap = SnapshotBuilder.build(game: game,
                                         photoStore: coordinator.photoStore,
                                         roomCode: coordinator.netSession.roomCode)
        coordinator.netSession.broadcast(snapshot: snap)
    }
}

extension View {
    func hostBroadcaster(game: Game) -> some View {
        modifier(HostBroadcasterModifier(game: game))
    }
}
