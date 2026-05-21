import Foundation
import SwiftData

/// M0 stub. The full model — Player / Score / Capture relationships,
/// house rules, current stop, etc. — lands in M1 per dev-design §3.
@Model
final class Game {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    init(id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.createdAt = createdAt
    }
}
