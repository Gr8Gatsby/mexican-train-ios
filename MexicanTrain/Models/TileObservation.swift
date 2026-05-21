import Foundation

struct TileObservation: Codable, Equatable, Hashable {
    var a: Int
    var b: Int

    var pips: Int { a + b }
}
