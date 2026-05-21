import Foundation
import UIKit

struct PipCountResult: Equatable {
    let tiles: [TileObservation]
    let total: Int
    let confidence: Confidence
}

enum PipCounterError: Error, Equatable {
    case noTilesDetected
    case modelUnavailable
    case badImage
}

protocol PipCounter: Sendable {
    func count(in image: UIImage) async throws -> PipCountResult
}
