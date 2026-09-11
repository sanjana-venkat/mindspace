import SwiftUI
import NotefyCore

/// A captured page, selection or transcript, drawn as a plate. Screenshots keep
/// their own aspect ratio; text captures set in the reading serif.
struct AuroraCaptureView: View {
    let step: ExplorationStep
    var index: Int
    /// Caps the lines of a text capture; nil lets it run to full length.
    var textLimit: Int? = nil
    /// Fixed image height for grid tiles; `nil` lets a screenshot run to its
    /// natural height in the reading column.
    var imageHeight: CGFloat? = nil

    /// Text captures all take the same green wash — mixed hues made some
    /// plates read grey and some green for no reason the reader could see.
    private var tint: Int { 0 }

    private var source: String {
        if let url = step.url, let host = URL(string: url)?.host { return host }
        if !step.windowTitle.isEmpty { return step.windowTitle }
        return step.appName
    }

    private var text: String? {
        if let t = step.selectedText, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
        if let t = step.pageText, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text(String(format: "%02d", index + 1))
                    .font(Aurora.mono(9.5))
                    .foregroundStyle(Aurora.ink2)
                    .padding(.horizontal, 6).padding(.vertical, 2.5)
                    .background(Aurora.surface, in: Capsule())
                Text(source)
                    .font(Aurora.mono(9.5))
                    .foregroundStyle(Aurora.ink3)
                    .lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Aurora.surface2, in: Capsule())
                Spacer(minLength: 0)
                Text(step.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(Aurora.mono(9.5)).foregroundStyle(Aurora.ink3)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(Aurora.surface2.opacity(0.75))

            content
        }
        .background(Aurora.surface2)
    }

    @ViewBuilder
    private var content: some View {
        if let path = step.screenshotPath, let image = NSImage(contentsOfFile: path) {
            if let imageHeight {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: imageHeight)
                    .clipped()
            } else {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            }
        } else if let text {
            ZStack {
                LinearGradient(colors: [Aurora.tint(tint).opacity(0.22), Aurora.tint(tint).opacity(0.06)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(text)
                    .font(Aurora.serif(15))
                    .lineSpacing(5)
                    .foregroundStyle(Aurora.ink)
                    .textSelection(.enabled)
                    .lineLimit(textLimit ?? (imageHeight == nil ? nil : 7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(height: imageHeight)
        }
    }
}
