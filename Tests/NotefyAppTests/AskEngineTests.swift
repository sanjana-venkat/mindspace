import XCTest
@testable import NotefyApp

final class AskEngineTests: XCTestCase {
    /// The answer that showed only one chip: [2, 3] and [6, 7] were dropped.
    func testCitationsReadListsAndSingles() {
        let answer = "You saved methods [2, 3], a voice note [4], and an overview [6,7]."
        XCTAssertEqual(AskEngine.citations(in: answer), [2, 3, 4, 6, 7])
    }

    func testCitationsReadRangesAndAdjacentBrackets() {
        XCTAssertEqual(AskEngine.citations(in: "See [2-4][9]."), [2, 3, 4, 9])
    }

    func testCitationsIgnoreBracketedProse() {
        XCTAssertEqual(AskEngine.citations(in: "A [link](x) and [note] but [1]"), [1])
    }

    func testPickedIndicesTolerateFencesAndDuplicates() {
        XCTAssertEqual(AskEngine.pickedIndices(in: "```json\n[4, 17, 4, 2]\n```"), [4, 17, 2])
        XCTAssertEqual(AskEngine.pickedIndices(in: "[]"), [])
        XCTAssertEqual(AskEngine.pickedIndices(in: "no array here"), [])
    }
}
