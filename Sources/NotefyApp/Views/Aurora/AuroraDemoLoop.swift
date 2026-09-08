import SwiftUI

/// The opening screen's demonstration: a screen gets clipped, the clipping
/// becomes a card, a thought is written under it, a meeting is recorded, and a
/// summary arrives. Drawn rather than filmed, so it stays sharp, weighs
/// nothing, and never goes out of date with the UI.
struct AuroraDemoLoop: View {
    var dark: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cycle: Double = 13

    private var ink: Color { dark ? .white : Aurora.ink }
    private var faint: Color { dark ? .white.opacity(0.38) : Aurora.ink3.opacity(0.7) }
    private var panel: Color { dark ? .white.opacity(0.08) : .white.opacity(0.85) }
    private var edge: Color { dark ? .white.opacity(0.18) : Aurora.line }
    private let glow = Color(red: 0.42, green: 0.86, blue: 0.66)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 6.0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
            ZStack(alignment: .topLeading) {
                browser(t: t)
                    .frame(width: 300, height: 196)
                    .offset(x: 0, y: 14)

                captureCard(t: t)
                    .frame(width: 226)
                    .offset(x: 250, y: ramp(t, 2.0, 2.7, from: 40, to: 0))
                    .opacity(ramp(t, 2.0, 2.7, from: 0, to: 1) * fade(t, 11.4, 12.4))

                meetingCard(t: t)
                    .frame(width: 226)
                    .offset(x: 250, y: 150 + ramp(t, 6.6, 7.3, from: 30, to: 0))
                    .opacity(ramp(t, 6.6, 7.3, from: 0, to: 1) * fade(t, 11.4, 12.4))
            }
            .frame(width: 500, height: 300, alignment: .topLeading)
        }
    }

    // MARK: the screen being clipped

    private func browser(t: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(faint).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 3).fill(ink.opacity(0.55)).frame(width: 132, height: 8)
                ForEach([0.92, 0.78, 0.86, 0.6], id: \.self) { w in
                    RoundedRectangle(cornerRadius: 2).fill(faint).frame(width: 250 * w, height: 4)
                }
                RoundedRectangle(cornerRadius: 6)
                    .fill(glow.opacity(0.18))
                    .frame(height: 54)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(glow.opacity(0.25), lineWidth: 1))
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(edge, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            // the selection sweeping over the passage
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(glow, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(glow.opacity(0.10)))
                .frame(width: ramp(t, 0.5, 1.6, from: 0, to: 262),
                       height: ramp(t, 0.5, 1.6, from: 0, to: 74))
                .offset(x: 12, y: 100)
                .opacity(fade(t, 1.9, 2.4) * step(t, 0.5))
        }
    }

    // MARK: what it becomes

    private func captureCard(t: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("01").font(Aurora.mono(8)).foregroundStyle(faint)
                Text("chatgpt.com").font(Aurora.mono(8)).foregroundStyle(faint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))

            VStack(alignment: .leading, spacing: 5) {
                ForEach([0.88, 0.72, 0.8], id: \.self) { w in
                    RoundedRectangle(cornerRadius: 2).fill(faint).frame(width: 200 * w, height: 4)
                }
            }
            .padding(10)

            // the thought, typing in
            VStack(alignment: .leading, spacing: 5) {
                Text("YOUR THOUGHT").font(Aurora.mono(7.5)).tracking(1).foregroundStyle(glow.opacity(0.8))
                Text(typed("this is the bit I keep forgetting", t: t, from: 3.2, to: 5.6))
                    .font(Aurora.serif(11.5))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 26, alignment: .topLeading)
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(edge, lineWidth: 1))
    }

    // MARK: the meeting, and what comes back

    private func meetingCard(t: Double) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 0.92, green: 0.44, blue: 0.42))
                    .frame(width: 6, height: 6)
                    .opacity(0.5 + 0.5 * sin(t * 6))
                Text("MEETING").font(Aurora.mono(8)).tracking(1).foregroundStyle(faint)
                Spacer(minLength: 0)
                Text("12:04").font(Aurora.mono(8)).foregroundStyle(faint)
            }

            HStack(spacing: 3) {
                ForEach(0..<26, id: \.self) { i in
                    let live = step(t, 7.2) * fade(t, 9.4, 9.8)
                    let h = 3 + abs(sin(Double(i) * 0.7 + t * 3.2)) * 16 * live
                    Capsule().fill(glow.opacity(0.55 + 0.35 * live)).frame(width: 3, height: max(3, h))
                }
            }
            .frame(height: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 5) {
                Text("SUMMARY").font(Aurora.mono(7.5)).tracking(1).foregroundStyle(glow.opacity(0.8))
                ForEach(Array([0.9, 0.76, 0.84].enumerated()), id: \.offset) { index, w in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ink.opacity(0.42))
                        .frame(width: 200 * w, height: 4)
                        .opacity(ramp(t, 9.9 + Double(index) * 0.25, 10.3 + Double(index) * 0.25, from: 0, to: 1))
                }
            }
            .opacity(step(t, 9.9))
        }
        .padding(11)
        .background(panel)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(edge, lineWidth: 1))
    }

    // MARK: timing helpers

    /// Eased interpolation between two values across a window of the cycle.
    private func ramp(_ t: Double, _ start: Double, _ end: Double, from: Double, to: Double) -> Double {
        guard t > start else { return from }
        guard t < end else { return to }
        let p = (t - start) / (end - start)
        let eased = p * p * (3 - 2 * p)
        return from + (to - from) * eased
    }

    private func step(_ t: Double, _ at: Double) -> Double { t >= at ? 1 : 0 }

    private func fade(_ t: Double, _ start: Double, _ end: Double) -> Double {
        guard t > start else { return 1 }
        guard t < end else { return 0 }
        return 1 - (t - start) / (end - start)
    }

    private func typed(_ text: String, t: Double, from: Double, to: Double) -> String {
        guard t > from else { return "" }
        guard t < to else { return text }
        let p = (t - from) / (to - from)
        return String(text.prefix(Int(Double(text.count) * p)))
    }
}
