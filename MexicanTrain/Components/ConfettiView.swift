import SwiftUI

/// Lightweight one-shot confetti overlay. No external dependencies; uses
/// timeline-driven SwiftUI animation. Particles explode upward from 2-3
/// random burst points in the bottom half of the screen, arc up then fall
/// back down with gravity. The whole burst lasts `duration` seconds, after
/// which the view stops drawing.
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
    private let burstOrigins: [BurstOrigin]

    init(duration: Double = 3.5, particleCount: Int = 80) {
        self.duration = duration
        self.particleCount = particleCount
        self.burstOrigins = [
            BurstOrigin(xFraction: .random(in: 0.2...0.8), yFraction: .random(in: 0.55...0.75), delay: 0),
            BurstOrigin(xFraction: .random(in: 0.2...0.8), yFraction: .random(in: 0.55...0.75), delay: 0.2),
            BurstOrigin(xFraction: .random(in: 0.2...0.8), yFraction: .random(in: 0.55...0.75), delay: 0.4),
        ]
        let perBurst = particleCount / 3
        self.particles = (0..<particleCount).map { i in
            let burstIdx = min(i / perBurst, 2)
            return Particle.random(burstIndex: burstIdx)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let progress = min(1.0, elapsed / duration)
            Canvas { ctx, size in
                guard progress < 1 else { return }
                let gravity: CGFloat = 1200 // points/sec^2

                for p in particles {
                    let burst = burstOrigins[p.burstIndex]
                    let particleElapsed = elapsed - burst.delay
                    guard particleElapsed > 0 else { continue }

                    let t = CGFloat(particleElapsed)
                    let totalTime = CGFloat(duration - burst.delay)

                    let angleRad = p.angleDeg * .pi / 180.0
                    let vx = cos(angleRad) * p.velocity * 0.5
                    let vy = -sin(angleRad) * p.velocity // negative = upward

                    let originX = burst.xFraction * size.width
                    let originY = burst.yFraction * size.height

                    let x = originX + vx * t
                    let y = originY + vy * t + 0.5 * gravity * t * t

                    // Skip if off screen
                    guard y <= size.height + 50, x >= -50, x <= size.width + 50 else { continue }

                    let localProgress = min(1.0, t / totalTime)
                    let opacity = localProgress > 0.8 ? 1.0 - ((localProgress - 0.8) / 0.2) : 1.0
                    let rot = Angle.degrees(Double(p.rotationStart) + Double(p.rotationRate) * localProgress * 360)

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

    private struct BurstOrigin {
        var xFraction: CGFloat
        var yFraction: CGFloat
        var delay: Double
    }

    private struct Particle {
        var burstIndex: Int
        var angleDeg: CGFloat        // launch angle 0-360
        var velocity: CGFloat        // initial speed
        var rotationStart: Double
        var rotationRate: Double
        var size: CGSize
        var colorIndex: Int

        static func random(burstIndex: Int) -> Particle {
            Particle(
                burstIndex: burstIndex,
                angleDeg: .random(in: 0...360),
                velocity: .random(in: 600...1100),
                rotationStart: .random(in: 0...360),
                rotationRate: .random(in: 0.5...3),
                size: CGSize(width: .random(in: 6...10), height: .random(in: 8...14)),
                colorIndex: Int.random(in: 0...4)
            )
        }
    }
}
