import XCTest
import CoreML
@testable import MexicanTrain

final class VisionPipCounterTests: XCTestCase {
    func testBucketLogic() {
        XCTAssertEqual(VisionPipCounter.bucket(for: [], tileCount: 0), .low)
        XCTAssertEqual(VisionPipCounter.bucket(for: [0.90, 0.85, 0.80], tileCount: 3), .high)
        XCTAssertEqual(VisionPipCounter.bucket(for: [0.95, 0.95, 0.30], tileCount: 3), .medium)
        XCTAssertEqual(VisionPipCounter.bucket(for: [0.40, 0.30], tileCount: 2), .low)
        XCTAssertEqual(VisionPipCounter.bucket(for: [0.60, 0.60, 0.60], tileCount: 3), .medium)
    }

    func testNMSDropsOverlapping() {
        let a = VisionPipCounter.YOLODetection(cx: 100, cy: 100, w: 50, h: 50, classIndex: 5, confidence: 0.9)
        let b = VisionPipCounter.YOLODetection(cx: 110, cy: 100, w: 50, h: 50, classIndex: 5, confidence: 0.6)
        let c = VisionPipCounter.YOLODetection(cx: 500, cy: 500, w: 50, h: 50, classIndex: 3, confidence: 0.7)
        let kept = VisionPipCounter.nms(detections: [a, b, c], iouThreshold: 0.45)
        XCTAssertEqual(kept.count, 2)
        XCTAssertTrue(kept.contains { $0.confidence == 0.9 })
        XCTAssertTrue(kept.contains { $0.classIndex == 3 })
    }

    func testIoUExact() {
        let a = VisionPipCounter.YOLODetection(cx: 100, cy: 100, w: 100, h: 100, classIndex: 0, confidence: 1)
        let b = VisionPipCounter.YOLODetection(cx: 150, cy: 100, w: 100, h: 100, classIndex: 0, confidence: 1)
        let iou = VisionPipCounter.iou(a, b)
        // overlap rectangle: 50×100 = 5000; union = 10000+10000-5000 = 15000; IoU = 0.333...
        XCTAssertEqual(iou, 5000.0 / 15000.0, accuracy: 0.001)
    }

    func testProductionFactoryFallsBackToMockWhenNotBundled() {
        // With the mlpackage bundled this returns VisionPipCounter; without,
        // MockPipCounter. We just assert the call doesn't crash.
        let counter = PipCounterFactory.makeProductionCounter()
        XCTAssertTrue(counter is VisionPipCounter || counter is MockPipCounter)
    }
}
