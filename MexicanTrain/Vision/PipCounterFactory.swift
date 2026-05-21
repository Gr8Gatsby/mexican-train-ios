import Foundation

enum PipCounterFactory {
    /// Use the bundled CoreML model when present; otherwise return the mock.
    /// Lets reviewers exercise the full camera/audit flow before the trained
    /// `DominoDetector.mlmodel` ships, and seamlessly upgrades to the real
    /// counter once it's bundled.
    static func makeProductionCounter() -> any PipCounter {
        if let real = VisionPipCounter.loadFromBundle() {
            return real
        }
        return MockPipCounter()
    }
}
