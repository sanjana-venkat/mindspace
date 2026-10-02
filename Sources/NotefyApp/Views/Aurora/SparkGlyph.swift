import SwiftUI

/// Mindspace's spark: a four-pointed star with full, curved sides, and a
/// small one beside it.
///
/// The system "sparkle" is four thin points meeting at a dot, which at the
/// size a button uses reads as a plus sign. Curving the sides outward gives
/// the star a body, and the second, smaller star makes it unmistakably a
/// sparkle rather than an operator.
struct SparkGlyph: View {
    var size: CGFloat = 14

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SparkShape()
                .frame(width: size, height: size)
                .padding(.top, size * 0.22)
                .padding(.trailing, size * 0.22)
            SparkShape()
                .frame(width: size * 0.42, height: size * 0.42)
        }
        .frame(width: size * 1.22, height: size * 1.22)
        .accessibilityHidden(true)
    }
}

/// One four-pointed star whose sides bow slightly outward from straight.
struct SparkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        // How far each side's control point sits from the centre, toward the
        // diagonal. Zero gives thin spikes (the plus look); this gives a body.
        let k = r * 0.2
        let top = CGPoint(x: c.x, y: c.y - r)
        let right = CGPoint(x: c.x + r, y: c.y)
        let bottom = CGPoint(x: c.x, y: c.y + r)
        let left = CGPoint(x: c.x - r, y: c.y)
        var p = Path()
        p.move(to: top)
        p.addQuadCurve(to: right, control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: bottom, control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: left, control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: top, control: CGPoint(x: c.x - k, y: c.y - k))
        p.closeSubpath()
        return p
    }
}
