import XCTest
@testable import NotefyApp

/// The search index is built from what a person would call the contents of a
/// note. These are the cases that went wrong in practice.
final class SearchTextTests: XCTestCase {
    func testDropsCaptureImagePaths() {
        let markdown = "![Capture](/Users/jane/Desktop/Mindspace/shot-1.png)"
        let clean = AppState.readable(markdown).lowercased()
        XCTAssertFalse(clean.contains("jane"), "a screenshot's path must not be searchable")
        XCTAssertFalse(clean.contains("desktop"))
        XCTAssertFalse(clean.contains("shot-1"))
    }

    func testDropsBarePathsAndFileNames() {
        let clean = AppState.readable("Source: /Users/jane/Sessions/x.json and voice-note.wav")
            .lowercased()
        XCTAssertFalse(clean.contains("jane"))
        XCTAssertFalse(clean.contains("voice-note"))
        XCTAssertTrue(clean.contains("source"))
    }

    func testKeepsRealWordsIncludingOnesThatLookLikePaths() {
        let clean = AppState.readable("Real content about jane the person should stay").lowercased()
        XCTAssertTrue(clean.contains("jane the person"))
    }

    func testKeepsLinkTextAndDropsDestination() {
        let clean = AppState.readable("The dashboard shows [the report](http://localhost:5175/dashboard)")
        XCTAssertTrue(clean.contains("the report"))
        XCTAssertFalse(clean.lowercased().contains("5175"))
    }

    func testStripsHeadingAndQuoteMarks() {
        let clean = AppState.readable("## Chrome · 3:16 PM\n> My thought: keep this")
        XCTAssertFalse(clean.contains("##"))
        XCTAssertTrue(clean.contains("Chrome"))
        XCTAssertTrue(clean.contains("keep this"))
    }
}
