import XCTest
import SwiftUI
@testable import NotefyApp

/// What a search result lights up, and what it leaves alone.
@MainActor
final class HighlightTests: XCTestCase {
    private func markedRanges(_ text: String, _ query: String?) -> Int {
        let attributed = Aurora.marked(text, query: query)
        return attributed.runs.filter { $0.backgroundColor != nil }.count
    }

    func testMarksEveryOccurrence() {
        XCTAssertEqual(markedRanges("aurora and more aurora", "aurora"), 2)
    }

    func testIgnoresCase() {
        XCTAssertEqual(markedRanges("The Dashboard", "dashboard"), 1)
    }

    func testNoQueryMarksNothing() {
        XCTAssertEqual(markedRanges("nothing to see", nil), 0)
        XCTAssertEqual(markedRanges("nothing to see", "   "), 0)
    }

    func testTextIsUnchanged() {
        let text = "keep every character — em dashes, accents: café"
        XCTAssertEqual(String(Aurora.marked(text, query: "accents").characters), text)
    }

    func testMarkSurvivesMultiByteCharacters() {
        // The offsets are counted in characters, not bytes: an emoji earlier in
        // the string used to shift the highlight off the match.
        let text = "🌙 the moon files it"
        let attributed = Aurora.marked(text, query: "moon")
        let marked = attributed.runs.first { $0.backgroundColor != nil }
        XCTAssertNotNil(marked)
        if let marked {
            XCTAssertEqual(String(attributed[marked.range].characters), "moon")
        }
    }
}
