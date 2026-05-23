import SwiftUI

/// Drag the row left to reveal a red Delete handle; tap it to fire
/// `onDelete`. Used on the Home History list, which lives inside a
/// ScrollView/VStack rather than a List (so we can't use `.swipeActions`
/// here). Releasing past `revealThreshold` snaps open; releasing short
/// snaps closed.
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
            // Delete handle sits underneath the row content.
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
                .background(Color(hex: 0xB54B2C))
            }
            .accessibilityLabel(accessibilityLabel)
            .opacity(currentOffset < -8 ? 1 : 0)

            content()
                .background(theme.bg)
                .offset(x: currentOffset)
                .gesture(dragGesture)
                // When the delete drawer is open, swallow row taps so the
                // user has to either delete or swipe back. Tapping the row
                // body closes the drawer.
                .allowsHitTesting(offset == 0)
            if offset != 0 {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .padding(.trailing, buttonWidth)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: offset)
    }

    private var currentOffset: CGFloat {
        // Clamp final offset to [-buttonWidth, 0]; allow a touch of
        // rubber-banding past either end while the finger is down.
        let raw = offset + dragX
        return min(0, max(-buttonWidth - 16, raw))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($dragX) { value, state, _ in
                // Only track horizontal drags so vertical scroll still wins.
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

    /// If the drawer is open, tapping the row anywhere should close it
    /// without firing the row's own tap. We only intercept while open.
    private var closeOnTapWhenOpen: some Gesture {
        TapGesture().onEnded {
            if offset != 0 { close() }
        }
    }

    private func close() {
        offset = 0
    }
}
