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
        let scoringFP = game.scoringOpen ? "open" : "closed"
        return "\(game.currentStopIndex)#\(playerFP)#\(scoreFP)#\(captureFP)#\(endFP)#\(scoringFP)"
    }

    private func broadcastIfHosting() {
        guard coordinator.netSession.role == .host else { return }
        let snap = SnapshotBuilder.build(game: game,
                                         roomCode: coordinator.netSession.roomCode)
        coordinator.netSession.broadcast(snapshot: snap)
        // Pre-warm photo cache for any captures not yet pushed, so they're
        // available when new joiners connect.
        prewarmPhotoCache()
    }

    /// Load thumbnails for any captures that aren't yet in the net session's
    /// photo cache. This ensures the host can replay all photos when a new
    /// joiner connects.
    private func prewarmPhotoCache() {
        let session = coordinator.netSession
        let photoStore = coordinator.photoStore
        for capture in game.captures {
            guard session.cachedPhoto(for: capture.id) == nil else { continue }
            if let img = photoStore.thumbnail(filename: capture.filename, gameID: game.id, maxEdge: PlayerPhoto.targetEdge),
               let data = img.jpegData(compressionQuality: 0.6),
               data.count <= PlayerPhoto.maxJPEGBytes {
                session.pushPhoto(
                    captureID: capture.id,
                    playerID: capture.playerID,
                    stop: capture.stopIndex,
                    thumbJPEG: data
                )
            }
        }
    }
}

extension View {
    func hostBroadcaster(game: Game) -> some View {
        modifier(HostBroadcasterModifier(game: game))
    }
}
