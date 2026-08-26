import AppKit
import SwiftUI
import NotefyCore

/// The width of the strip the note header, thought blocks, and capture
/// cards occupy. The splatter's content-safe column is derived from it, so
/// the two can never drift apart.
private let rawContentColumn: CGFloat = 780

private enum NoteViewMode: String, CaseIterable, Identifiable {
    case raw = "Raw"
    case organized = "Organized"
    var id: String { rawValue }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.ground) private var ground
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
        .padding(.horizontal, 28)
        // The extra clearance above the tab strip is cancelled out by the
        // matching reduction in pageViewport's own top padding below, so the
        // note column's absolute position doesn't move when this changes —
        // only the tab strip's distance from the window top does.
        .padding(.top, 2)
        .background(Color.clear)
    }

    @ViewBuilder
    private var pageViewport: some View {
        if mode == .raw {
            // Raw owns its scroll view so trackpad/wheel input reaches the
            // paired capture stream directly instead of being intercepted by
            // the dashboard's outer page scroller.
            rawPage
                .padding(.horizontal, 14)
                .padding(.bottom, 110)
        } else {
            ScrollView {
                pageContent
                    .padding(.horizontal, 14)
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
        // Cut INTO the ground rather than floating on it. Same geometry in
        // both modes; only the fill and the lip change.
        .background(ground.isInk ? ground.groundLift : Stoneink.surfacePress)
        .clipShape(Capsule())
        .modifier(TrackWell())
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 22)
        .zIndex(3)
    }

    /// The active tab is a slab resting inside the press well — an
    /// impression, never a raised element competing with real buttons.
    private func tabButton(title: String, mode candidate: NoteViewMode) -> some View {
        let isActive = candidate == mode
        return Button {
            mode = candidate
        } label: {
            Text(title)
                // The active segment is the only paper in the control, so
                // its label is ink on paper in both modes. Inactive labels
                // sit directly on the ground and follow it.
                .font(StoneFont.bodyMedium())
                .foregroundStyle(isActive ? Stoneink.textPrimary : ground.onGround42)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isActive {
                        Capsule().fill(Stoneink.surfaceSlab).modifier(SegmentSlab())
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
                TextField("Name this note", text: $appState.noteTitle, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(StoneFont.title())
                    .foregroundStyle(ground.onGround)
                    .lineLimit(1...2)
                    .onSubmit { appState.saveActiveNote() }

                Text(metaText)
                    .font(StoneFont.mark())
                    .tracking(Stoneink.trMark * 11)
                    .foregroundStyle(ground.onGround42)
                    .padding(.top, 9)
                    .padding(.bottom, 30)

                organizedPage
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Title + meta on the left, source tags on the right — dropped the
    /// "ACTIVE NOTE · SAVES AUTOMATICALLY" mark entirely and moved the tags
    /// beside the title instead of stacking beneath it, so the header
    /// takes one compact row instead of three and leaves more of the
    /// limited vertical space for the capture itself.
    private var rawNoteHeader: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Name this note", text: $appState.noteTitle, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(StoneFont.title())
                    .foregroundStyle(ground.onGround)
                    .lineSpacing(2)
                    .onSubmit { appState.saveActiveNote() }
                    .fixedSize(horizontal: false, vertical: true)

                Text(metaText)
                    .font(StoneFont.mark())
                    .tracking(Stoneink.trMark * 11)
                    .foregroundStyle(ground.onGround42)
                    .padding(.top, 9)
            }

            if !sourceTags.isEmpty {
                Spacer(minLength: 12)
                FlowTags(tags: sourceTags)
                    .frame(maxWidth: 340, alignment: .trailing)
                    .padding(.top, 6)
            }
        }
    }

    // No enclosing well: captures rest flat on the bed as their own small
    // clay cards, not held inside one big panel. No left/right split
    // either — the title sits at the top and everything else, one thought
    // + capture pair at a time, stacks straight down beneath it. The
    // paging scroll still snaps to exactly one pair at a time, so it
    // reads as one blob of note you focus through rather than a wall of
    // cards you skim.
    private var rawPage: some View {
        let steps = Array(appState.steps.reversed())
        return VStack(alignment: .leading, spacing: 22) {
            rawNoteHeader

            if steps.isEmpty {
                emptyPaper
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                GeometryReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(steps) { step in
                                // The capture scrolls internally if it's
                                // taller than the page itself — nothing
                                // gets clipped, it's just reachable by
                                // scrolling that one card in place.
                                ScrollView(.vertical) {
                                    // Narrower than the full page: at full
                                    // width the aspect-fit image scales up
                                    // wide-and-short, so less of it is
                                    // visible without scrolling. Narrower,
                                    // it scales down instead and more of
                                    // the capture fits on screen at once.
                                    // An actual `width` (not `maxWidth`) —
                                    // a ScrollView doesn't propose a width
                                    // to its content, so `maxWidth` alone
                                    // was capping the reported size without
                                    // ever reproposing a narrower width
                                    // down to the text, which just clipped
                                    // instead of wrapping.
                                    VStack(alignment: .leading, spacing: 24) {
                                        rawThoughtBlock(step)
                                        rawCaptureBlock(step)
                                    }
                                    .frame(width: rawContentColumn, alignment: .leading)
                                }
                                .scrollIndicators(.hidden)
                                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                                .revealTransition()
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollIndicators(.hidden)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The splatter lives below every panel and text node, on the
        // canvas only — never in the sidebar. Placed at fixed anchors,
        // never randomized, so the mark set is identical on every load.
        // `rawContentColumn` is the strip the header, thoughts, and capture
        // cards occupy; no mark may intersect it or its 48px margin, so on
        // a narrow window the marks simply don't render.
        .background(GroundSplatterField(contentColumnWidth: rawContentColumn))
    }

    @ViewBuilder
    private func rawThoughtBlock(_ step: ExplorationStep) -> some View {
        let annotation = appState.stepAnnotations[step.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !annotation.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("MY THOUGHT")
                    .font(StoneFont.mark())
                    .tracking(Stoneink.trMark * 11)
                    .foregroundStyle(ground.onGround42)
                // The user's own words — this is the one place Newsreader
                // (the ink) appears in UI chrome, per the type rule. Set on
                // the cobalt highlighter wash: ink lands on clay.
                Text(annotation)
                    .font(StoneFont.readSmall())
                    // Full strength. The wash is what carries the mark; the
                    // text must never strain against it.
                    .foregroundStyle(ground.onGround)
                    .lineSpacing((Stoneink.tRead - 2) * (Stoneink.lhRead - 1))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    // A highlighter mark, not a surface: no glow, no drop
                    // shadow, no outer stroke. Tight even radius only.
                    .background(ground.wash, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .padding(.top, 8)
        }
    }

    /// A note card: fresh slip on the bed. The most repeated object in the
    /// product. Selected: a cobalt rule + cobalt stroke, never a colour
    /// the palette doesn't have.
    private func rawCaptureBlock(_ step: ExplorationStep) -> some View {
        let isSelected = appState.selectedStepIDs.contains(step.id)
        return HStack(alignment: .top, spacing: 10) {
            if isSelecting {
                Button { appState.toggleStepSelection(step.id) } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(isSelected ? Stoneink.cobalt600 : Stoneink.clay500)
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
            }
            CaptureStamp(step: step, analysis: appState.vlmResults[step.id])
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Stoneink.surfaceSlip)
                .overlay(GrogOverlay().allowsHitTesting(false))
                .clipShape(ThrownRect.md)
                .depthSlab(ThrownRect.md)
                .overlay {
                    if isSelected {
                        ThrownRect.md.stroke(Stoneink.cobalt600, lineWidth: 2)
                    }
                }
        }
    }

    private var organizedPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            if appState.isOrganizing {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Setting the page in order…")
                        .font(StoneFont.body())
                        .foregroundStyle(ground.onGround72)
                }
            } else if appState.organizedDraft.isEmpty {
                Text("Choose Bullet List, Essay, or Diagram from Organize below.")
                    .font(StoneFont.body())
                    .foregroundStyle(ground.onGround72)
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
    // Organized is the AI's own read of the note — text only. Raw screenshots
    // stay in Raw; showing the capture stream again here was a redundant
    // second copy of the same evidence, not a second view of it.
    /// §3.5, option A. Organized is a long-form reading surface, and light
    /// text on a dark ground is the hardest readability case in the app —
    /// so the essay sits on a paper sheet, ink on paper, exactly like the
    /// sidebar. The ground shows only as a margin around it, and readability
    /// is then solved for free in both modes. No splatter here: this is a
    /// reading surface.
    private var organizedSplitPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A considered view of what you captured, and why it matters.")
                .font(StoneFont.body())
                .foregroundStyle(Stoneink.textSecondary)
            FlowTags(tags: sourceTags, onPaper: true)
            OrganizedMarkdownView(markdown: appState.organizedDraft)
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Stoneink.surfaceLeaf)
        .overlay(GrogOverlay().allowsHitTesting(false))
        .clipShape(ThrownRect.lg)
        .depthSlab(ThrownRect.lg)
    }

    private var sourceTags: [String] {
        Array(Set(appState.steps.map { step in
            if let host = step.url.flatMap(URL.init(string:))?.host, !host.isEmpty { return host }
            return step.appName
        }).prefix(3))
    }

    /// Simple wrapping tag-coil row — source tags read left to right and
    /// wrap to a new line when the column runs out of width.
    private struct FlowTags: View {
        let tags: [String]
        /// Source pills on the organized sheet land on paper; the note
        /// header's tags land on the ground. Same ghost treatment either
        /// way — only the pigment is mixed for the substrate.
        var onPaper: Bool = false

        var body: some View {
            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    TagCoil(text: tag, onPaper: onPaper)
                }
            }
        }
    }

    /// The one place the full splatter mark appears at scale, per the
    /// system's own rule: one splatter, maximum, per screen.
    private var emptyPaper: some View {
        VStack(spacing: 18) {
            // The wash strength is for a highlighter behind text; at 96pt
            // it reads as a blue blob dropped in the middle of the canvas.
            // The bloom mix is the ambient one, which is what this is.
            StoneinkMark(tint: ground.bloom)
                .frame(width: 96, height: 96)

            VStack(spacing: 8) {
                Text("Nothing kept yet")
                    .font(StoneFont.title())
                    .foregroundStyle(ground.onGround)
                Text("Capture anything on screen and it lands here.")
                    .font(StoneFont.body())
                    .foregroundStyle(ground.onGround72)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)

                Text("⌘⇧N")
                    .font(StoneFont.markMedium())
                    .tracking(Stoneink.trMark * 11)
                    .foregroundStyle(ground.onGround72)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(ground.isInk ? ground.groundLift : Stoneink.surfacePress)
                    .clipShape(ThrownRect.press)
                    .modifier(TrackWell(shape: ThrownRect.press))
                    .padding(.top, 6)
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
        // One primary `ink` (cobalt) button per screen; everything else is
        // `stamp`. Never floating, never glowing — the fired edge carries it.
        if mode == .raw {
            VStack(alignment: .trailing, spacing: 7) {
                if showOrganizationChoices {
                    organizationChoices
                }
                HStack(spacing: 8) {
                    StoneButton(title: isSelecting ? "Done" : "Select", systemImage: isSelecting ? "checkmark" : "checkmark.circle", variant: .ghost) {
                        isSelecting.toggle()
                    }
                    StoneButton(title: "Organize", systemImage: showOrganizationChoices ? "xmark" : "arrow.up", variant: .ink) {
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
                    StoneButton(title: "Template", systemImage: "square.grid.2x2", variant: .ink) {
                        showOrganizationChoices.toggle()
                    }
                    // Ghost, not a filled slab — one solid cobalt per screen.
                    StoneButton(title: "Raw", systemImage: "arrow.left", variant: .ghost) {
                        mode = .raw
                    }
                }
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 10) {
            Text("\(appState.selectedStepIDs.count) selected")
                .font(StoneFont.mark()).tracking(Stoneink.trMark * 11)
                .foregroundStyle(ground.onGround72)

            Button {
                showMovePicker = true
            } label: {
                Label("Move", systemImage: "arrow.right.doc.on.clipboard")
                    .font(StoneFont.bodyMedium())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ground.onGround)
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
                    .font(StoneFont.bodyMedium())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ground.onGround)
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
                    .font(StoneFont.bodyMedium())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ground.destructive)

            Button {
                appState.clearStepSelection()
            } label: {
                Text("Cancel")
                    .font(StoneFont.bodyMedium())
                    .foregroundStyle(ground.onGround42)
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
            Label(template.rawValue, systemImage: icon)
                .font(StoneFont.bodyMedium())
                .foregroundStyle(Stoneink.textPrimary)
                .padding(.horizontal, 14)
                .frame(width: 154, height: 38, alignment: .leading)
                .background(Stoneink.surfaceSlab)
                .clipShape(ThrownRect.sm)
                .depthSlab(ThrownRect.sm)
        }
        .buttonStyle(.plain)
    }

    private var organizationChoices: some View {
        VStack(alignment: .trailing, spacing: 7) {
            Text(appState.visionStatus)
                .font(StoneFont.mark())
                .tracking(Stoneink.trMark * 11)
                .foregroundStyle(Stoneink.textSecondary)
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
                .font(StoneFont.heading())
                .foregroundStyle(Stoneink.textPrimary)
                .padding(.top, 9)
                .padding(.bottom, 4)
        } else if trimmed.hasPrefix("## ") {
            inlineMarkdown(String(trimmed.dropFirst(3)))
                .font(StoneFont.mark())
                .tracking(1.1)
                .foregroundStyle(Stoneink.textSecondary)
                .padding(.top, 14)
                .padding(.bottom, 7)
        } else if trimmed.hasPrefix("# ") {
            inlineMarkdown(String(trimmed.dropFirst(2)))
                .font(StoneFont.title())
                .foregroundStyle(Stoneink.textPrimary)
                .padding(.bottom, 10)
        } else if trimmed.hasPrefix("- [ ] ") {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "square")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Stoneink.textSecondary)
                    .padding(.top, 4)
                inlineMarkdown(String(trimmed.dropFirst(6)))
                    .font(StoneFont.body())
                    .foregroundStyle(Stoneink.textPrimary)
            }
            .padding(.vertical, 3)
        } else if trimmed.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 10) {
                // Cobalt, not a neutral and not a second pigment. The sheet
                // is paper in both modes, so this is the paper mix.
                Circle()
                    .fill(Stoneink.cobalt600)
                    .frame(width: 5, height: 5)
                    .padding(.top, 9)
                inlineMarkdown(String(trimmed.dropFirst(2)))
                    .font(StoneFont.body())
                    .foregroundStyle(Stoneink.textPrimary)
                    .lineSpacing(4)
            }
            .padding(.vertical, 3)
        } else {
            inlineMarkdown(trimmed)
                .font(StoneFont.body())
                .foregroundStyle(Stoneink.textPrimary)
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
                tint: Stoneink.cobalt050.opacity(0.58),
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
            diagramNode(eyebrow: "CENTRAL QUESTION", text: centralQuestion, tint: Stoneink.cobalt050.opacity(0.58), emphasis: true)
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
                .font(StoneFont.mark()).tracking(0.9)
                .foregroundStyle(Stoneink.textSecondary)
            Text(excerpt(for: step))
                .font(StoneFont.body())
                .foregroundStyle(Stoneink.textPrimary)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(Stoneink.textPrimary.opacity(0.14))
                .frame(height: 1)
            Text("THEN…")
                .font(StoneFont.mark()).tracking(0.8)
                .foregroundStyle(Stoneink.textSecondary)
            Text(thought(for: step))
                .font(StoneFont.body())
                .foregroundStyle(Stoneink.textPrimary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Stoneink.surfaceSlab)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Stoneink.textPrimary.opacity(0.14), lineWidth: 1))
        .depthSlab(RoundedRectangle(cornerRadius: 12))
    }

    private func semanticNode(_ node: ThoughtNode) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(node.type.rawValue.uppercased()) · \(node.sourceIds.count) SOURCE\(node.sourceIds.count == 1 ? "" : "S")")
                .font(StoneFont.mark()).tracking(0.9)
                .foregroundStyle(Stoneink.textSecondary)
            Text(node.title)
                .font(StoneFont.bodyMedium())
                .foregroundStyle(Stoneink.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = node.summary, !summary.isEmpty {
                Text(summary)
                    .font(StoneFont.mark())
                    .foregroundStyle(Stoneink.textSecondary)
                    .lineLimit(4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Stoneink.surfaceSlab)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Stoneink.textPrimary.opacity(0.14), lineWidth: 1))
        .depthSlab(RoundedRectangle(cornerRadius: 12))
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
                .font(StoneFont.mark()).tracking(0.9)
                .foregroundStyle(Stoneink.textSecondary)
            Text(text)
                .font(emphasis ? StoneFont.heading() : StoneFont.body())
                .foregroundStyle(Stoneink.textPrimary)
                .lineLimit(emphasis ? 3 : 6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(emphasis ? 18 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Stoneink.textPrimary.opacity(0.14), lineWidth: 1))
        .depthSlab(RoundedRectangle(cornerRadius: 12))
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
                        .fill(Stoneink.textSecondary.opacity(0.45))
                        .frame(width: 1, height: 9)
                    Circle()
                        .fill(Stoneink.textSecondary.opacity(0.7))
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity)
                if index < count - 1 {
                    Rectangle()
                        .fill(Stoneink.textSecondary.opacity(0.35))
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
            .fill(Stoneink.textSecondary.opacity(0.45))
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
            context.stroke(line, with: .color(Stoneink.textSecondary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            var tip = Path()
            tip.move(to: CGPoint(x: size.width - 18, y: size.height * 0.31))
            tip.addLine(to: CGPoint(x: size.width - 7, y: size.height / 2))
            tip.addLine(to: CGPoint(x: size.width - 18, y: size.height * 0.69))
            context.stroke(tip, with: .color(Stoneink.textSecondary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
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
                    .font(StoneFont.mark()).tracking(1.1)
                    .foregroundStyle(Stoneink.textMuted)
                Spacer()
                Text(step.timestamp, style: .time)
                    .font(StoneFont.mark())
                    .foregroundStyle(Stoneink.textMuted)
            }

            if let path = step.screenshotPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Show the description line once — as body copy if there's real
            // selected text, or as the small mono caption if there isn't.
            // Showing both when they're the same placeholder ("Selected
            // screen region" twice) is the redundant second wrapper.
            if let selected = displayText, selected != sourceDescription {
                Text(selected)
                    .font(StoneFont.body())
                    .foregroundStyle(Stoneink.textPrimary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            if let analysis {
                Text(analysis)
                    .font(StoneFont.mark())
                    .foregroundStyle(Stoneink.textSecondary)
                    .lineLimit(4)
            }
            if displayText != sourceDescription {
                // Wrap to a second line rather than clipping. A truncated
                // URL is the one caption that has to stay readable.
                Text(sourceDescription)
                    .font(StoneFont.mark())
                    .foregroundStyle(Stoneink.textMuted)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
