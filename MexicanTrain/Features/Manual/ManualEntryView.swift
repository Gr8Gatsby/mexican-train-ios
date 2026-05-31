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
                if game.doublesPenaltyPips > 0 {
                    doublesPenaltyChip
                        .padding(.horizontal, 16)
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

    private var doublesPenaltyChip: some View {
        Button(action: applyDoublesPenalty) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("ADD +\(game.doublesPenaltyPips) DOUBLES PENALTY")
                    .font(theme.monoFont(size: 11))
                    .fontWeight(.semibold)
                    .tracking(1.4)
            }
            .foregroundStyle(theme.brand)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(theme.cardBg, in: Capsule())
            .overlay(Capsule().stroke(theme.brand.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(game.doublesPenaltyPips) doubles penalty")
    }

    private func applyDoublesPenalty() {
        let current = Int(value) ?? 0
        value = String(current + game.doublesPenaltyPips)
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
