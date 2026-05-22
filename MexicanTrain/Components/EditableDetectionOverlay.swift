import SwiftUI
import UIKit

/// Conductor-editable version of `DetectionOverlay`. Renders the captured
/// photo with each detection as a tappable chip; supports:
///
/// - **Tap chip**: open a pip-value picker (0–12 + Delete) so the conductor
///   can correct a misclassified half.
/// - **Tap on empty image area**: drop a new chip with a default bbox at
///   that point, then prompt for its value (handles missed detections).
///
/// `bindings` is the source of truth — edits update the array in place via
/// the binding, so the caller (AuditView) sees the corrected `[TileObservation]`
/// and decides when to persist it.
struct EditableDetectionOverlay: View {
    let image: UIImage
    @Binding var tiles: [TileObservation]
    var color: Color = .orange
    var lineWidth: CGFloat = 2

    @State private var editing: EditingState?

    /// Either editing an existing tile (by index) or adding a new one at a
    /// normalized point on the image.
    enum EditingState: Identifiable {
        case existing(index: Int)
        case new(at: CGPoint)
        var id: String {
            switch self {
            case .existing(let i): return "existing-\(i)"
            case .new(let p): return "new-\(p.x)-\(p.y)"
            }
        }
    }

    /// Default bbox size used when the conductor drops a new chip — about
    /// the median half-tile size in the existing detector's output. Crude
    /// but useful: imperfect bboxes are still much better than missing
    /// training labels.
    private let defaultBBoxWidth: Double = 0.12
    private let defaultBBoxHeight: Double = 0.24

    var body: some View {
        GeometryReader { geo in
            let displayed = displayedRect(in: geo.size, imageSize: image.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { point in
                        guard displayed.contains(point) else { return }
                        let nx = (point.x - displayed.minX) / displayed.width
                        let ny = (point.y - displayed.minY) / displayed.height
                        editing = .new(at: CGPoint(x: nx, y: ny))
                    }
                ForEach(Array(tiles.enumerated()), id: \.offset) { (i, tile) in
                    if let bbox = tile.bbox {
                        let r = rect(for: bbox, in: displayed)
                        EditableMark(
                            value: tile.pips,
                            rect: r,
                            color: color,
                            lineWidth: lineWidth
                        )
                        .onTapGesture {
                            editing = .existing(index: i)
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { state in
            PipValuePicker(initial: initialValue(for: state)) { result in
                handlePickerResult(result, state: state)
                editing = nil
            }
            .presentationDetents([.height(360)])
        }
    }

    // MARK: - Picker glue

    private func initialValue(for state: EditingState) -> Int {
        switch state {
        case .existing(let i): return i < tiles.count ? tiles[i].pips : 0
        case .new: return 0
        }
    }

    private func handlePickerResult(_ result: PipValuePicker.Result, state: EditingState) {
        switch (state, result) {
        case (.existing(let i), .value(let v)) where i < tiles.count:
            let existing = tiles[i]
            tiles[i] = TileObservation(a: v, b: 0, bbox: existing.bbox)
        case (.existing(let i), .delete) where i < tiles.count:
            tiles.remove(at: i)
        case (.new(let point), .value(let v)):
            let half = NormalizedRect(
                x: max(0, min(1 - defaultBBoxWidth, point.x - defaultBBoxWidth / 2)),
                y: max(0, min(1 - defaultBBoxHeight, point.y - defaultBBoxHeight / 2)),
                width: defaultBBoxWidth,
                height: defaultBBoxHeight
            )
            tiles.append(TileObservation(a: v, b: 0, bbox: half))
        case (.new, .delete):
            break
        default:
            break
        }
    }

    // MARK: - Geometry helpers (mirror DetectionOverlay)

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

private struct EditableMark: View {
    let value: Int
    let rect: CGRect
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(color, lineWidth: lineWidth)
                .background(color.opacity(0.06))
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())
            Text("\(value)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(color, in: Capsule())
                .offset(x: 6, y: -8)
                .allowsHitTesting(false)
        }
        .position(x: rect.midX, y: rect.midY)
        .accessibilityLabel("Detected half: \(value) pips. Tap to edit.")
    }
}

/// Modal picker for selecting a pip value 0…12, with a delete option.
struct PipValuePicker: View {
    let initial: Int
    let onPick: (Result) -> Void

    enum Result { case value(Int); case delete }

    @Environment(\.theme) private var theme
    @State private var selected: Int

    init(initial: Int, onPick: @escaping (Result) -> Void) {
        self.initial = initial
        self.onPick = onPick
        _selected = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("PIP VALUE")
                .font(theme.monoFont(size: 11))
                .tracking(2)
                .foregroundStyle(theme.muted)
                .padding(.top, 14)
            Text("\(selected)")
                .font(theme.displayFont(size: 56))
                .foregroundStyle(theme.brand)
                .contentTransition(.numericText())
            let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(0...12, id: \.self) { n in
                    Button {
                        selected = n
                    } label: {
                        Text("\(n)")
                            .font(theme.monoFont(size: 14))
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(selected == n ? theme.ctaText : theme.ink)
                            .background(selected == n ? theme.cta : theme.cardBg,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 14)
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    onPick(.delete)
                } label: {
                    Text("DELETE")
                        .font(theme.monoFont(size: 12))
                        .tracking(1.4)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(theme.brand)
                        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                                .stroke(theme.brand.opacity(0.4), lineWidth: 1)
                        )
                }
                Button {
                    onPick(.value(selected))
                } label: {
                    Text("SAVE")
                        .font(theme.displayFont(size: 13))
                        .tracking(1.6)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(theme.ctaText)
                        .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .background(theme.bg)
    }
}
