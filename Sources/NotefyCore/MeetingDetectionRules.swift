import Foundation

public enum MeetingDetectionRules {
    public static func isGoogleMeet(url: String?, title: String?) -> Bool {
        if let url,
           URL(string: url)?.host?.localizedCaseInsensitiveCompare("meet.google.com") == .orderedSame {
            return true
        }
        return title?.localizedCaseInsensitiveContains("Google Meet") == true
    }

    public static func isZoomMeetingWindow(_ title: String) -> Bool {
        title.localizedCaseInsensitiveContains("zoom meeting")
            || title.localizedCaseInsensitiveContains("zoom webinar")
            || title.localizedCaseInsensitiveContains("meeting controls")
    }
}
