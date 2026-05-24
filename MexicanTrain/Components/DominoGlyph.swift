import SwiftUI

/// Minimal SVG-style domino glyph. `value` is repeated on both halves
/// (it's the "double" engine indicator from the design); for a generic
/// tile we'd take (a, b). For M1 we only need doubles.
struct DominoGlyph: View {
    let a: Int
    let b: Int
    let width: CGFloat
    var color: Color = .black

    init(value: Int, width: CGFloat = 36, color: Color = .black) {
        self.a = value
        self.b = value
        self.width = width
        self.color = color
    }

    init(a: Int, b: Int, width: CGFloat = 56, color: Color = .black) {
        self.a = a
        self.b = b
        self.width = width
        self.color = color
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let stroke = max(0.6, w * 0.025)
            let halfW = w / 2
            ctx.stroke(
                Path(roundedRect: CGRect(x: stroke/2, y: stroke/2,
                                         width: w - stroke, height: h - stroke),
                     cornerRadius: w * 0.04),
                with: .color(color), lineWidth: stroke
            )
            var divider = Path()
            divider.move(to: CGPoint(x: halfW, y: stroke))
            divider.addLine(to: CGPoint(x: halfW, y: h - stroke))
            ctx.stroke(divider, with: .color(color), lineWidth: stroke)

            // pip layouts in 0..14 grid, then scaled to half-width
            for (offset, value) in [(CGFloat(0), a), (halfW, b)] {
                let positions = pipLayout(value)
                for (px, py) in positions {
                    let rx = offset + CGFloat(px) / 14.0 * halfW
                    let ry = CGFloat(py) / 14.0 * h
                    let r = w * 0.045
                    let rect = CGRect(x: rx - r, y: ry - r, width: r*2, height: r*2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .frame(width: width, height: width / 2)
    }

    private func pipLayout(_ n: Int) -> [(CGFloat, CGFloat)] {
        switch n {
        case 0: return []
        case 1: return [(7,7)]
        case 2: return [(4,4),(10,10)]
        case 3: return [(4,4),(7,7),(10,10)]
        case 4: return [(4,4),(10,4),(4,10),(10,10)]
        case 5: return [(4,4),(10,4),(7,7),(4,10),(10,10)]
        case 6: return [(4,4),(10,4),(4,7),(10,7),(4,10),(10,10)]
        case 7: return [(4,4),(10,4),(4,7),(10,7),(4,10),(10,10),(7,7)]
        case 8: return [(3,3),(7,3),(11,3),(3,7),(11,7),(3,11),(7,11),(11,11)]
        case 9: return [(3,3),(7,3),(11,3),(3,7),(7,7),(11,7),(3,11),(7,11),(11,11)]
        case 10: return [(3,2.5),(7,2.5),(11,2.5),(3,5.5),(11,5.5),(3,8.5),(11,8.5),(3,11.5),(7,11.5),(11,11.5)]
        case 11: return [(3,2.5),(7,2.5),(11,2.5),(3,5.5),(11,5.5),(7,7),(3,8.5),(11,8.5),(3,11.5),(7,11.5),(11,11.5)]
        case 12: return [(3,2.5),(7,2.5),(11,2.5),(3,5.5),(7,5.5),(11,5.5),(3,8.5),(7,8.5),(11,8.5),(3,11.5),(7,11.5),(11,11.5)]
        default: return []
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        DominoGlyph(value: 12, width: 64)
        DominoGlyph(a: 5, b: 3, width: 64)
        DominoGlyph(value: 0, width: 64)
    }
    .padding()
}
