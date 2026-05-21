import SwiftUI

struct CameraView: View {
    let game: Game
    let player: Player
    let stop: Int

    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context

    @State private var camera = CameraCapture()
    @State private var phase: Phase = .aim
    @State private var captured: UIImage?
    @State private var result: PipCountResult?
    @State private var error: String?

    enum Phase: Equatable { case aim, scanning, confirm }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                viewfinder
                bottomBar
            }
        }
        .task {
            await camera.prepare()
        }
        .onDisappear {
            camera.stop()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                coordinator.openScoreboard(game)
            } label: {
                Text("← CANCEL")
                    .font(theme.monoFont(size: 10))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            }
            Spacer()
            Text("\(player.name.uppercased()) · STOP \(stop)/\(game.lengthStops)")
                .font(theme.monoFont(size: 10))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Button {
                coordinator.openManualEntry(game: game, player: player, stop: stop)
            } label: {
                Text("123")
                    .font(theme.monoFont(size: 11))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.25), lineWidth: 1)
                    )
            }
            .accessibilityLabel("Manual entry")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.6))
    }

    @ViewBuilder
    private var viewfinder: some View {
        ZStack {
            if let session = camera.session, camera.hasCamera {
                CameraPreview(session: session)
                    .clipped()
            } else if let img = captured {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
            }

            switch phase {
            case .aim:
                AimBrackets(color: theme.accent)
                statusPill
            case .scanning:
                ScanLine(color: theme.accent)
            case .confirm:
                confirmOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fallback: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.6))
            Text(camera.state == .denied ? "Camera access denied" : "No camera available")
                .font(theme.monoFont(size: 12))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.75))
            Text("Tap the shutter to simulate a scan.")
                .font(theme.monoFont(size: 10))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.55))
        }
        .multilineTextAlignment(.center)
        .padding()
    }

    private var statusPill: some View {
        VStack {
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("HOLD STILL · GOOD LIGHT")
                    .font(theme.monoFont(size: 9))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
            Spacer()
        }
        .padding(.top, 16)
    }

    private var confirmOverlay: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0.4), .clear],
                           startPoint: .bottom, endPoint: .top)
                .allowsHitTesting(false)
            if let result {
                VStack {
                    Spacer()
                    DetectedTilesRow(tiles: result.tiles)
                        .padding(.bottom, 6)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("✓ \(result.tiles.count) TILES · YOUR PIP COUNT")
                                .font(theme.monoFont(size: 10))
                                .tracking(1.8)
                                .foregroundStyle(theme.accent)
                                .fontWeight(.semibold)
                            Text("\(result.total)")
                                .font(theme.displayFont(size: 96, relativeTo: .largeTitle))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
                                .contentTransition(.numericText())
                            Text("EDIT IN AUDIT AFTER SUBMIT")
                                .font(theme.monoFont(size: 9))
                                .tracking(1.4)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(16)
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let err = error {
                Text(err)
                    .font(theme.monoFont(size: 10))
                    .foregroundStyle(.red)
            }
            switch phase {
            case .aim:
                aimControls
            case .scanning:
                scanningControls
            case .confirm:
                confirmControls
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(.black.opacity(0.85))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
    }

    private var aimControls: some View {
        HStack {
            Spacer()
            Button(action: shoot) {
                Circle()
                    .fill(.white)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().fill(theme.accent).frame(width: 56, height: 56))
                    .overlay(Circle().stroke(.black, lineWidth: 4).padding(-4))
            }
            .accessibilityLabel("Scan tiles")
            Spacer()
        }
    }

    private var scanningControls: some View {
        VStack(spacing: 6) {
            Text("SCANNING…")
                .font(theme.monoFont(size: 11))
                .tracking(2)
                .foregroundStyle(theme.accent)
            ProgressView()
                .tint(theme.accent)
        }
    }

    private var confirmControls: some View {
        HStack(spacing: 8) {
            Button {
                phase = .aim
                captured = nil
                result = nil
            } label: {
                Text("↻ RETAKE")
                    .font(theme.displayFont(size: 14))
                    .tracking(2)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                            .stroke(.white.opacity(0.25), lineWidth: 1)
                    )
            }
            Button(action: submit) {
                Text("ALL ABOARD ✓")
                    .font(theme.displayFont(size: 14))
                    .tracking(2)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(theme.ctaText)
                    .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
            }
            .frame(maxWidth: .infinity * 2)
        }
    }

    private func shoot() {
        Task {
            withAnimation(.easeInOut(duration: 0.2)) { phase = .scanning }
            do {
                let image: UIImage
                if camera.hasCamera {
                    image = try await camera.capturePhoto()
                } else {
                    image = Self.simulatedCapture()
                }
                captured = image
                let result = try await coordinator.pipCounter.count(in: image)
                self.result = result
                withAnimation(.easeInOut(duration: 0.3)) { phase = .confirm }
            } catch {
                self.error = "Couldn't read tiles. Tap retake or use 123 for manual entry."
                phase = .aim
            }
        }
    }

    private func submit() {
        guard let image = captured, let result else { return }
        do {
            let capture = try CapturePersistence.saveCapture(
                in: context, photoStore: coordinator.photoStore,
                game: game, player: player, stop: stop,
                image: image, result: result
            )
            try GamePersistence.recordScore(
                in: context, game: game, player: player,
                stop: stop, pips: result.total, source: .scanned, captureID: capture.id
            )
            coordinator.openScoreboard(game)
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
        }
    }

    /// Solid color image used when running on the simulator with no camera.
    /// The mock pip counter doesn't care about pixel content; it uses image
    /// size to vary results, so a 1024-square frame is fine.
    private static func simulatedCapture() -> UIImage {
        let size = CGSize(width: 1024, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(red: 0.55, green: 0.43, blue: 0.27, alpha: 1.0).cgColor,
                          UIColor(red: 0.30, green: 0.20, blue: 0.10, alpha: 1.0).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(gradient,
                                  start: .zero,
                                  end: CGPoint(x: size.width, y: size.height),
                                  options: [])
        }
    }
}

