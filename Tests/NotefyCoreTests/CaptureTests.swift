import XCTest
@testable import NotefyCore

final class CaptureTests: XCTestCase {
    func testTrackerCanDiscardPendingCapture() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("noted-tracker-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let tracker = ExplorationTracker(outputDir: directory)
        let step = ExplorationStep(appName: "Test", windowTitle: "Capture", selectedText: "Draft")
        XCTAssertTrue(tracker.start())
        tracker.captureCustomStep(step)
        tracker.removeStep(id: step.id)
        XCTAssertTrue(tracker.stop().isEmpty)
    }

    func testLegacySettingsDecodeWithoutSelectedMicrophone() throws {
        let data = Data(#"{"audio":{"provider":"local","apiURL":"","apiKey":"","modelName":"base"},"vision":{"provider":"local","apiURL":"http://localhost:11434/api/chat","apiKey":"","modelName":"qwen2-vl"}}"#.utf8)
        let settings = try JSONDecoder().decode(NotefySettings.self, from: data)
        XCTAssertNil(settings.audio.inputDeviceUID)
    }

    func testAudioInputEnumerationHasStableUniqueIdentifiers() {
        let devices = AudioInputDevices.available()
        XCTAssertEqual(Set(devices.map(\.uid)).count, devices.count)
        XCTAssertTrue(devices.allSatisfy { !$0.name.isEmpty && !$0.uid.isEmpty })
    }

    func testVisualDifferenceIsZeroForIdenticalFrames() {
        XCTAssertEqual(
            ScreenCapturer.difference([0, 64, 128, 255], [0, 64, 128, 255]),
            0,
            accuracy: 0.000_001
        )
    }

    func testVisualDifferenceIsNormalized() {
        XCTAssertEqual(
            ScreenCapturer.difference([0, 0], [255, 255]),
            1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ScreenCapturer.difference([0, 255], [255, 0]),
            1,
            accuracy: 0.000_001
        )
    }

    func testMissingFingerprintForcesCapture() {
        XCTAssertEqual(
            ScreenCapturer.difference(nil, [0, 0]),
            1,
            accuracy: 0.000_001
        )
    }
}
