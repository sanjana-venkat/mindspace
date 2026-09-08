import SwiftUI
import NotefyCore

/// The organized note: the model's structure over the same captures, with the
/// sources it was built from listed underneath so any line can be checked.
struct AuroraOrganized: View {
    let steps: [ExplorationStep]
    var onJump: (Int) -> Void

    @EnvironmentObject private var appState: AppState

    private var blocks: [AuroraDocBlock] { AuroraDocBlock.parse(appState.organizedDraft) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                head

                if appState.isOrganizing {
                    working
                } else if blocks.isEmpty {
                    empty
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        AuroraDocBlockView(block: block)
                    }
                    // The model's own write-up already cites its sources; only
                    // add the list when it hasn't.
                    if !mentionsSources { sources }
                }
                Spacer(minLength: 120)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, 40).padding(.horizontal, 40)
        }
        .scrollIndicators(.never)
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text(providerLabel)
                    .font(Aurora.mono(10)).tracking(1.3).textCase(.uppercase)
                .foregroundStyle(Aurora.accent)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Aurora.accentSoft, in: Capsule())

                Spacer()

                ForEach(OrganizationTemplate.offered) { t in
                    Button {
                        appState.showOrganized(t)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: t.icon).font(.system(size: 10.5, weight: .semibold))
                            Text(t.rawValue).font(Aurora.ui(11.5))
                        }
                        .foregroundStyle(appState.organizedTemplate == t ? Aurora.ground : Aurora.ink)
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .background(appState.organizedTemplate == t ? AnyShapeStyle(Aurora.ink) : AnyShapeStyle(Color.clear),
                                    in: Capsule())
                        .overlay(Capsule().strokeBorder(appState.organizedTemplate == t ? .clear : Aurora.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isOrganizing)
                    .help("Rewrite this note as \(t.rawValue.lowercased())")
                }
            }

            if let status = appState.recordingStatus, !status.isEmpty {
                Text(status).font(Aurora.ui(12, .medium)).foregroundStyle(Aurora.ink3)
            }

            HStack(spacing: 10) {
                Text("\(steps.count) captures")
                Circle().fill(Aurora.ink3).frame(width: 3, height: 3)
                Text("\(sourceNames.count) sources")
                if let graph = appState.organizedGraph {
                    Circle().fill(Aurora.ink3).frame(width: 3, height: 3)
                    Text("\(graph.nodes.count) threads")
                }
            }
            .font(Aurora.ui(12, .medium))
            .foregroundStyle(Aurora.ink2)
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Aurora.line).frame(height: 1) }
    }

    private var providerLabel: String {
        switch appState.settings.vision.provider {
        case .local: return "Organized on-device · \(appState.settings.vision.modelName)"
        case .gemini: return "Organized by Gemini"
        case .anthropic: return "Organized by Claude"
        case .api: return "Organized by \(appState.settings.vision.modelName)"
        }
    }

    private var working: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Reading \(steps.count) captures and writing it up…")
                .font(Aurora.serif(17)).foregroundStyle(Aurora.ink2)
        }
        .padding(.vertical, 30)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nothing organized yet.")
                .font(Aurora.serif(24)).foregroundStyle(Aurora.ink)
            Text("Pick a shape above and the model will read every capture in this note — the screenshots, the text you clipped, and the thoughts you wrote beside them — and write it up.")
                .font(Aurora.serif(17)).foregroundStyle(Aurora.ink2).lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                appState.organizeCurrentSession(as: appState.organizedTemplate)
            } label: {
                Text("Organize this note")
                    .font(Aurora.ui(14, .bold))
                    .foregroundStyle(Aurora.ground)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Aurora.ink, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(steps.isEmpty)
            .padding(.top, 4)
        }
        .padding(.vertical, 10)
    }

    /// True when the organized text already carries a sources section, so the
    /// app doesn't print a second one underneath it.
    private var mentionsSources: Bool {
        blocks.contains { block in
            if case .heading(let t) = block { return t.lowercased().contains("source") }
            if case .subheading(let t) = block { return t.lowercased().contains("source") }
            return false
        }
    }

    private var sourceNames: [String] {
        var seen: [String] = []
        for s in steps {
            let name = URL(string: s.url ?? "")?.host ?? s.appName
            if !seen.contains(name) { seen.append(name) }
        }
        return seen
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SOURCES")
                .font(Aurora.mono(10.5)).tracking(1.6).foregroundStyle(Aurora.ink)
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                Button { onJump(i) } label: {
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", i + 1))
                            .font(Aurora.mono(10)).foregroundStyle(Aurora.ink3)
                        Text(step.windowTitle.isEmpty ? step.appName : step.windowTitle)
                            .font(Aurora.ui(13, .medium)).foregroundStyle(Aurora.ink).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(URL(string: step.url ?? "")?.host ?? step.appName)
                            .font(Aurora.mono(10.5)).foregroundStyle(Aurora.ink3)
                        Image(systemName: "arrow.up.right").font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Aurora.ink3)
                    }
                    .padding(.vertical, 9).padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AuroraHoverRow())
            }
        }
    }
}

/// Just enough Markdown for what the model returns.
enum AuroraDocBlock: Hashable {
    case title(String)
    case heading(String)
    case subheading(String)
    case bullet(String)
    case quote(String)
    case paragraph(String)

    static func parse(_ markdown: String) -> [AuroraDocBlock] {
        var out: [AuroraDocBlock] = []
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("### ") { out.append(.subheading(String(line.dropFirst(4)))) }
            else if line.hasPrefix("## ") { out.append(.heading(String(line.dropFirst(3)))) }
            else if line.hasPrefix("# ") { out.append(.title(String(line.dropFirst(2)))) }
            else if line.hasPrefix("> ") { out.append(.quote(String(line.dropFirst(2)))) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") { out.append(.bullet(String(line.dropFirst(2)))) }
            else if line.hasPrefix("---") { continue }
            else { out.append(.paragraph(line)) }
        }
        return out
    }
}

struct AuroraDocBlockView: View {
    let block: AuroraDocBlock

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }

    var body: some View {
        switch block {
        case .title(let t):
            Text(inline(t))
                .font(Aurora.serif(28, .semibold))
                .foregroundStyle(Aurora.ink)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let t):
            HStack(spacing: 10) {
                Text(t.uppercased())
                    .font(Aurora.mono(10.5)).tracking(1.6).foregroundStyle(Aurora.ink)
                Rectangle().fill(Aurora.line).frame(height: 1)
            }
            .padding(.top, 8)
        case .subheading(let t):
            Text(inline(t))
                .font(Aurora.title(16)).foregroundStyle(Aurora.ink)
        case .bullet(let t):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Circle().fill(Aurora.accent).frame(width: 5, height: 5)
                Text(inline(t))
                    .font(Aurora.serif(17)).foregroundStyle(Aurora.ink)
                    .lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            }
        case .quote(let t):
            Text(inline(t))
                .font(Aurora.serif(17)).foregroundStyle(Aurora.ink2)
                .lineSpacing(6).italic()
                .padding(.leading, 16)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Aurora.accent).frame(width: 3)
                }
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph(let t):
            Text(inline(t))
                .font(Aurora.serif(17)).foregroundStyle(Aurora.ink)
                .lineSpacing(6).fixedSize(horizontal: false, vertical: true)
        }
    }
}
