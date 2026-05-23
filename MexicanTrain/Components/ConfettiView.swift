import SwiftUI

/// Lightweight one-shot confetti overlay. No external dependencies; uses
/// timeline-driven SwiftUI animation. Particles fall from the top of the
/// frame, rotating, and fade out near the bottom. The whole burst lasts
/// `duration` seconds, after which the view stops drawing.
struct ConfettiView: View {
    var duration: Double = 3.5
    var particleCount: Int = 80
    var colors: [Color] = [
        Color(hex: 0xB54B2C),   // brand red
        Color(hex: 0x3A7A3A),   // accent green
        Color(hex: 0xD7A847),   // warm gold
        Color(hex: 0x2E5BA8),   // royal blue
        Color(hex: 0x8C3FA1),   // plum
    ]

    @State private var startedAt = Date()
    private let particles: [Particle]

    init(duration: Double = 3.5, particleCount: Int = 80) {
        self.duration = duration
        self.particleCount = particleCount
        self.particles = (0..<particleCount).map { _ in Particle.random() }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let progress = min(1.0, elapsed / duration)
            Canvas { ctx, size in
                guard progress < 1 else { return }
                for p in particles {
                    let t = max(0, min(1, (elapsed - p.delay) / (duration - p.delay)))
                    if t <= 0 { continue }
                    let x = p.startX * size.width + p.driftX * t * size.width
                    // ease-in fall: starts above the frame, falls past bottom
                    let y = -40 + (size.height + 80) * pow(t, 1.4)
                    let rot = Angle.degrees(p.rotationStart + p.rotationRate * t * 360)
                    let opacity = 1.0 - max(0, (t - 0.85) / 0.15)
                    let rect = CGRect(x: x - p.size.width/2, y: y - p.size.height/2,
                                      width: p.size.width, height: p.size.height)
                    var path = Path(roundedRect: rect, cornerRadius: 1.5)
                    path = path.applying(.init(translationX: rect.midX, y: rect.midY)
                        .rotated(by: rot.radians)
                        .translatedBy(x: -rect.midX, y: -rect.midY))
                    let color = colors[p.colorIndex % colors.count]
                    ctx.fill(path, with: .color(color.opacity(opacity)))
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .onAppear { startedAt = Date() }
    }

    private struct Particle {
        var startX: CGFloat          // 0…1
        var driftX: CGFloat          // -0.3…0.3
        var delay: Double            // 0…0.6 staggered start
        var rotationStart: Double    // 0…360
        var rotationRate: Double     // 0.5…3 rotations/sec
        var size: CGSize
        var colorIndex: Int

        static func random() -> Particle {
            Particle(
                startX: .random(in: 0...1),
                driftX: .random(in: -0.25...0.25),
                delay: .random(in: 0...0.6),
                rotationStart: .random(in: 0...360),
                rotationRate: .random(in: 0.5...3),
                size: CGSize(width: .random(in: 6...10), height: .random(in: 8...14)),
                colorIndex: Int.random(in: 0...4)
            )
        }
    }
}
