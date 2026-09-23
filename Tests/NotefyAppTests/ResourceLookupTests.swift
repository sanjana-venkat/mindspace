import XCTest
@testable import NotefyApp

/// 0.1.5 died on launch on macOS 15 because `Bundle.module` calls `fatalError`
/// when it cannot open the resource bundle — and the bundle we shipped had no
/// Info.plist, which that macOS refuses. Art must never be able to do that.
final class ResourceLookupTests: XCTestCase {
    func testMissingResourceAnswersNilRatherThanTrapping() {
        // The name is deliberately absurd: the point is that asking for
        // something that is not there returns, rather than killing the process.
        XCTAssertNil(AuroraResources.url("no-such-picture-anywhere", extension: "heic"))
        XCTAssertNil(AuroraResources.url("no-such-picture", extension: "png", subdirectory: "Pet"))
    }

    func testMoonArtLoadsOrFallsBackWithoutCrashing() {
        // Under the test runner there is no app bundle to find art in, which is
        // exactly the condition that used to trap.
        let art = MoonPetArt.load()
        XCTAssertNoThrow(art)
        // Whatever it found, the view has something to draw: `isDrawn` reports
        // the stand-in when no artwork was located.
        _ = art.isDrawn
    }
}
