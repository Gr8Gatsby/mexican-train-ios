import Foundation
import CoreGraphics

struct TileObservation: Codable, Equatable, Hashable {
    var a: Int
    var b: Int
    /// Bounding box in the source image's normalized coordinate system
    /// ([0,1], top-left origin). `nil` when the observation didn't come
    /// from a vision pipeline (e.g. manual entry).
    var bbox: NormalizedRect?

    init(a: Int, b: Int, bbox: NormalizedRect? = nil) {
        self.a = a
        self.b = b
        self.bbox = bbox
    }

    var pips: Int { a + b }
}

/// Hand-rolled Codable rect so JSON round-trips cleanly across the wire
/// (CGRect's synthesized Codable encodes as a less-readable nested form).
struct NormalizedRect: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
