import Foundation

enum RoomCode {
    /// 4-digit code avoiding patterns that get garbled when said aloud
    /// (all-same, simple runs).
    static func generate() -> String {
        for _ in 0..<50 {
            let code = String(format: "%04d", Int.random(in: 1000...9999))
            if !isAmbiguous(code) { return code }
        }
        return String(format: "%04d", Int.random(in: 1000...9999))
    }

    static func isAmbiguous(_ code: String) -> Bool {
        guard code.count == 4 else { return true }
        let chars = Array(code)
        if Set(chars).count == 1 { return true }
        if chars == ["1","2","3","4"] || chars == ["4","3","2","1"] { return true }
        if chars == ["2","3","4","5"] || chars == ["5","4","3","2"] { return true }
        return false
    }

    static func isValid(_ code: String) -> Bool {
        code.count == 4 && code.allSatisfy { $0.isNumber }
    }
}
