import AVFoundation
import SwiftUI

struct CameraView: View {
    /// `nil` when invoked from the joiner side (no SwiftData on that device).
    /// When nil, `onSubmit` and `onCancel` must be provided by the caller.
    let game: Game?
    let player: Player?
    let stop: Int
    /// Overrides the default "PLAYER · STOP N" pill in the top bar. Used by
    /// the conductor override flow ("AS ALICE · STOP 4/13") and by the
    /// joiner camera (no Game/Player available).
    var topBarSubject: String?
    /// Replaces the default "save Capture + recordScore + back to scoreboard"
    /// behavior. The joiner camera path injects a closure that sends a
    /// `ScoreSubmission` via `MexTrainNetSession` instead of writing locally.
    var onSubmit: ((UIImage, PipCountResult) -> Void)?
    /// Replaces the default "back to scoreboard" navigation on cancel.
    /// Joiner mode points this at the spectator view.
    var onCancel: (() -> Void)?
    /// Replaces the default "open ManualEntryView for this player" path on
    /// the "123" button. Joiner mode points this at a joiner-side manual
    /// entry; passing nil hides the manual button entirely.
    var onManual: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context

    @State private var camera = CameraCapture()
    @State private var phase: Phase = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MEXTRAIN_DEBUG_CAMERA_PHASE"] == "confirm" {
            return .confirm
        }
        #endif
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        // Treat a prior grant within this process as still-granted so we
        // never re-show the permission gate between captures (the system
        // status occasionally lags on simulator and on cold-warm transitions).
        if status == .authorized || CameraView.didGrantInSession {
            return .aim
        }
        return .permission
    }()
    /// Process-wide latch: once the user has granted camera permission in
    /// this app launch, skip the permission view on subsequent opens even
    /// if `authorizationStatus` momentarily returns something else.
    private static var didGrantInSession = false
    @State private var captured: UIImage? = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MEXTRAIN_DEBUG_CAMERA_PHASE"] == "confirm" {
            return CameraView.simulatedCapture()
        }
        #endif
        return nil
    }()
    @State private var result: PipCountResult? = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MEXTRAIN_DEBUG_CAMERA_PHASE"] == "confirm" {
            let tiles: [TileObservation] = [
                TileObservation(a: 5, b: 0, bbox: NormalizedRect(x: 0.10, y: 0.20, width: 0.18, height: 0.20)),
                TileObservation(a: 3, b: 0, bbox: NormalizedRect(x: 0.32, y: 0.22, width: 0.18, height: 0.20)),
                TileObservation(a: 9, b: 0, bbox: NormalizedRect(x: 0.55, y: 0.22, width: 0.18, height: 0.20)),
                TileObservation(a: 6, b: 0, bbox: NormalizedRect(x: 0.10, y: 0.50, width: 0.18, height: 0.20)),
                TileObservation(a: 11, b: 0, bbox: NormalizedRect(x: 0.32, y: 0.50, width: 0.18, height: 0.20)),
                TileObservation(a: 4, b: 0, bbox: NormalizedRect(x: 0.55, y: 0.50, width: 0.18, height: 0.20)),
                TileObservation(a: 2, b: 0, bbox: NormalizedRect(x: 0.77, y: 0.50, width: 0.18, height: 0.20))
            ]
            return PipCountResult(
                tiles: tiles,
                total: tiles.map(\.pips).reduce(0, +),
                confidence: .high
            )
        }
        #endif
        return nil
    }()
    @State private var error: String?

    enum Phase: Equatable { case permission, aim, scanning, confirm }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if phase == .permission {
                permissionView
            } else {
                VStack(spacing: 0) {
                    topBar
                    viewfinder
                    bottomBar
                }
            }
        }
        .task {
            if phase != .permission {
                await camera.prepare()
            }
        }
        .onDisappear {
            camera.stop()
        }
    }

    @ViewBuilder
    private var permissionView: some View {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        VStack(spacing: 24) {
            Spacer()
            if status == .denied || status == .restricted {
                Text("Camera access denied")
                    .font(theme.monoFont(size: 16))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(theme.displayFont(size: 14))
                        .tracking(1.4)
                        .frame(maxWidth: 260, minHeight: 50)
                        .foregroundStyle(theme.ctaText)
                        .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                }
            } else {
                Text("Camera access needed to scan dominoes")
                    .font(theme.monoFont(size: 16))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button {
                    Task {
                        let granted = await AVCaptureDevice.requestAccess(for: .video)
                        if granted {
                            CameraView.didGrantInSession = true
                            await camera.prepare()
                            withAnimation(.easeInOut(duration: 0.25)) { phase = .aim }
                        } else {
                            // Refresh the view so it shows the denied state
                            phase = .permission
                        }
                    }
                } label: {
                    Text("Grant Permission")
                        .font(theme.displayFont(size: 14))
                        .tracking(1.4)
                        .frame(maxWidth: 260, minHeight: 50)
                        .foregroundStyle(theme.ctaText)
                        .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                }
            }
            if shouldShowManualButton {
                Button {
                    manual()
                } label: {
                    Text("Enter manually instead")
                        .font(theme.monoFont(size: 14))
                        .fontWeight(.semibold)
                        .tracking(1.2)
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: 260, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Enter manually instead")
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Re-check permission when returning from Settings
            let updated = AVCaptureDevice.authorizationStatus(for: .video)
            if updated == .authorized {
                CameraView.didGrantInSession = true
                Task {
                    await camera.prepare()
                    withAnimation(.easeInOut(duration: 0.25)) { phase = .aim }
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            Button {
                cancel()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.10), in: Circle())
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Cancel")
            Spacer(minLength: 0)
            Text(resolvedTopBarSubject)
                .font(theme.monoFont(size: 13))
                .fontWeight(.semibold)
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if shouldShowManualButton {
                Button {
                    manual()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "number")
                            .font(.system(size: 13, weight: .semibold))
                        Text("KEYPAD")
                            .font(theme.monoFont(size: 12))
                            .fontWeight(.semibold)
                            .tracking(1.2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
                }
                .accessibilityLabel("Manual entry")
            } else {
                Color.clear.frame(width: 44, height: 1)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(.black.opacity(0.6))
    }

    private var resolvedTopBarSubject: String {
        if let topBarSubject { return topBarSubject }
        if let player, let game {
            return "\(player.name.uppercased()) · STOP \(stop)/\(game.lengthStops)"
        }
        return "STOP \(stop)"
    }

    private var shouldShowManualButton: Bool {
        onManual != nil || (game != nil && player != nil)
    }

    private func cancel() {
        if let onCancel { onCancel(); return }
        if let game { coordinator.openScoreboard(game) }
    }

    private func manual() {
        if let onManual { onManual(); return }
        if let game, let player {
            coordinator.openManualEntry(game: game, player: player, stop: stop)
        }
    }

    @ViewBuilder
    private var viewfinder: some View {
        ZStack {
            // Background layer: confirm mode shows the captured photo with
            // detection boxes; aim/scanning show the live preview or fallback.
            if phase == .confirm, let img = captured, let result {
                DetectionOverlay(image: img, tiles: result.tiles, color: theme.accent)
            } else if let session = camera.session, camera.hasCamera {
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
            case .permission:
                EmptyView()
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
            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.3), .clear],
                           startPoint: .bottom, endPoint: .top)
                .allowsHitTesting(false)
            if let result {
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("✓ \(result.tiles.count) HALVES DETECTED")
                                .font(theme.monoFont(size: 10))
                                .tracking(1.8)
                                .foregroundStyle(theme.accent)
                                .fontWeight(.semibold)
                            Text("\(result.total)")
                                .font(theme.displayFont(size: 96, relativeTo: .largeTitle))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
                                .contentTransition(.numericText())
                            Text("PIP COUNT · EDIT IN AUDIT AFTER SUBMIT")
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
            case .permission:
                EmptyView()
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
        VStack(spacing: 10) {
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
            if error != nil, captured != nil, shouldShowManualButton {
                Button(action: bounceToManual) {
                    Text("USE MANUAL ENTRY")
                        .font(theme.monoFont(size: 11))
                        .tracking(1.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.white.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 1))
                }
                .accessibilityHint("Opens a number pad with the photo you just took for reference.")
            }
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
        VStack(spacing: 8) {
            if let r = result, r.tiles.isEmpty, shouldShowManualButton {
                Button(action: bounceToManual) {
                    Text("COULDN'T READ TILES · ENTER MANUALLY")
                        .font(theme.monoFont(size: 11))
                        .tracking(1.4)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.white.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 1))
                }
            }
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        phase = .aim
                        captured = nil
                        result = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                        Text("RETAKE")
                    }
                    .font(theme.displayFont(size: 14))
                    .tracking(2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.buttonCornerRadius)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
                }
                Button(action: submit) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                        Text("ALL ABOARD")
                    }
                    .font(theme.displayFont(size: 14))
                    .tracking(2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(theme.ctaText)
                    .background(theme.cta, in: RoundedRectangle(cornerRadius: theme.buttonCornerRadius))
                }
            }
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
                self.error = "Couldn't read tiles. Tap RETAKE or USE MANUAL ENTRY to type them in."
                phase = .aim
            }
        }
    }

    /// Hand the captured image to the manual-entry view as a reference
    /// photo, then route to manual entry. Triggered either by the
    /// explicit fallback button when vision fails, or by the no-tiles
    /// banner in the confirm step.
    private func bounceToManual() {
        if let image = captured {
            coordinator.pendingManualReference = image
        }
        manual()
    }

    private func submit() {
        guard let image = captured, let result else { return }
        if let onSubmit {
            onSubmit(image, result)
            return
        }
        guard let game, let player else { return }
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
    static func simulatedCapture() -> UIImage {
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
