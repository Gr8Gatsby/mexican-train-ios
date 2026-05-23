import SwiftUI

/// Canonical header used across every screen. Two visual templates:
///
/// - **.push**: chevron-back on the left, centered title in display font
///   brand color, optional trailing accessory. Used for any screen the
///   user navigated into via `coordinator.openXxx`.
/// - **.modal**: mono section-label on the left, "Done"/"Cancel" text
///   button on the right. Used for sheet-presented screens (Join, Share).
///
/// Replaces hand-rolled headers that had drifted into three back-button
/// styles, two title alignments, and a mix of pill / text dismiss
/// affordances. Tap targets are 44pt minimum to match Apple HIG.
struct AppHeaderBar<Trailing: View>: View {
    enum Style { case push, modal }

    let style: Style
    let title: String
    /// Optional second line under the title. Used by EndGameView's
    /// "FINAL · May 23, 2026" subtitle. Push style only.
    var subtitle: String? = nil
    let onLeading: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.theme) private var theme

    init(
        style: Style,
        title: String,
        subtitle: String? = nil,
        onLeading: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.style = style
        self.title = title
        self.subtitle = subtitle
        self.onLeading = onLeading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 4) {
            leading
            Spacer(minLength: 0)
            switch style {
            case .push:
                pushTitle
            case .modal:
                modalTitle
            }
            Spacer(minLength: 0)
            trailingArea
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .background(theme.headerBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch style {
        case .push:
            if let onLeading {
                Button(action: onLeading) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        case .modal:
            // Modal headers don't have a leading nav — the dismiss is on
            // the right by iOS convention. We still reserve 44pt so the
            // title's optical center matches the push variant.
            Color.clear.frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private var pushTitle: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(theme.displayFont(size: 16))
                .foregroundStyle(theme.brand)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtitle {
                Text(subtitle)
                    .font(theme.monoFont(size: 11))
                    .tracking(1.4)
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var modalTitle: some View {
        Text(title.uppercased())
            .font(theme.monoFont(size: 12))
            .tracking(2)
            .foregroundStyle(theme.muted)
    }

    @ViewBuilder
    private var trailingArea: some View {
        HStack(spacing: 4) {
            trailing()
        }
        .frame(minHeight: 44)
    }
}
