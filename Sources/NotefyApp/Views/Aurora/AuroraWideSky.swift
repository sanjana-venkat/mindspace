import SwiftUI
import AppKit

/// Five illustrated moments joined into one landscape, with the app's window
/// as a camera on it. Moving through setup pans that whole strip to the left;
/// neither the mountain silhouette nor the ice dissolves between pages.
struct AuroraWideSky: View {
    /// 0 is the left end of the world, 1 the right.
    var pan: Double
    /// 0 tips the camera up into the sky, 1 down onto the ice.
    var tilt: Double = 0.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height

            ZStack(alignment: .topLeading) {
                Color(red: 0.035, green: 0.05, blue: 0.08)

                WorldSequence(progress: pan, tilt: tilt, width: w, height: h)
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .frame(width: w, height: h, alignment: .topLeading)
            .clipped()
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil }
            }
        }
        .ignoresSafeArea()
    }

}

// MARK: - the painted world

/// The five finished onboarding scenes, loaded once from the bundle. By URL
/// rather than asset name: they are loose files in the resource bundle, and
/// `Image(_:bundle:)` quietly draws nothing when it cannot find one.
enum World {
    static let scenes: [Image] = (1...5).compactMap { load("onboarding-aurora-\($0)") }

    private static func load(_ name: String) -> Image? {
        let tries = [("heic", "Scenery"), ("heic", nil), ("png", "Scenery"), ("png", nil)]
        for (ext, folder) in tries {
            let url = AuroraResources.url(name, extension: ext, subdirectory: folder)
            if let url, let image = NSImage(contentsOf: url), image.size.height > 0 {
                return Image(nsImage: image)
            }
        }
        return nil
    }
}

/// Lays the five scenes edge-to-edge as one panoramic strip. `progress` moves
/// the camera across four window-widths, which makes each Continue action feel
/// like travelling through the landscape instead of fading between backdrops.
struct WorldSequence: View {
    let progress: Double
    let tilt: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let clamped = max(0, min(1, progress))
        let count = max(1, World.scenes.count)
        // The paintings overlap at their joins. Only that narrow overlap is
        // feathered; the landscape itself remains a translating strip.
        let overlap = width * 0.20
        let stride = width - overlap
        let stripWidth = width + stride * CGFloat(max(0, count - 1))
        let travel = stripWidth - width
        let verticalOffset = (0.5 - max(0, min(1, tilt))) * height * 0.10

        ZStack(alignment: .leading) {
            ForEach(Array(World.scenes.indices), id: \.self) { index in
                World.scenes[index]
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height * 1.12)
                    .clipped()
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .white.opacity(index == 0 ? 1 : 0), location: 0),
                            .init(color: .white, location: 0.12),
                            .init(color: .white, location: 0.88),
                            .init(color: .white.opacity(index == count - 1 ? 1 : 0), location: 1)
                        ], startPoint: .leading, endPoint: .trailing)
                    }
                    .offset(x: CGFloat(index) * stride)
            }
        }
        .frame(width: stripWidth, height: height * 1.12, alignment: .leading)
        .offset(x: -CGFloat(clamped) * travel, y: verticalOffset)
        .frame(width: width, height: height, alignment: .leading)
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - thumbnail

/// A small, still view of the world, for showing what a choice looks like:
/// tipped up it is all aurora, tipped down it is all ice.
struct AuroraSceneThumbnail: View {
    /// 0 looks up into the sky, 1 looks down onto the ice.
    var tilt: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height

            ZStack {
                Color(red: 0.035, green: 0.05, blue: 0.08)
                if let scene = World.scenes.first {
                    scene
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: w, height: h,
                               alignment: tilt < 0.5 ? .top : .bottom)
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
    }
}
