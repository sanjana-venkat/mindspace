import AppKit
import SwiftUI
import NotefyCore

private enum NoteViewMode: String, CaseIterable, Identifiable {
    case raw = "Raw"
    case organized = "Organized"
    var id: String { rawValue }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var mode: NoteViewMode = .raw
    @State private var showOrganizationChoices = false
    @State private var isSelecting = false
    @State private var showMovePicker = false
    @State private var showForwardPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabStrip
            ZStack {
                pageViewport
            }
            .overlay(alignment: .bottom) { actionShelf }
        }
        .padding(.horizontal, 46)
        .padding(.top, 80)
        .background(Color.clear)
    }

    @ViewBuilder
    private var pageViewport: some View {
        if mode == .raw {
            // Raw owns its scroll view so trackpad/wheel input reaches the
            // paired capture stream directly instead of being intercepted by
            // the dashboard's outer page scroller.
            rawPage
                .padding(.horizontal, 42)
                .padding(.top, 12)
                .padding(.bottom, 110)
        } else {
            ScrollView {
                pageContent
                    .padding(.horizontal, 42)
                    .padding(.top, 12)
                    .padding(.bottom, 110)
            }
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 2) {
            tabButton(title: "Raw captures", mode: .raw)
            tabButton(title: "Organized", mode: .organized)
        }
        .padding(3)
        .background(NotefyTheme.sandDeep, in: Capsule())
        .grain()
        .clipShape(Capsule())
        .overlay(Capsule().stroke(NotefyTheme.glassBorderSoft, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 22)
        .zIndex(3)
    }

    private func tabButton(title: String, mode candidate: NoteViewMode) -> some View {
        let isActive = candidate == mode
        return Button {
            mode = candidate
        } label: {
            Text(title)
                .font(NotefyFont.bodyMedium)
                .foregroundStyle(isActive ? NotefyTheme.inkStrong : NotefyTheme.inkMuted)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    if isActive {
                        Capsule().fill(NotefyTheme.cardPaper).emboss()
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pageContent: some View {
        if mode == .raw {
            rawPage
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("ACTIVE NOTE · SAVES AUTOMATICALLY")
                    .font(NotefyFont.label)
                    .tracking(1.4)
                    .foregroundStyle(NotefyTheme.inkSoft)
                    .padding(.bottom, 6)

                TextField("Name this note", text: $appState.noteTitle, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(NotefyFont.pageTitle)
                    .foregroundStyle(NotefyTheme.ink)
                    .lineLimit(1...2)
                    .onSubmit { appState.saveActiveNote() }

                Text(metaText)
                    .font(NotefyFont.caption)
                    .tracking(0.9)
                    .foregroundStyle(NotefyTheme.inkFaint)
                    .padding(.top, 9)
                    .padding(.bottom, 30)

                organizedPage
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The left column beside the capture stage: title, meta, and the note's
    /// source tags — plain typography, no box, per the source frame.
    private var rawNoteHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ACTIVE NOTE · SAVES AUTOMATICALLY")
                .font(NotefyFont.label)
                .tracking(1.4)
                .foregroundStyle(NotefyTheme.inkSoft)
                .padding(.bottom, 6)

            TextField("Name this note", text: $appState.noteTitle, axis: .vertical)
                .textFieldStyle(.plain)
                .font(NotefyFont.pageTitle)
                .foregroundStyle(NotefyTheme.ink)
                .lineSpacing(2)
                .onSubmit { appState.saveActiveNote() }
                .fixedSize(horizontal: false, vertical: true)

            Text(metaText)
                .font(NotefyFont.caption)
                .tracking(0.9)
                .foregroundStyle(NotefyTheme.inkFaint)
                .padding(.top, 9)

            if !sourceTags.isEmpty {
                FlowTags(tags: sourceTags)
                    .padding(.top, 22)
            }
        }
    }

    private var rawPage: some View {
        GeometryReader { proxy in
            let panelWidth = min(500, max(390, proxy.size.width * 0.54))
            let columnGap: CGFloat = 34
            let leftWidth = max(280, proxy.size.width - panelWidth - columnGap)
            let captureWidth = panelWidth - 48
            let steps = Array(appState.steps.reversed())

            ZStack(alignment: .topTrailing) {
                // This is a fixed viewport. The shared stream below is sized
                // to its exact inner width so cards can never escape the well.
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(NotefyTheme.sandDeep)
                    .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(NotefyTheme.glassBorder, lineWidth: 1))
                    .grain()
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .neomorphicDeboss(cornerRadius: 32)
                    .frame(width: panelWidth, height: 620)
                    .overlay {
                        if steps.isEmpty {
                            emptyPaper
                                .padding(28)
                                .frame(width: panelWidth, height: 620, alignment: .center)
                        }
                    }

                // One scroll stream owns paired rows. A note and its capture
                // leave the viewport together, so the next pair is revealed
                // as one coherent unit rather than as two drifting columns.
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 28) {
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 28) {
                                rawNoteHeader
                                if let first = steps.first {
                                    rawThoughtBlock(first)
                                }
                            }
                            .frame(width: leftWidth, alignment: .leading)

                            if let first = steps.first {
                                rawCaptureBlock(first)
                                    .padding(.horizontal, 24)
                                    .frame(width: captureWidth, alignment: .leading)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 1, alignment: .trailing)
                            }
                        }
                        .frame(width: proxy.size.width, alignment: .topLeading)

                        ForEach(Array(steps.dropFirst())) { step in
                            ZStack(alignment: .topLeading) {
                                rawThoughtBlock(step)
                                    .frame(width: leftWidth, alignment: .leading)
                                rawCaptureBlock(step)
                                    .padding(.horizontal, 24)
                                    .frame(width: captureWidth, alignment: .leading)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .frame(width: proxy.size.width, alignment: .topLeading)
                            .scrollTransition(.interactive, axis: .vertical) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.78)
                                    .offset(y: phase.isIdentity ? 0 : phase.value * 10)
                            }
                        }
                    }
                    .frame(width: proxy.size.width, alignment: .topLeading)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.automatic)
                .frame(width: proxy.size.width, height: 620, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
            .frame(minHeight: 620, maxHeight: 620)
        }
        .frame(maxWidth: .infinity, minHeight: 620, maxHeight: 620, alignment: .topLeading)
    }

    @ViewBuilder
    private func rawThoughtBlock(_ step: ExplorationStep) -> some View {
        let annotation = appState.stepAnnotations[step.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !annotation.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("MY THOUGHT")
                    .font(NotefyFont.label)
                    .tracking(1.1)
                    .foregroundStyle(NotefyTheme.inkFaint)
                Text(annotation)
                    .font(NotefyFont.body)
                    .foregroundStyle(NotefyTheme.ink)
                    .lineSpacing(7)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .pigmentMark()
            }
            .padding(.top, 8)
        }
    }

    private func rawCaptureBlock(_ step: ExplorationStep) -> some View {
        let isSelected = appState.selectedStepIDs.contains(step.id)
        return HStack(alignment: .top, spacing: 10) {
            if isSelecting {
                Button { appState.toggleStepSelection(step.id) } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(isSelected ? NotefyTheme.marginRose : NotefyTheme.inkFaint)
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
            }
            CaptureStamp(step: step, analysis: appState.vlmResults[step.id])
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NotefyTheme.cardPaper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .grain()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? NotefyTheme.pigment : NotefyTheme.glassBorderSoft, lineWidth: isSelected ? 2 : 1))
                .shadow(color: NotefyTheme.panelShadowColor, radius: 16, x: 0, y: 8)
        }
    }

    private var organizedPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            if appState.isOrganizing {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Setting the page in order…")
                        .font(NotefyFont.body)
                        .foregroundStyle(NotefyTheme.inkSoft)
                }
            } else if appState.organizedDraft.isEmpty {
                Text("Choose Bullet List, Essay, or Diagram from Organize below.")
                    .font(NotefyFont.body)
                    .foregroundStyle(NotefyTheme.inkSoft)
            } else if appState.organizedTemplate == .diagram {
                OrganizedDiagramView(
                    steps: Array(appState.steps.reversed()),
                    annotations: appState.stepAnnotations,
                    noteTitle: appState.noteTitle,
                    graph: appState.organizedGraph
                )
            } else {
                organizedSplitPage
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    /// Organized is the interpretation layer. Raw screenshots stay in Raw;
    /// this view should read as a clean, continuous page of understanding.
    private var organizedSplitPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 34) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("A considered view of what you captured, and why it matters.")
                        .font(NotefyFont.body)
                        .foregroundStyle(NotefyTheme.inkSoft)
                    FlowTags(tags: sourceTags)
                    OrganizedMarkdownView(markdown: appState.organizedDraft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                organizedCaptureWell
                    .frame(width: 500, height: 680)
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
    }

    private var organizedCaptureWell: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(NotefyTheme.sandDeep)
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(NotefyTheme.glassBorder, lineWidth: 1))
                .grain()
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .neomorphicDeboss(cornerRadius: 30)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(appState.steps.reversed())) { step in
                        CaptureStamp(step: step, analysis: appState.vlmResults[step.id])
                            .padding(22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(NotefyTheme.cardPaper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .grain()
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(NotefyTheme.glassBorderSoft, lineWidth: 1))
                            .scrollTransition(.interactive, axis: .vertical) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.72)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
                            }
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.automatic)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
    }

    private var sourceTags: [String] {
        Array(Set(appState.steps.map { step in
            if let host = step.url.flatMap(URL.init(string:))?.host, !host.isEmpty { return host }
            return step.appName
        }).prefix(3))
    }

    /// Simple wrapping tag row — source tags read left to right and wrap to a
    /// new line when the column runs out of width, rather than clipping.
    private struct FlowTags: View {
        let tags: [String]

        var body: some View {
            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(NotefyFont.caption)
                        .foregroundStyle(NotefyTheme.inkSoft)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(NotefyTheme.glassFillTag, in: Capsule())
                        .overlay(Capsule().stroke(NotefyTheme.glassBorder, lineWidth: 1))
                }
            }
        }
    }

    private var emptyPaper: some View {
        VStack(spacing: 18) {
            ZStack {
                InkSplatterMark(seed: 12, tint: NotefyTheme.pigment, opacity: 0.22)
                    .frame(width: 128, height: 108)
                NotedMark(tint: NotefyTheme.ink, knockout: NotefyTheme.sand)
                    .frame(width: 46, height: 46)
            }
            .frame(width: 140, height: 112)

            VStack(spacing: 8) {
                Text("Bring the intangible here")
                    .font(NotefyFont.sectionTitle)
                Text("Tap Kami or use a hotkey while you browse. Only the things you choose become part of this page.")
                    .font(NotefyFont.body)
                    .foregroundStyle(NotefyTheme.inkSoft)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// A floating glass pill holding just the actions — never a full-width scrim.
    /// Content behind it clears via the ScrollView's own bottom padding; nothing
    /// here may fade or mask what's scrolling underneath.
    private var actionShelf: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if !appState.selectedStepIDs.isEmpty {
                selectionToolbar
            } else if appState.isRecording {
                DualAudioSourceMeters(
                    microphoneDB: appState.microphonePowerDB,
                    systemDB: appState.systemAudioPowerDB,
                    microphoneActive: appState.microphoneSourceActive,
                    systemActive: appState.systemAudioSourceActive
                )
            }
            Spacer()
            if appState.selectedStepIDs.isEmpty {
                actionButtons
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var actionButtons: some View {
        // Graphite pills float above the material — exactly one primary
        // (pigment) pill per screen. Organize is the primary action here.
        if mode == .raw {
            VStack(alignment: .trailing, spacing: 7) {
                if showOrganizationChoices {
                    organizationChoices
                }
                HStack(spacing: 8) {
                    GraphitePillButton(isSelecting ? "Done" : "Select", systemImage: isSelecting ? "checkmark" : "checkmark.circle") {
                        isSelecting.toggle()
                    }
                    GraphitePillButton("Organize", systemImage: showOrganizationChoices ? "xmark" : "arrow.up", primary: true) {
                        showOrganizationChoices.toggle()
                    }
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 7) {
                if showOrganizationChoices {
                    organizationChoices
                }
                HStack(spacing: 7) {
                    GraphitePillButton("Template", systemImage: "square.grid.2x2", primary: true) {
                        showOrganizationChoices.toggle()
                    }
                    GraphitePillButton("Raw", systemImage: "arrow.left") {
                        mode = .raw
                    }
                }
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 10) {
            Text("\(appState.selectedStepIDs.count) SELECTED")
                .font(NotefyFont.label).tracking(1)
                .foregroundStyle(NotefyTheme.inkSoft)

            Button {
                showMovePicker = true
            } label: {
                Label("Move", systemImage: "arrow.right.doc.on.clipboard")
                    .font(NotefyFont.label).tracking(0.6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NotefyTheme.ink)
            .popover(isPresented: $showMovePicker, arrowEdge: .bottom) {
                NoteSearchPicker(
                    title: "Move to",
                    excluding: appState.activeNoteURL,
                    onSelect: { appState.relocateSelectedSteps(to: $0, keepInCurrent: false) },
                    onCreateNew: { appState.relocateSelectedSteps(toNewNoteNamed: "", keepInCurrent: false) }
                )
            }

            Button {
                showForwardPicker = true
            } label: {
                Label("Forward", systemImage: "arrowshape.turn.up.right")
                    .font(NotefyFont.label).tracking(0.6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NotefyTheme.ink)
            .popover(isPresented: $showForwardPicker, arrowEdge: .bottom) {
                NoteSearchPicker(
                    title: "Forward to",
                    excluding: appState.activeNoteURL,
                    onSelect: { appState.relocateSelectedSteps(to: $0, keepInCurrent: true) },
                    onCreateNew: { appState.relocateSelectedSteps(toNewNoteNamed: "", keepInCurrent: true) }
                )
            }

            Button(role: .destructive) {
                appState.deleteSelectedSteps()
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(NotefyFont.label).tracking(0.6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NotefyTheme.marginRose)

            Button {
                appState.clearStepSelection()
            } label: {
                Text("CANCEL")
                    .font(NotefyFont.label).tracking(0.8)
                    .foregroundStyle(NotefyTheme.inkFaint)
            }
            .buttonStyle(.plain)
        }
    }

    private func organizationChoice(_ template: OrganizationTemplate, icon: String) -> some View {
        Button {
            showOrganizationChoices = false
            appState.organizeCurrentSession(as: template)
            mode = .organized
        } label: {
            Label(template.rawValue.uppercased(), systemImage: icon)
                .font(NotefyFont.label)
                .tracking(0.8)
                .foregroundStyle(NotefyTheme.inkStrong)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(width: 154, alignment: .leading)
                .background(NotefyTheme.cardPaper, in: Capsule())
                .emboss()
        }
        .buttonStyle(.plain)
    }

    private var organizationChoices: some View {
        VStack(alignment: .trailing, spacing: 7) {
            Text(appState.visionStatus.uppercased())
                .font(NotefyFont.caption)
                .tracking(0.6)
                .foregroundStyle(NotefyTheme.inkSoft)
                .frame(maxWidth: 270, alignment: .trailing)
            organizationChoice(.bulletList, icon: "list.bullet")
            organizationChoice(.essay, icon: "text.alignleft")
            organizationChoice(.diagram, icon: "point.3.connected.trianglepath.dotted")
        }
    }

    private var metaText: String {
        "\(appState.steps.count) ITEMS · TODAY"
    }

}

private struct OrganizedMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                markdownLine(line)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func markdownLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Spacer().frame(height: 11)
        } else if trimmed.hasPrefix("```") {
            EmptyView()
        } else if trimmed.hasPrefix("### ") {
            inlineMarkdown(String(trimmed.dropFirst(4)))
                .font(NotefyFont.heading)
                .foregroundStyle(NotefyTheme.ink)
                .padding(.top, 9)
                .padding(.bottom, 4)
        } else if trimmed.hasPrefix("## ") {
            inlineMarkdown(String(trimmed.dropFirst(3)))
                .font(NotefyFont.label)
                .tracking(1.1)
                .foregroundStyle(NotefyTheme.inkSoft)
                .padding(.top, 14)
                .padding(.bottom, 7)
        } else if trimmed.hasPrefix("# ") {
            inlineMarkdown(String(trimmed.dropFirst(2)))
                .font(NotefyFont.sectionTitle)
                .foregroundStyle(NotefyTheme.ink)
                .padding(.bottom, 10)
        } else if trimmed.hasPrefix("- [ ] ") {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "square")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NotefyTheme.inkSoft)
                    .padding(.top, 4)
                inlineMarkdown(String(trimmed.dropFirst(6)))
                    .font(NotefyFont.body)
                    .foregroundStyle(NotefyTheme.ink)
            }
            .padding(.vertical, 3)
        } else if trimmed.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(NotefyTheme.marginRose)
                    .frame(width: 5, height: 5)
                    .padding(.top, 9)
                inlineMarkdown(String(trimmed.dropFirst(2)))
                    .font(NotefyFont.body)
                    .foregroundStyle(NotefyTheme.ink)
                    .lineSpacing(4)
            }
            .padding(.vertical, 3)
        } else {
            inlineMarkdown(trimmed)
                .font(NotefyFont.body)
                .foregroundStyle(NotefyTheme.ink)
                .lineSpacing(5)
                .padding(.vertical, 2)
        }
    }

    private func inlineMarkdown(_ value: String) -> Text {
        if let attributed = try? AttributedString(markdown: value) {
            return Text(attributed)
        }
        return Text(value)
    }
}

