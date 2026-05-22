import SwiftUI
import UIKit

/// Joiner-side analogue of `ManualEntryView`. Same keypad UX, but on submit
/// it sends a `ScoreSubmission` to the host instead of writing locally.
struct JoinerManualEntryView: View {
    let playerID: UUID
    let playerName: String
    let stop: Int
    let lengthStops: Int

    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @State private var value: String = ""
    @State private var referencePhoto: UIImage?

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                readout
                if let referencePhoto {
                    referenceCard(referencePhoto)
                }
                Spacer(minLength: 0)
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

    private var header: some View {
        HStack {
            Button {
                coordinator.openSpectator()
            } label: {
                Text("← CANCEL")
                    .font(theme.monoFont(size: 10))
                    .tracking(1.2)
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(theme.subBg, in: RoundedRectangle(cornerRadius: 14))
            }
            Spacer()
            Text("\(playerName.uppercased()) · STOP \(stop)/\(lengthStops)")
                .font(theme.monoFont(size: 10))
                .tracking(1.6)
                .foregroundStyle(theme.muted)
            Spacer()
            Color.clear.frame(width: 80, height: 1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.headerBg)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var readout: some View {
        VStack(spacing: 6) {
            Text("PIP COUNT")
                .font(theme.monoFont(size: 10))
                .tracking(1.8)
                .foregroundStyle(theme.muted)
            Text(value.isEmpty ? "0" : value)
                .font(theme.displayFont(size: 80))
                .foregroundStyle(theme.ink)
                .frame(minHeight: 92)
            Text("SUM OF PIPS LEFT IN HAND")
                .font(theme.monoFont(size: 9))
                .tracking(1.4)
                .foregroundStyle(theme.muted)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack {
            Button(action: submit) {
                Text("ALL ABOARD ✓")
                    .font(theme.displayFont(size: 14))
                    .tracking(2.5)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(theme.ctaText)
                    .background(canSubmit ? theme.cta : theme.muted,
                                in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
            }
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.55)
        }
        .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 10)
        .background(theme.subBg)
        .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 1) }
    }

    private var canSubmit: Bool { Int(value) != nil }

    private func submit() {
        guard let n = Int(value) else { return }
        let submission = ScoreSubmission(
            playerID: playerID,
            stopIndex: stop,
            pips: n,
            source: .manual,
            tiles: [],
            thumbJPEG: nil
        )
        coordinator.netSession.sendScoreSubmission(submission)
        coordinator.openSpectator()
    }
}
