import UIKit

struct ContactPrefill: Equatable {
    let displayName: String?
    let imageData: Data?
}

/// iOS-side identity prefill. The macOS "Me card" API isn't available on
/// iOS, so we prefill from `UIDevice.current.name`, stripping the
/// "'s iPhone" / "'s iPad" suffix when present. The user can edit before
/// they tap Join.
///
/// (When Apple ships a richer identity API or we want to lean on the
/// AccessoryPicker flow, swap the body of `loadCurrentIdentity` — the
/// `ContactPrefill` shape stays stable.)
enum DeviceIdentity {
    enum Access { case granted }

    static func currentAccess() -> Access { .granted }

    static func request() async -> Access { .granted }

    static func loadCurrentIdentity() async -> ContactPrefill {
        let raw = UIDevice.current.name
        let cleaned = stripDeviceSuffix(raw)
        return ContactPrefill(displayName: cleaned.isEmpty ? nil : cleaned, imageData: nil)
    }

    static func stripDeviceSuffix(_ name: String) -> String {
        var out = name
        for suffix in ["'s iPhone", "'s iPad", "'s iPod", "’s iPhone", "’s iPad", "’s iPod"] {
            if let r = out.range(of: suffix) {
                out = String(out[..<r.lowerBound])
                break
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Resize + JPEG-compress so a photo fits inside the multipeer reliable
    /// envelope. v1 doesn't supply a photo automatically, but if the user
    /// picks one later this stays the right hook.
    static func compressPhoto(_ data: Data?) -> Data? {
        guard let data, let image = UIImage(data: data) else { return nil }
        let resized = image.resized(toMaxEdge: PlayerPhoto.targetEdge)
        var quality: CGFloat = 0.7
        while quality >= 0.3 {
            if let out = resized.jpegData(compressionQuality: quality),
               out.count <= PlayerPhoto.maxJPEGBytes {
                return out
            }
            quality -= 0.1
        }
        return resized.jpegData(compressionQuality: 0.3)
    }
}
