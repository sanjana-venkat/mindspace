import AppKit
import SwiftUI

/// The capture rail's icon set. The rail itself is gone — the moon on the
/// desktop carries these actions now, in a ring that opens when you hover it —
/// but the drawings are the app's own and are still what the ring, the review
/// panel and the recording notepad use.

struct OverlayIcon: View {
    enum Kind { case capture, text, audio, meeting, microphone, window, region, spark, systemAudio }
    let kind: Kind
    var tint: Color = NotefyTheme.ink

    var body: some View {
        Canvas { context, size in
            let sx = size.width / 24
            let sy = size.height / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
            func stroke(_ path: Path, dashed: Bool = false) {
                context.stroke(
                    path,
                    with: .color(tint),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: dashed ? [3, 3] : [])
                )
            }
            var path = Path()
            switch kind {
            case .capture:
                path.move(to: p(4,8)); path.addLine(to: p(4,6)); path.addQuadCurve(to: p(6,4), control: p(4,4)); path.addLine(to: p(8,4))
                path.move(to: p(16,4)); path.addLine(to: p(18,4)); path.addQuadCurve(to: p(20,6), control: p(20,4)); path.addLine(to: p(20,8))
                path.move(to: p(20,16)); path.addLine(to: p(20,18)); path.addQuadCurve(to: p(18,20), control: p(20,20)); path.addLine(to: p(16,20))
                path.move(to: p(8,20)); path.addLine(to: p(6,20)); path.addQuadCurve(to: p(4,18), control: p(4,20)); path.addLine(to: p(4,16)); stroke(path)
                stroke(Path(ellipseIn: CGRect(x: 8.8*sx, y: 8.8*sy, width: 6.4*sx, height: 6.4*sy)))
            case .systemAudio:
                // A display with sound coming off it — computer audio, rather
                // than the waveform that now belongs to meetings.
                path.addRoundedRect(in: CGRect(x: 3*sx, y: 5*sy, width: 13*sx, height: 10*sy),
                                    cornerSize: CGSize(width: 2*sx, height: 2*sy))
                path.move(to: p(7,19)); path.addLine(to: p(12,19))
                path.move(to: p(9.5,15)); path.addLine(to: p(9.5,19))
                stroke(path)
                var waves = Path()
                waves.move(to: p(18,8)); waves.addQuadCurve(to: p(18,16), control: p(21,12))
                waves.move(to: p(20.5,6)); waves.addQuadCurve(to: p(20.5,18), control: p(24,12))
                stroke(waves)
            case .spark:
                // Four-point star, drawn on the same grid and stroke as the rest.
                path.move(to: p(12,3))
                path.addCurve(to: p(21,12), control1: p(12,9), control2: p(15,12))
                path.addCurve(to: p(12,21), control1: p(15,12), control2: p(12,15))
                path.addCurve(to: p(3,12), control1: p(12,15), control2: p(9,12))
                path.addCurve(to: p(12,3), control1: p(9,12), control2: p(12,9))
                stroke(path)
            case .text:
                path.move(to: p(5,7)); path.addCurve(to: p(6.5,10.5), control1: p(5,4.5), control2: p(10,3.5)); path.addCurve(to: p(10,7), control1: p(8,10), control2: p(10,9))
                path.move(to: p(13,7)); path.addCurve(to: p(14.5,10.5), control1: p(13,4.5), control2: p(18,3.5)); path.addCurve(to: p(18,7), control1: p(16,10), control2: p(18,9))
                path.move(to: p(5,15)); path.addLine(to: p(19,15)); path.move(to: p(5,19)); path.addLine(to: p(14,19)); stroke(path)
            case .audio:
                for (x, y1, y2) in [(4,10,14),(8,7,17),(12,4,20),(16,8,16),(20,10,14)] {
                    path.move(to: p(CGFloat(x),CGFloat(y1))); path.addLine(to: p(CGFloat(x),CGFloat(y2)))
                }; stroke(path)
            case .meeting:
                stroke(Path(ellipseIn: CGRect(x: 6*sx, y: 6*sy, width: 6*sx, height: 6*sy)))
                stroke(Path(ellipseIn: CGRect(x: 14.3*sx, y: 7.8*sy, width: 4.4*sx, height: 4.4*sy)))
                path.move(to: p(3.5,19)); path.addCurve(to: p(14.5,19), control1: p(4.5,13), control2: p(13.5,13)); path.move(to: p(16,15.6)); path.addCurve(to: p(20,19), control1: p(18,16), control2: p(19.4,17)); stroke(path)
            case .microphone:
                path.addRoundedRect(in: CGRect(x: 9*sx, y: 3.5*sy, width: 6*sx, height: 11*sy), cornerSize: CGSize(width: 3*sx, height: 3*sy)); path.move(to: p(5.5,11.5)); path.addCurve(to: p(18.5,11.5), control1: p(5.5,20), control2: p(18.5,20)); path.move(to: p(12,18)); path.addLine(to: p(12,20.5)); stroke(path)
            case .window:
                path.addRoundedRect(in: CGRect(x: 3.5*sx, y: 5*sy, width: 17*sx, height: 14*sy), cornerSize: CGSize(width: 2*sx, height: 2*sy)); path.move(to: p(3.5,9)); path.addLine(to: p(20.5,9)); stroke(path)
            case .region:
                path.addRoundedRect(in: CGRect(x: 5*sx, y: 5*sy, width: 14*sx, height: 14*sy), cornerSize: CGSize(width: 1.5*sx, height: 1.5*sy)); stroke(path, dashed: true)
            }
        }
        .foregroundStyle(NotefyTheme.ink)
    }
}


/// Frosted backing for the floating rail.
///
/// `.behindWindow` blending is what makes it real glass: the material samples
/// the desktop behind the panel rather than the panel's own contents. The
/// panel is already non-opaque with a clear background, which is the
/// precondition — without that the effect view has nothing to sample.
///
/// The shape comes from `maskImage` rather than a SwiftUI clip, because a
/// clip applied over an NSViewRepresentable does not reliably reach the
/// effect view's own layer.
private struct RailGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        // Pinned light, like the main window: the rail's glyphs are ink, and
        // a dark material under them would leave them unreadable on a dark
        // desktop.
        view.appearance = NSAppearance(named: .aqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        let radius = max(1, min(view.bounds.width, view.bounds.height) / 2)
        view.maskImage = Self.capsuleMask(radius: radius)
    }

    private static func capsuleMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 2
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
