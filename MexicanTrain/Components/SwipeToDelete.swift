import SwiftUI

struct SwipeToDelete<Content: View>: View {
    let onDelete: () -> Void
    let accessibilityLabel: String
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @GestureState private var dragX: CGFloat = 0

    private let buttonWidth: CGFloat = 80
    private let revealThreshold: CGFloat = 40

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: {
                close()
                onDelete()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                    Text("DELETE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                }
                .foregroundStyle(.white)
                .frame(width: buttonWidth)
                .frame(maxHeight: .infinity)
                .background(Color(hex: 0xB54B2C), in: RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel(accessibilityLabel)
            .opacity(currentOffset < -8 ? 1 : 0)

            content()
                .background(theme.bg)
                .offset(x: currentOffset)
                .simultaneousGesture(dragGesture)
                .allowsHitTesting(offset == 0)

            // When drawer is open, cover the row to intercept taps and swipe-back.
            if offset != 0 {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .onTapGesture { close() }
                    .padding(.trailing, buttonWidth)
            }
        }
        .clipped()
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: offset)
    }

    private var currentOffset: CGFloat {
        let raw = offset + dragX
        return min(0, max(-buttonWidth - 16, raw))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($dragX) { value, state, _ in
                if abs(value.translation.width) > abs(value.translation.height) {
                    state = value.translation.width
                }
            }
            .onEnded { value in
                let total = offset + value.translation.width
                if total < -revealThreshold {
                    offset = -buttonWidth
                } else {
                    offset = 0
                }
            }
    }

    private func close() {
        offset = 0
    }
}
