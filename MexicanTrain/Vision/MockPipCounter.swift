import Foundation
import UIKit

/// Deterministically random pip counts so we can build the camera/audit
/// flow before the real CoreML model lands. Used by default in DEBUG and
/// whenever the production model is absent.
struct MockPipCounter: PipCounter {
    var seed: UInt64 = 0xC0FFEE
    var simulateLatency: TimeInterval = 0.7
    var maxValue: Int = 12

    func count(in image: UIImage) async throws -> PipCountResult {
        try await Task.sleep(nanoseconds: UInt64(simulateLatency * 1_000_000_000))

        // Mix the seed with a hash of the image's pixel size to get
        // photo-stable but per-photo variation.
        let pxKey = UInt64(image.size.width.rounded()) &* 31 &+ UInt64(image.size.height.rounded())
        var rng = SeededRNG(seed: seed ^ pxKey ^ UInt64(bitPattern: Int64(Date().timeIntervalSinceReferenceDate)))

        let count = Int.random(in: 4...8, using: &rng)
        var tiles: [TileObservation] = []
        // Sprinkle plausible bboxes in a rough grid so the confirm-screen
        // overlay shows highlights instead of nothing.
        let cols = 3
        for i in 0..<count {
            let a = Int.random(in: 0...maxValue, using: &rng)
            let b = Int.random(in: 0...maxValue, using: &rng)
            let row = i / cols
            let col = i % cols
            let w = 0.20
            let h = 0.18
            let x = 0.10 + Double(col) * 0.28 + Double.random(in: -0.02...0.02, using: &rng)
            let y = 0.25 + Double(row) * 0.22 + Double.random(in: -0.02...0.02, using: &rng)
            let bbox = NormalizedRect(x: x, y: y, width: w, height: h)
            tiles.append(TileObservation(a: a, b: b, bbox: bbox))
        }
        let total = tiles.map(\.pips).reduce(0, +)
        let confidence: Confidence = (count >= 5 ? .high : .medium)
        return PipCountResult(tiles: tiles, total: total, confidence: confidence)
    }
}

/// Tiny RNG so Mock results stay reproducible across runs when we want
/// them to. (Not cryptographically anything.)
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
