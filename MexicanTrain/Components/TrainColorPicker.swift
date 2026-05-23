import SwiftUI
import UIKit

/// Curated 10-color palette for the join-sheet "no photo? pick a train"
/// fallback. Each row gets a `tram.fill` SF Symbol rendered in that color
/// against the theme's card background, which we encode to JPEG and ship
/// over the wire as the player's avatar. Picking a train fires
/// `onPick` with the JPEG bytes ready to be sent.
struct TrainColorPicker: View {
    /// Currently-selected color index, or nil if a real photo is in play.
    /// Shown as a highlighted ring around the matching swatch.
    let selection: Int?
    let onPick: (_ index: Int, _ jpeg: Data) -> Void
    @Environment(\.theme) private var theme

    static let colors: [TrainColor] = [
        TrainColor(name: "Brand red",   hex: 0x8C2A1A),
        TrainColor(name: "Accent rust", hex: 0xC8541D),
        TrainColor(name: "Forest",      hex: 0x3A7A3A),
        TrainColor(name: "Royal",       hex: 0x2E5BA8),
        TrainColor(name: "Teal",        hex: 0x1F8089),
        TrainColor(name: "Plum",        hex: 0x8C3FA1),
        TrainColor(name: "Sun",         hex: 0xD7A847),
        TrainColor(name: "Coral",       hex: 0xE26D5C),
        TrainColor(name: "Slate",       hex: 0x4A5A6A),
        TrainColor(name: "Cocoa",       hex: 0x6B4226),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OR PICK A TRAIN")
                .font(theme.monoFont(size: 11))
                .tracking(1.6)
                .foregroundStyle(theme.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                     count: 5), spacing: 8) {
                ForEach(Self.colors.indices, id: \.self) { i in
                    let c = Self.colors[i]
                    Button {
                        if let data = Self.renderJPEG(colorIndex: i, theme: theme) {
                            onPick(i, data)
                        }
                    } label: {
                        swatch(color: Color(hex: c.hex), selected: selection == i)
                    }
                    .accessibilityLabel(c.name + " train")
                }
            }
        }
    }

    private func swatch(color: Color, selected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(theme.cardBg)
                .overlay(Circle().stroke(selected ? theme.brand : theme.borderLight,
                                          lineWidth: selected ? 2 : 1))
            Image(systemName: "tram.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(height: 52)
    }

    /// Render the train SF Symbol into a small JPEG so it round-trips
    /// over the existing `photoJPEG` field. Output is square, sized so
    /// it stays well under the 32 KB cap. We pre-bake the theme's card
    /// background as the fill so it composes well into the standard
    /// avatar treatment on the host (which clips to a circle).
    static func renderJPEG(colorIndex: Int, theme: Theme) -> Data? {
        guard colorIndex >= 0, colorIndex < colors.count else { return nil }
        let color = UIColor(red: CGFloat((colors[colorIndex].hex >> 16) & 0xFF) / 255,
                            green: CGFloat((colors[colorIndex].hex >> 8) & 0xFF) / 255,
                            blue: CGFloat(colors[colorIndex].hex & 0xFF) / 255,
                            alpha: 1)
        let side: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { ctx in
            // Theme card background as the fill so the avatar matches the
            // app's palette when shown alongside photo avatars.
            UIColor(theme.cardBg).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let symbolCfg = UIImage.SymbolConfiguration(pointSize: side * 0.55, weight: .semibold)
            let symbol = UIImage(systemName: "tram.fill", withConfiguration: symbolCfg)?
                .withTintColor(color, renderingMode: .alwaysOriginal)
            if let symbol {
                let s = symbol.size
                let rect = CGRect(x: (side - s.width) / 2,
                                  y: (side - s.height) / 2,
                                  width: s.width, height: s.height)
                symbol.draw(in: rect)
            }
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}

struct TrainColor: Equatable {
    let name: String
    let hex: UInt32
}
