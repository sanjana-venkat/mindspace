import Foundation

/// Where the app's own pictures live, found without ever trapping.
///
/// SwiftPM generates `Bundle.module` as a `static let` whose last act, if it
/// cannot find the resource bundle, is `fatalError`. That is a reasonable
/// default for a library and a terrible one for an app: it runs inside a
/// `dispatch_once`, so the trap fires wherever the first lookup happens —
/// which for Mindspace 0.1.5 was `MoonPetState.init()`, inside `AppState.init()`,
/// inside SwiftUI building the menu bar scene. The app died before it had a
/// window, on every Mac running macOS 15, because the bundle it ships was
/// missing an `Info.plist` and `Bundle(url:)` there refuses a bundle without
/// one. A missing texture should cost a picture, not the launch.
///
/// So the search is done here, by hand, and answers `nil` when it comes up
/// empty. Every caller already has a drawn fallback.
enum AuroraResources {
    private static let bundleName = "Notefy_NotefyApp"

    /// The resource bundle, if it can be found. Resolved once and kept.
    static let bundle: Bundle? = {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources) }
        candidates.append(Bundle.main.bundleURL)
        // Alongside the executable, which is where a command-line build puts it.
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent())
        if let finder = Bundle(for: BundleFinder.self).resourceURL { candidates.append(finder) }

        for candidate in candidates {
            let url = candidate.appendingPathComponent("\(bundleName).bundle")
            if let bundle = Bundle(url: url) { return bundle }
            // A bundle macOS won't open — no Info.plist, as shipped in 0.1.5 —
            // is still a directory full of the right files.
            if FileManager.default.fileExists(atPath: url.path) { return nil }
        }
        return nil
    }()

    /// The directory the resources sit in, whether or not macOS calls it a
    /// bundle. This is the fallback that makes a malformed bundle harmless.
    private static let directory: URL? = {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources) }
        candidates.append(Bundle.main.bundleURL)
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent())

        for candidate in candidates {
            let url = candidate.appendingPathComponent("\(bundleName).bundle")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return url
            }
        }
        return nil
    }()

    /// A resource by name, looked for in the bundle first and then in the
    /// directory itself — flat, and under the subdirectory it was declared in.
    static func url(_ name: String, extension ext: String, subdirectory: String? = nil) -> URL? {
        if let bundle {
            if let subdirectory,
               let found = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
                return found
            }
            if let found = bundle.url(forResource: name, withExtension: ext) { return found }
        }

        guard let directory else { return nil }
        let manager = FileManager.default
        var places = [directory]
        if let subdirectory { places.insert(directory.appendingPathComponent(subdirectory), at: 0) }
        places.append(directory.appendingPathComponent("Contents/Resources"))

        for place in places {
            let candidate = place.appendingPathComponent("\(name).\(ext)")
            if manager.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

private final class BundleFinder {}