private struct OrganizedDiagramView: View {
    let steps: [ExplorationStep]
    let annotations: [UUID: String]
    let noteTitle: String
    let graph: ThoughtGraph?

    var body: some View {
        if let graph {
            semanticGraphBody(graph)
        } else {
            legacyGraphBody
        }
    }

    private func semanticGraphBody(_ graph: ThoughtGraph) -> some View {
        VStack(spacing: 0) {
            diagramNode(
                eyebrow: "CENTRAL QUESTION",
                text: graph.centralQuestion,
                tint: NotefyTheme.pebbleTan.opacity(0.58),
                emphasis: true
            )
            .frame(maxWidth: 470)

            GraphStem(height: 28)

            let tiers = semanticTiers(graph)
            ForEach(Array(tiers.enumerated()), id: \.offset) { index, tier in
                VStack(spacing: 0) {
                    if tier.count > 1 {
                        GraphBranchArms(count: tier.count).frame(height: 19)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(tier) { node in
                            semanticNode(node)
                                .frame(width: tier.count == 1 ? 460 : 220, alignment: .top)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                if index < tiers.count - 1 {
                    GraphStem(height: 26)
                }
            }
        }
        .frame(maxWidth: 860, alignment: .center)
    }

    private var legacyGraphBody: some View {
        VStack(spacing: 0) {
            diagramNode(eyebrow: "CENTRAL QUESTION", text: centralQuestion, tint: NotefyTheme.pebbleTan.opacity(0.58), emphasis: true)
                .frame(maxWidth: 470)
            GraphStem(height: 28)
            ForEach(Array(tiers.enumerated()), id: \.offset) { index, tier in
                graphTier(tier, index: index)
                if index < tiers.count - 1 { GraphStem(height: 26) }
            }
        }
        .frame(maxWidth: 860, alignment: .center)
    }

    private func graphTier(_ tier: [ExplorationStep], index: Int) -> some View {
        VStack(spacing: 0) {
            if tier.count > 1 {
                GraphBranchArms(count: tier.count)
                    .frame(height: 19)
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(tier.enumerated()), id: \.element.id) { offset, step in
                    integratedNode(step: step, index: index + offset + 1)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
    }

    private func integratedNode(step: ExplorationStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("THREAD \(index) · \(sourceName(for: step))".uppercased())
                .font(NotefyFont.caption).tracking(0.9)
                .foregroundStyle(NotefyTheme.inkSoft)
            Text(excerpt(for: step))
                .font(NotefyFont.body)
                .foregroundStyle(NotefyTheme.ink)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(NotefyTheme.ink.opacity(0.14))
                .frame(height: 1)
            Text("THEN…")
                .font(NotefyFont.caption).tracking(0.8)
                .foregroundStyle(NotefyTheme.inkSoft)
            Text(thought(for: step))
                .font(NotefyFont.body)
                .foregroundStyle(NotefyTheme.ink)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotefyTheme.cardPaper)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NotefyTheme.ink.opacity(0.14), lineWidth: 1))
        .neomorphicDeboss(cornerRadius: 12)
    }

    private func semanticNode(_ node: ThoughtNode) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(node.type.rawValue.uppercased()) · \(node.sourceIds.count) SOURCE\(node.sourceIds.count == 1 ? "" : "S")")
                .font(NotefyFont.caption).tracking(0.9)
                .foregroundStyle(NotefyTheme.inkSoft)
            Text(node.title)
                .font(NotefyFont.body.weight(.medium))
                .foregroundStyle(NotefyTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = node.summary, !summary.isEmpty {
                Text(summary)
                    .font(NotefyFont.caption)
                    .foregroundStyle(NotefyTheme.inkSoft)
                    .lineLimit(4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotefyTheme.cardPaper)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NotefyTheme.ink.opacity(0.14), lineWidth: 1))
        .neomorphicDeboss(cornerRadius: 12)
    }

    private func semanticTiers(_ graph: ThoughtGraph) -> [[ThoughtNode]] {
        let lookup = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        var current = [graph.rootNodeId]
        var seen = Set(current)
        var result: [[ThoughtNode]] = []
        while !current.isEmpty {
            let childIDs = current.flatMap { lookup[$0]?.children.map(\.nodeId) ?? [] }
            let nextIDs = childIDs.filter { seen.insert($0).inserted }
            let next = nextIDs.compactMap { lookup[$0] }
            if next.isEmpty { break }
            result.append(next)
            current = next.map(\.id)
        }
        return result
    }

    private func diagramNode(eyebrow: String, text: String, tint: Color, emphasis: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased())
                .font(NotefyFont.caption).tracking(0.9)
                .foregroundStyle(NotefyTheme.inkSoft)
            Text(text)
                .font(emphasis ? NotefyFont.heading : NotefyFont.body)
                .foregroundStyle(NotefyTheme.ink)
                .lineLimit(emphasis ? 3 : 6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(emphasis ? 18 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NotefyTheme.ink.opacity(0.14), lineWidth: 1))
        .neomorphicDeboss(cornerRadius: 12)
    }

