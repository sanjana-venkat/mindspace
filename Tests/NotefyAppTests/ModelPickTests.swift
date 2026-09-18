import XCTest
@testable import NotefyApp
@testable import NotefyCore

/// Choosing for someone, when their saved model has been retired.
@MainActor
final class ModelPickTests: XCTestCase {
    func testPrefersTheEverydayModelOverWhateverSortsFirst() {
        let gemini = ["gemini-3.1-pro", "gemini-3.8-flash", "gemini-3.5-flash-lite"]
        XCTAssertEqual(AuroraSettingsView.pick(from: gemini), "gemini-3.8-flash")
    }

    func testFallsBackToTheFirstWhenNothingIsFamiliar() {
        XCTAssertEqual(AuroraSettingsView.pick(from: ["aleph-1", "beth-2"]), "aleph-1")
    }

    func testKeysAreKeptPerProvider() {
        var settings = NotefySettings()
        settings.rememberKey("openai-key", for: .api)
        settings.rememberKey("gemini-key", for: .gemini)
        settings.rememberKey("claude-key", for: .anthropic)

        // Reading one provider's key must never hand back another's.
        XCTAssertEqual(settings.key(for: .api), "openai-key")
        XCTAssertEqual(settings.key(for: .gemini), "gemini-key")
        XCTAssertEqual(settings.key(for: .anthropic), "claude-key")
        XCTAssertEqual(settings.key(for: .local), "")
    }

    func testAudioAndVisionKeysAreSeparate() {
        var settings = NotefySettings()
        settings.rememberKey("vision-key", for: .gemini)
        settings.rememberKey("audio-key", for: .gemini, audio: true)
        XCTAssertEqual(settings.key(for: .gemini), "vision-key")
        XCTAssertEqual(settings.key(for: .gemini, audio: true), "audio-key")
    }

    func testImageAndAudioModelsAreNeverOffered() {
        let names = ["gemini-3.8-flash", "imagen-4", "nano-banana-2", "lyria-2",
                     "veo-3", "text-embedding-004", "gpt-6-astra", "whisper-1",
                     "dall-e-3", "omni-moderation-latest", "sora-2"]
        let offered = names.filter { ProviderCatalog.isWorthOffering($0) }
        // Imagen goes too — "imagen" carries "image", which is the point.
        XCTAssertEqual(offered, ["gemini-3.8-flash", "gpt-6-astra"])
    }
}
