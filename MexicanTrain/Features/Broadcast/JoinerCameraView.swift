import SwiftUI
import UIKit

/// Thin wrapper around `CameraView` for player joiners. The joiner has no
/// `Game` / `Player` SwiftData model — those live on the host — so we drive
/// `CameraView` in its `game: nil, player: nil` mode and inject closures for
/// the top-bar subject, cancel navigation, the manual fallback, and submit.
///
/// On submit, we encode the captured image as a small JPEG thumbnail and
/// build a `ScoreSubmission` that gets sent to the host via
/// `MexTrainNetSession.sendScoreSubmission`.
struct JoinerCameraHost: View {
    let playerID: UUID
    let playerName: String
    let stop: Int
    let lengthStops: Int

    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        CameraView(
            game: nil,
            player: nil,
            stop: stop,
            topBarSubject: "\(playerName.uppercased()) · STOP \(stop)/\(lengthStops)",
            onSubmit: { image, result in
                send(image: image, result: result)
            },
            onCancel: {
                coordinator.openSpectator()
            },
            onManual: {
                coordinator.openJoinerManualEntry(
                    playerID: playerID, playerName: playerName,
                    stop: stop, lengthStops: lengthStops
                )
            }
        )
    }

    private func send(image: UIImage, result: PipCountResult) {
        let resized = image.resized(toMaxEdge: PlayerPhoto.targetEdge)
        var thumb: Data?
        for q in [0.7, 0.5, 0.3] as [CGFloat] {
            if let data = resized.jpegData(compressionQuality: q),
               data.count <= PlayerPhoto.maxJPEGBytes {
                thumb = data
                break
            }
        }

        // Save the captured photo locally on the joiner device.
        if let gameID = coordinator.netSession.latestSnapshot?.gameID {
            _ = try? coordinator.photoStore.save(
                image: image, gameID: gameID, captureID: UUID()
            )
        }

        let submission = ScoreSubmission(
            playerID: playerID,
            stopIndex: stop,
            pips: result.total,
            source: .scanned,
            tiles: result.tiles,
            thumbJPEG: thumb
        )
        coordinator.netSession.sendScoreSubmission(submission)
        coordinator.openSpectator()
    }
}