    private func excerpt(for step: ExplorationStep) -> String {
        let value = step.selectedText ?? step.pageText ?? step.windowTitle
        return String(value.replacingOccurrences(of: "\n", with: " ").prefix(240))
    }

    private func thought(for step: ExplorationStep) -> String {
        let value = annotations[step.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false ? value! : "No annotation yet — add what this capture makes you wonder, decide, or connect.")
    }

    private var centralQuestion: String {
        let title = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.caseInsensitiveCompare("Untitled capture") == .orderedSame {
            return "What is the thread connecting these captures?"
        }
        if title.hasSuffix("?") { return title }
        return "What is the thread through \u{201C}\(title)\u{201D}?"
    }

    private var tiers: [[ExplorationStep]] {
        guard !steps.isEmpty else { return [] }
        // The visual rhythm intentionally alternates: branches, a single continuation,
        // then branches again. Each card still contains both the source and the thought,
        // so the graph reads as one evolving argument rather than two parallel columns.
        let pattern = [2, 3, 1, 2, 1, 3]
        var result: [[ExplorationStep]] = []
        var cursor = 0
        var patternIndex = 0
        while cursor < steps.count {
            let remaining = steps.count - cursor
            let count = min(pattern[patternIndex % pattern.count], remaining)
            result.append(Array(steps[cursor..<(cursor + count)]))
            cursor += count
            patternIndex += 1
        }
        return result
    }

