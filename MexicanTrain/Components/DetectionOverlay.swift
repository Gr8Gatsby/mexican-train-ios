import SwiftUI

/// Renders a captured photo with the vision pipeline's detections drawn
/// on top: a colored rectangle around each detected domino half plus a
/// pip-value pill in the corner. Bounding boxes are in the source image's
/// normalized [0, 1] coordinate system (top-left origin).
struct DetectionOverlay: View {
    let image: UIImage
    let tiles: [TileObservation]
    var color: Color = .orange
    var lineWidth: CGFloat = 2
    var animateIn: Bool = true

    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            // .scaledToFit keeps aspect ratio; figure out the actual displayed rect
            // so overlay coordinates align with the visible image.
            let displayed = displayedRect(in: geo.size, imageSize: image.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                ForEach(Array(tiles.enumerated()), id: \.offset) { (i, tile) in
                    if let bbox = tile.bbox {
                        DetectionMark(
                            value: tile.pips,
                            rect: rect(for: bbox, in: displayed),
                            color: color,
                            lineWidth: lineWidth
                        )
                        .scaleEffect(appeared ? 1 : 0.7)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.32, dampingFraction: 0.7)
                            .delay(Double(i) * 0.04), value: appeared)
                    }
                }
            }
            .onAppear {
                if animateIn { appeared = true } else { appeared = true }
            }
        }
    }

    /// Compute the rectangle the scaledToFit image actually occupies inside
    /// the parent's bounds.
    private func displayedRect(in container: CGSize, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width,
                        container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        let x = (container.width - w) / 2
        let y = (container.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func rect(for bbox: NormalizedRect, in displayed: CGRect) -> CGRect {
        CGRect(
            x: displayed.minX + bbox.x * displayed.width,
            y: displayed.minY + bbox.y * displayed.height,
            width: bbox.width * displayed.width,
            height: bbox.height * displayed.height
        )
    }
}

private struct DetectionMark: View {
    let value: Int
    let rect: CGRect
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(color, lineWidth: lineWidth)
                .shadow(color: color.opacity(0.6), radius: 6)
                .frame(width: rect.width, height: rect.height)
            Text("\(value)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(color, in: Capsule())
                .offset(x: 6, y: -8)
        }
        .position(x: rect.midX, y: rect.midY)
        .accessibilityLabel("Detected half: \(value) pips")
    }
}
