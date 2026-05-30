import SwiftUI
import SwiftData
import UIKit

struct ManualEntryView: View {
    let game: Game
    let player: Player
    let stop: Int
    /// Override for the top-bar pill — used by the conductor override flow
    /// to read "AS ALICE · STOP 4/13", matching the camera-side badge.
    var topBarSubject: String?

    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @State private var value: String = ""
    @State private var referencePhoto: UIImage?

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                AppHeaderBar(
                    style: .push,
                    title: topBarSubject ?? player.name,
                    subtitle: topBarSubject == nil ? "STOP \(stop) / \(game.lengthStops)" : nil,
                    onLeading: { coordinator.openScoreboard(game) }
                )
                readout
                if let referencePhoto {
                    referenceCard(referencePhoto)
                }
                Spacer(minLength: 0)
                if hasAnyRuleChip {
                    rulesChipRow
                        .padding(.bottom, 8)
                }
                KeypadView(value: $value)
                    .padding(.horizontal, 16)
                footer
            }
        }
        .onAppear {
            referencePhoto = coordinator.pendingManualReference
            coordinator.pendingManualReference = nil
        }
    }

    private func referenceCard(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("REFERENCE PHOTO")
                .font(theme.monoFont(size: 9))
                .tracking(1.4)
                .foregroundStyle(theme.muted)
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.border, lineWidth: 1)
                )
        }
        .padding(.horizontal, 16).padding(.bottom, 6)
    }

    private var readout: some View {
        VStack(spacing: 6) {
            Text("PIP COUNT")
                .font(theme.monoFont(size: 10))
                .tracking(1.8)
                .foregroundStyle(theme.muted)
            Text(value.isEmpty ? "—" : value)
                .font(theme.displayFont(size: 80))
                .foregroundStyle(value.isEmpty ? theme.muted.opacity(0.5) : theme.ink)
                .frame(minHeight: 92)
            Text(readoutHelper)
                .font(theme.monoFont(size: 9))
                .tracking(1.4)
                .foregroundStyle(willApplyGoingOutBonus ? theme.brand : theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    /// Help text under the big readout. Reflects whether the player will get
    /// the going-out bonus when they submit at the current value.
    private var readoutHelper: String {
        if value.isEmpty {
            return game.goingOutBonus == .none
                ? "TYPE A NUMBER · 0 IF THEY WENT OUT"
                : "TYPE A NUMBER · 0 IF THEY WENT OUT (BONUS \(game.goingOutBonus.displayName))"
        }
        if willApplyGoingOutBonus {
            return "GOING-OUT BONUS \(game.goingOutBonus.displayName) WILL APPLY"
        }
        return "SUM OF PIPS LEFT IN HAND"
    }

    private var willApplyGoingOutBonus: Bool {
        Int(value) == 0 && game.goingOutBonus != .none
    }

    private var hasAnyRuleChip: Bool {
        // Note: double-blank penalty is intentionally NOT a per-entry chip —
        // detection can't reliably identify the 0|0 tile, so it's applied via
        // a round-end "who had it?" prompt on the scoreboard instead.
        game.doublesPenaltyPips > 0
            || game.anyBlankPenaltyPips > 0
            || game.doublesCountDouble
    }

    /// Horizontally-scrollable row of one-tap penalty chips. Hidden entirely
    /// when no chip-driven rule is configured for the game.
    private var rulesChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if game.doublesPenaltyPips > 0 {
                    addChip(label: "+\(game.doublesPenaltyPips) DBL",
                            accessibility: "Add \(game.doublesPenaltyPips) doubles penalty") {
                        add(game.doublesPenaltyPips)
                    }
                }
                if game.anyBlankPenaltyPips > 0 {
                    addChip(label: "+\(game.anyBlankPenaltyPips) BLANK",
                            accessibility: "Add \(game.anyBlankPenaltyPips) per blank tile") {
                        add(game.anyBlankPenaltyPips)
                    }
                }
                if game.doublesCountDouble {
                    doublesCountDoubleMenu
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Generic "+N LABEL" pill that adds a fixed value on tap.
    private func addChip(label: String, accessibility: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(theme.monoFont(size: 11))
                    .fontWeight(.semibold)
                    .tracking(1.2)
            }
            .foregroundStyle(theme.brand)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(theme.cardBg, in: Capsule())
            .overlay(Capsule().stroke(theme.brand.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    /// Menu chip for the "doubles count double" rule. Picking a double from
    /// the menu adds the *extra* pips beyond standard counting (`+2N` for an
    /// `N|N` tile, since the standard pip sum `2N` is already typed in).
    private var doublesCountDoubleMenu: some View {
        Menu {
            ForEach(0...12, id: \.self) { half in
                let extra = 2 * half
                Button("\(half)|\(half)  (+\(extra))") {
                    add(extra)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("DOUBLE 2×")
                    .font(theme.monoFont(size: 11))
                    .fontWeight(.semibold)
                    .tracking(1.2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(theme.brand)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(theme.cardBg, in: Capsule())
            .overlay(Capsule().stroke(theme.brand.opacity(0.4), lineWidth: 1))
        }
        .accessibilityLabel("Add extra pips for a double left in hand")
    }

    private func add(_ amount: Int) {
        let current = Int(value) ?? 0
        value = String(current + amount)
    }

    private var footer: some View {
        Button(action: submit) { Text("ALL ABOARD ✓") }
            .appPrimaryStyle(enabled: canSubmit)
            .disabled(!canSubmit)
            .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 10)
            .background(theme.subBg)
            .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var canSubmit: Bool { Int(value) != nil }

    private func submit() {
        guard let entered = Int(value) else { return }
        // Going-out bonus: if the conductor entered 0 (player went out) and a
        // bonus is configured, store the bonus value instead. Audit history
        // captures the negative pips directly.
        let pips: Int
        if entered == 0, game.goingOutBonus != .none {
            pips = game.goingOutBonus.rawValue
        } else {
            pips = entered
        }
        do {
            try GamePersistence.recordScore(in: context, game: game, player: player,
                                            stop: stop, pips: pips, source: .manual)
            coordinator.openScoreboard(game)
        } catch {
            // Surface persistence errors silently for v1; reroute home as a fallback.
            coordinator.goHome()
        }
    }
}
