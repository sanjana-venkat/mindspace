import XCTest
import SwiftUI
@testable import NotefyApp

/// The ring has to stay on the screen: against an edge it swings to whichever
/// side has room, and the labels follow.
@MainActor
final class MoonRingTests: XCTestCase {
    private func ring(_ configure: (MoonPetState) -> Void) -> [CGPoint] {
        let state = MoonPetState()
        configure(state)
        let view = MoonPetView(state: state)
        return (0..<4).map { view.ringPosition($0, of: 4, radius: 74) }
    }

    func testDefaultArcSitsAboveTheMoon() {
        let points = ring { _ in }
        XCTAssertTrue(points.allSatisfy { $0.y < 0 }, "the ring belongs overhead when there is room")
        XCTAssertLessThan(points.first!.x, 0, "it runs left to right")
        XCTAssertGreaterThan(points.last!.x, 0)
    }

    func testAgainstTheRightEdgeTheRingSwingsLeft() {
        let points = ring { $0.roomRight = false }
        XCTAssertTrue(points.allSatisfy { $0.x < 0 }, "no icon may open off the right of the screen")
    }

    func testAgainstTheLeftEdgeTheRingSwingsRight() {
        let points = ring { $0.roomLeft = false }
        XCTAssertTrue(points.allSatisfy { $0.x > 0 })
    }

    func testAgainstTheTopTheRingHangsBelow() {
        let points = ring { $0.roomAbove = false }
        XCTAssertTrue(points.allSatisfy { $0.y > 0 }, "at the top of the screen the icons hang underneath")
    }

    func testEveryIconKeepsItsDistanceFromTheMoon() {
        for points in [ring { _ in }, ring { $0.roomRight = false }, ring { $0.roomAbove = false }] {
            for point in points {
                XCTAssertEqual(hypot(point.x, point.y), 74, accuracy: 0.001)
            }
        }
    }
}
