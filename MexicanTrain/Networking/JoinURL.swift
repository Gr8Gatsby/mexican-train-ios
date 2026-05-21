import Foundation

enum JoinURL {
    static let scheme = "mextrain"
    static let host = "join"

    static func encode(roomCode: String) -> URL {
        URL(string: "\(scheme)://\(host)?code=\(roomCode)")!
    }

    static func decode(_ url: URL) -> String? {
        guard url.scheme == scheme, url.host == host else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else {
            return nil
        }
        return RoomCode.isValid(code) ? code : nil
    }
}
