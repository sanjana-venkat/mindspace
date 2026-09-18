import XCTest
@testable import NotefyApp

/// The preview under a result and the place the result takes you have to come
/// from the same match. They used to be worked out separately.
final class SearchHitTests: XCTestCase {
    func testSnippetSurroundsTheMatch() {
        let text = "personalization research and marketing tiles jane reviewed research on customers"
        let snippet = AppState.snippet(of: text, around: "jane")
        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet!.contains("jane"))
        XCTAssertTrue(snippet!.contains("marketing tiles"), "the words before the match come along")
    }

    func testSnippetMarksWhereItWasCut() {
        let long = String(repeating: "word ", count: 60) + "jane " + String(repeating: "tail ", count: 60)
        let snippet = AppState.snippet(of: long, around: "jane")!
        XCTAssertTrue(snippet.hasPrefix("…"))
        XCTAssertTrue(snippet.hasSuffix("…"))
    }

    func testNoMatchIsNoSnippet() {
        XCTAssertNil(AppState.snippet(of: "nothing of the sort here", around: "jane"))
    }

    func testSnippetNeverCarriesAPath() {
        // What the index matches on is what the snippet is cut from, so a path
        // can neither produce a hit nor appear in the preview.
        let raw = "![Capture](/Users/jane/Desktop/shot.png)\nreal words about jane"
        let clean = AppState.readable(raw)
        XCTAssertNil(AppState.snippet(of: clean, around: "/users"))
        let snippet = AppState.snippet(of: clean, around: "jane")
        XCTAssertNotNil(snippet)
        XCTAssertFalse(snippet!.contains("Desktop"))
        XCTAssertFalse(snippet!.contains(".png"))
    }
}
