import XCTest
@testable import NotefyCore

final class MeetingDetectionRulesTests: XCTestCase {
    func testRecognizesGoogleMeetByURL() {
        XCTAssertTrue(MeetingDetectionRules.isGoogleMeet(
            url: "https://meet.google.com/abc-defg-hij",
            title: "Weekly sync"
        ))
    }

    func testRecognizesGoogleMeetByTitle() {
        XCTAssertTrue(MeetingDetectionRules.isGoogleMeet(url: nil, title: "Team sync - Google Meet"))
    }

    func testDoesNotTreatOrdinaryGooglePageAsMeeting() {
        XCTAssertFalse(MeetingDetectionRules.isGoogleMeet(
            url: "https://docs.google.com/document/d/example",
            title: "Project brief"
        ))
    }

    func testRecognizesZoomMeetingWindowsButNotZoomHome() {
        XCTAssertTrue(MeetingDetectionRules.isZoomMeetingWindow("Sanjana's Zoom Meeting"))
        XCTAssertTrue(MeetingDetectionRules.isZoomMeetingWindow("Zoom Webinar"))
        XCTAssertFalse(MeetingDetectionRules.isZoomMeetingWindow("Zoom Workplace"))
    }
}
