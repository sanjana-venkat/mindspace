import SwiftUI

// ============================================================
// INK SPLATTER — the pigment carried across the empty canvas.
// Same cobalt hue as the accent, always at bloom strength. Never
// a second colour, never grey. Sits below every panel and text
// node, at fixed anchors — placed, not generated, so the mark set
// is identical on every load. Ported from the Noted pigment pass.
// ============================================================

/// A single organic, irregular body traced through a fixed set of
/// hand-placed points (smoothed with quad curves) rather than a circle —
/// a blurred circle reads as a gradient blob, not ink. `variant` selects
/// one of a few fixed point-sets so different marks don't share an edge,
/// without any runtime randomness.
private struct OrganicBlob: Shape {
    var variant: Int

    private static let pointSets: [[CGPoint]] = [
        [
            CGPoint(x: 0.50, y: 0.03), CGPoint(x: 0.79, y: 0.11), CGPoint(x: 0.95, y: 0.35),
            CGPoint(x: 0.87, y: 0.63), CGPoint(x: 0.67, y: 0.83), CGPoint(x: 0.42, y: 0.97),
            CGPoint(x: 0.17, y: 0.87), CGPoint(x: 0.03, y: 0.59), CGPoint(x: 0.11, y: 0.31),
            CGPoint(x: 0.29, y: 0.09),
        ],
        [
            CGPoint(x: 0.46, y: 0.02), CGPoint(x: 0.74, y: 0.08), CGPoint(x: 0.97, y: 0.28),
            CGPoint(x: 0.93, y: 0.55), CGPoint(x: 0.98, y: 0.78), CGPoint(x: 0.71, y: 0.93),
            CGPoint(x: 0.45, y: 0.99), CGPoint(x: 0.21, y: 0.90), CGPoint(x: 0.02, y: 0.68),
            CGPoint(x: 0.07, y: 0.40), CGPoint(x: 0.22, y: 0.14),
        ],
        [
            CGPoint(x: 0.52, y: 0.05), CGPoint(x: 0.83, y: 0.16), CGPoint(x: 0.92, y: 0.44),
            CGPoint(x: 0.79, y: 0.70), CGPoint(x: 0.55, y: 0.90), CGPoint(x: 0.30, y: 0.95),
            CGPoint(x: 0.08, y: 0.76), CGPoint(x: 0.06, y: 0.46), CGPoint(x: 0.20, y: 0.20),
        ],
    ]

    func path(in rect: CGRect) -> Path {
        let points = Self.pointSets[variant % Self.pointSets.count]
            .map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for i in 0..<points.count {
            let current = points[i]
            let next = points[(i + 1) % points.count]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: current)
        }
        path.closeSubpath()
        return path
    }
}

/// Four to six placed marks, never a random field. Non-negotiable: nothing
/// at ink strength, nothing overlapping a text bounding box, ≤ 7% opacity
/// each, ≤ ~12% of canvas covered in total.
struct InkSplatterField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private struct Mark: Identifiable {
        let id: Int
        let anchor: UnitPoint
        let size: CGFloat
        let opacity: Double
        let rotation: Angle
        let kind: Kind
        let delay: Double
    }
    private enum Kind { case blot, spray, bleed, fleck }

    private let marks: [Mark] = [
        Mark(id: 0, anchor: UnitPoint(x: 0.12, y: 0.18), size: 56, opacity: 0.032,
             rotation: .degrees(-18), kind: .fleck, delay: 0.00),
        Mark(id: 1, anchor: UnitPoint(x: 0.88, y: 0.26), size: 300, opacity: 0.026,
             rotation: .degrees(0), kind: .bleed, delay: 0.06),
        Mark(id: 2, anchor: UnitPoint(x: 0.28, y: 0.72), size: 190, opacity: 0.040,
             rotation: .degrees(34), kind: .blot, delay: 0.12),
        Mark(id: 3, anchor: UnitPoint(x: 0.64, y: 0.88), size: 230, opacity: 0.034,
             rotation: .degrees(12), kind: .spray, delay: 0.18),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(marks) { m in
                    markView(m)
                        .frame(width: m.size, height: m.size)
                        .rotationEffect(m.rotation)
                        // A little blur breaks up the vector edge so it
                        // reads as ink rather than a flat cut-out shape —
                        // the spec's own filter ends in a soft blur too.
                        .blur(radius: 3)
                        .position(x: proxy.size.width * m.anchor.x, y: proxy.size.height * m.anchor.y)
                        .opacity((appeared || reduceMotion) ? m.opacity : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(m.delay), value: appeared)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { appeared = true }
    }

    @ViewBuilder
    private func markView(_ m: Mark) -> some View {
        switch m.kind {
        case .blot:
            // One dense body, two or three satellite droplets.
            ZStack {
                OrganicBlob(variant: 0).fill(Stoneink.cobalt600)
                Circle().fill(Stoneink.cobalt600).frame(width: 20, height: 20).offset(x: 48, y: -34)
                Circle().fill(Stoneink.cobalt600).frame(width: 10, height: 10).offset(x: 66, y: -10)
            }
        case .bleed:
            // Soft irregular halo, no droplets — sits directly under an edge.
            OrganicBlob(variant: 1).fill(Stoneink.cobalt600)
        case .spray:
            // Small droplets on a directional arc — implies motion.
            ZStack {
                ForEach(0..<10, id: \.self) { i in
                    let t = Double(i) / 9.0
                    let arc = Angle.degrees(200 + t * 70)
                    let radius = 0.30 + t * 0.62
                    let size: CGFloat = 20 - CGFloat(t) * 13
                    Circle()
                        .fill(Stoneink.cobalt600)
                        .frame(width: size, height: size)
                        .offset(
                            x: CGFloat(cos(arc.radians)) * radius * 140,
                            y: CGFloat(sin(arc.radians)) * radius * 140
                        )
                }
            }
        case .fleck:
            // Three to five tiny droplets — punctuation, not a presence.
            ZStack {
                Circle().fill(Stoneink.cobalt600).frame(width: 26, height: 26)
                Circle().fill(Stoneink.cobalt600).frame(width: 12, height: 12).offset(x: 24, y: 14)
                Circle().fill(Stoneink.cobalt600).frame(width: 7, height: 7).offset(x: -16, y: 20)
                Circle().fill(Stoneink.cobalt600).frame(width: 8, height: 8).offset(x: 10, y: -20)
            }
        }
    }
}

/// The one anchor tied to a specific element rather than the canvas at
/// large: a soft bleed sitting behind the "MY THOUGHT" wash block, so the
/// highlighter reads as soaked into the surface instead of pasted on top.
struct InkWashBleed: View {
    var body: some View {
        OrganicBlob(variant: 2)
            .fill(Stoneink.cobalt600)
            .opacity(0.07)
            .frame(width: 160, height: 90)
            .offset(x: -16, y: 10)
            .allowsHitTesting(false)
    }
}