    private func sourceName(for step: ExplorationStep) -> String {
        step.url.flatMap(URL.init(string:))?.host ?? step.appName
    }
}

private struct GraphBranchArms: View {
    let count: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(NotefyTheme.inkSoft.opacity(0.45))
                        .frame(width: 1, height: 9)
                    Circle()
                        .fill(NotefyTheme.inkSoft.opacity(0.7))
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity)
                if index < count - 1 {
                    Rectangle()
                        .fill(NotefyTheme.inkSoft.opacity(0.35))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct GraphStem: View {
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(NotefyTheme.inkSoft.opacity(0.45))
            .frame(width: 1, height: height)
    }
}

private struct GraphArrow: View {
    var body: some View {
        Canvas { context, size in
            var line = Path()
            line.move(to: CGPoint(x: 2, y: size.height / 2))
            line.addCurve(
                to: CGPoint(x: size.width - 10, y: size.height / 2),
                control1: CGPoint(x: size.width * 0.35, y: size.height * 0.12),
                control2: CGPoint(x: size.width * 0.62, y: size.height * 0.88)
            )
            context.stroke(line, with: .color(NotefyTheme.inkSoft), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            var tip = Path()
            tip.move(to: CGPoint(x: size.width - 18, y: size.height * 0.31))
            tip.addLine(to: CGPoint(x: size.width - 7, y: size.height / 2))
            tip.addLine(to: CGPoint(x: size.width - 18, y: size.height * 0.69))
            context.stroke(tip, with: .color(NotefyTheme.inkSoft), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct CaptureStamp: View {
    let step: ExplorationStep
    let analysis: String?

    /// Typography only — no container, no fill, no radius. This lives *inside*
    /// an already-debossed `.nt-note` row; a second box here is the "mush"
    /// the corrections pass calls out.
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(sourceName.uppercased())
                    .font(NotefyFont.label).tracking(1.1)
                    .foregroundStyle(NotefyTheme.inkFaint)
                Spacer()
                Text(step.timestamp, style: .time)
                    .font(NotefyFont.caption)
                    .foregroundStyle(NotefyTheme.inkFaint)
            }

            if let path = step.screenshotPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let selected = displayText {
                Text(selected)
                    .font(NotefyFont.capturedBody)
                    .foregroundStyle(NotefyTheme.ink)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            if let analysis {
                Text(analysis)
                    .font(NotefyFont.caption)
                    .foregroundStyle(NotefyTheme.inkSoft)
                    .lineLimit(4)
            }
            Text(sourceDescription)
                .font(NotefyFont.caption)
                .foregroundStyle(NotefyTheme.inkFaint)
        }
    }

    private var sourceName: String {
        if let host = step.url.flatMap(URL.init(string:))?.host, !host.isEmpty { return host }
        if step.appName == "Audio" { return "Computer audio" }
        if ["Notefy", "Noted", "notefy-app"].contains(step.appName) { return "Screen region" }
        return step.appName
    }

    private var sourceDescription: String {
        if step.appName == "Audio" { return "Computer audio recording" }
        if ["Notefy", "Noted", "notefy-app"].contains(step.windowTitle) {
            return step.url ?? "Selected screen region"
        }
        return step.url ?? step.windowTitle
    }

    private var displayText: String? {
        guard let text = step.selectedText else { return nil }
        guard step.appName == "Audio", let marker = text.range(of: "Others (computer audio):") else {
            return text
        }
        let computerAudio = text[marker.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return computerAudio == "[BLANK_AUDIO]" ? "No computer audio was detected." : computerAudio
    }
}

/// Minimal left-to-right wrapping layout for tag pills.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