private struct AimBrackets: View {
    let color: Color
    var body: some View {
        ZStack {
            GeometryReader { geo in
                let w: CGFloat = 240
                let h: CGFloat = w * 0.62
                let len: CGFloat = 36
                let t: CGFloat = 3
                let x = (geo.size.width - w) / 2
                let y = (geo.size.height - h) / 2
                Group {
                    Rectangle().fill(color).frame(width: len, height: t).offset(x: x, y: y)
                    Rectangle().fill(color).frame(width: t, height: len).offset(x: x, y: y)
                    Rectangle().fill(color).frame(width: len, height: t).offset(x: x + w - len, y: y)
                    Rectangle().fill(color).frame(width: t, height: len).offset(x: x + w - t, y: y)
                    Rectangle().fill(color).frame(width: len, height: t).offset(x: x, y: y + h - t)
                    Rectangle().fill(color).frame(width: t, height: len).offset(x: x, y: y + h - len)
                    Rectangle().fill(color).frame(width: len, height: t).offset(x: x + w - len, y: y + h - t)
                    Rectangle().fill(color).frame(width: t, height: len).offset(x: x + w - t, y: y + h - len)
                }
            }
            Text("POINT AT YOUR HAND")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

private struct DetectedTilesRow: View {
    let tiles: [TileObservation]
    @State private var appeared = false
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(tiles.prefix(6).enumerated()), id: \.offset) { i, t in
                DominoGlyph(a: t.a, b: t.b, width: 48, color: .white)
                    .padding(4)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .scaleEffect(appeared ? 1.0 : 0.6)
                    .opacity(appeared ? 1.0 : 0.0)
                    .animation(.spring(response: 0.32, dampingFraction: 0.7).delay(Double(i) * 0.07),
                               value: appeared)
                    .accessibilityLabel("Tile \(t.a) and \(t.b)")
            }
        }
        .onAppear { appeared = true }
    }
}

private struct ScanLine: View {
    let color: Color
    @State private var animate = false
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(color)
                .frame(height: 2)
                .shadow(color: color, radius: 8)
                .position(x: geo.size.width / 2,
                          y: animate ? geo.size.height * 0.8 : geo.size.height * 0.2)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animate)
        }
        .onAppear { animate = true }
    }
}
