import Foundation
import SwiftData

@Model
final class Player {
    @Attribute(.unique) var id: UUID
    var game: Game?
    var name: String
    var seat: Int
    var isYou: Bool
    var isActive: Bool
    var avatarFilename: String?

    init(
        id: UUID = UUID(),
        name: String,
        seat: Int,
        isYou: Bool = false,
        isActive: Bool = true,
        avatarFilename: String? = nil
    ) {
        self.id = id
        self.name = name
        self.seat = seat
        self.isYou = isYou
        self.isActive = isActive
        self.avatarFilename = avatarFilename
    }
}
