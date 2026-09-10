import Foundation
import AppKit
import Combine
import NotefyCore

private enum RecordingPurpose: Equatable {
    case sessionVoiceNote
    case standaloneMeetingNote
}

enum OrganizationTemplate: String, Codable, CaseIterable, Identifiable {
    case bulletList = "Bullet list"
    case essay = "Essay"
    case meetingNotes = "Meeting notes"
    case diagram = "Flowchart"

    var id: String { rawValue }

    /// What the UI offers. The flowchart path isn't reliable yet, so it stays
    /// out of the picker while the rest ships.
    static var offered: [OrganizationTemplate] { allCases.filter { $0 != .diagram } }

    var icon: String {
        switch self {
        case .bulletList: return "list.bullet"
        case .essay: return "text.alignleft"
        case .meetingNotes: return "person.2"
        case .diagram: return "point.3.connected.trianglepath.dotted"
        }
    }

    /// The exact Markdown skeleton the model must fill in — kept separate from prose
    /// instructions so the model has an unambiguous structure to match, not a description
    /// to interpret loosely.
    func structure(authorName: String) -> String {
        switch self {
        case .bulletList:
            return """
            # {Title}

            ## Key Ideas
            - One bullet per idea or finding. Embed a descriptive Markdown link to the full source URL in the sentence the first time it is referenced, e.g. [Stripe](https://stripe.com).

            ## \(authorName)'s Reflections
            - \(authorName)'s own typed or spoken thoughts, paraphrased in third person, e.g. "\(authorName) noted that...". Omit this whole section if none were captured.
            """
        case .essay:
            return """
            # {Title}

            ## Overview
            One short paragraph framing what this session was about.

            ## [2-4 more ## subheadings, named after the actual topics covered — do not leave the literal placeholder text]
            Connected paragraphs, embedding a descriptive Markdown link to the full source URL the first time each source is mentioned.

            ## Takeaway
            One closing paragraph tying the session together. If \(authorName) left thoughts, fold in \(authorName)'s own reasoning here in third person, e.g. "\(authorName) concluded that...".
            """
        case .meetingNotes:
            return """
            # {Title}

            ## Context
            One or two sentences on what this meeting or work session covered and, if evident, who or what was involved.

            ## Key Discussion Points
            - One bullet per topic actually discussed or shown, embedding a descriptive Markdown link to the full source URL where applicable.

            ## Decisions
            - One bullet per concrete decision made. Write "No decisions recorded." if none are evident.

            ## Action Items
            - [ ] Task — Owner: name if stated in the material, otherwise "Unassigned"

            ## \(authorName)'s Notes
            \(authorName)'s own thoughts, paraphrased in third person. Omit this whole section if none were captured.
            """
        case .diagram:
            return """
            A single Mermaid flowchart and nothing else — no heading, no prose before or after.

            ```mermaid
            flowchart TD
                S0["first capture or idea"] --> S1["next one"]
            ```

            Every node should represent a real capture, thought, or source, in the order they logically connect. Label edges when the relationship needs explaining (e.g. `-->|clarifies|`). Keep node labels short; put detail in a following node instead of a long label.
            """
        }
    }
}

struct NoteDestination: Identifiable, Hashable {
    let url: URL
    let title: String
    var id: URL { url }
}

/// Read-only presentation data for the chronological canvas. The canvas never owns
/// note content: it projects the existing markdown + JSON sidecar store so capture,
/// organization, and model behavior continue to have one source of truth.
struct CanvasNoteSnapshot: Identifiable, Hashable {
    let url: URL
    let title: String
    let excerpt: String
    let createdAt: Date
    let folderID: UUID?
    let folderName: String
    let captureCount: Int
    let hasOrganizedNote: Bool

    var id: URL { url }
}

enum ThoughtNodeType: String, Codable {
    case question, observation, insight, concern, hypothesis, evidence, solution, conclusion
}

enum ThoughtRelationship: String, Codable {
    case expands, explains, supports, questions, contradicts, exampleOf = "example_of"
    case leadsTo = "leads_to", consequence, possibleSolution = "possible_solution", evidenceFor = "evidence_for"
}

struct ThoughtEdge: Codable, Hashable {
    var nodeId: String
    var relationship: ThoughtRelationship
}

struct ThoughtNode: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var summary: String?
    var type: ThoughtNodeType
    /// Stable provenance links back to ExplorationStep.id values. A semantic thought may
    /// reference multiple captures when repeated ideas are merged.
    var sourceIds: [String]
    var children: [ThoughtEdge]
}

struct ThoughtGraph: Codable, Hashable {
    var centralQuestion: String
    var rootNodeId: String
    var nodes: [ThoughtNode]

    static func build(steps: [ExplorationStep], annotations: [UUID: String], noteTitle: String) -> ThoughtGraph {
        let rootID = "root"
        let question = centralQuestion(noteTitle)
        var semanticNodes: [ThoughtNode] = [ThoughtNode(id: rootID, title: question, summary: nil, type: .question, sourceIds: [], children: [])]
        var byKey: [String: Int] = [:]
        for step in steps {
            let annotation = annotations[step.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let selected = (step.selectedText ?? step.pageText ?? step.windowTitle)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let seed = annotation.isEmpty ? selected : annotation
            let key = seed.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).prefix(12).joined(separator: " ")
            let title = String(seed.prefix(120)).components(separatedBy: .newlines).first ?? seed
            let summary = annotation.isEmpty ? nil : String(selected.prefix(220))
            if let existing = byKey[key], !key.isEmpty {
                semanticNodes[existing].sourceIds.append(step.id.uuidString)
            } else {
                let type: ThoughtNodeType = annotation.contains("?") ? .question : (annotation.isEmpty ? .observation : .insight)
                let node = ThoughtNode(
                    id: "thought-\(UUID().uuidString)",
                    title: title.isEmpty ? "Untitled thought" : title,
                    summary: summary,
                    type: type,
                    sourceIds: [step.id.uuidString],
                    children: []
                )
                byKey[key] = semanticNodes.count
                semanticNodes.append(node)
            }
        }

        // Stable, organic tiers: branches can converge to one continuation and branch again.
        let pattern = [2, 3, 1, 2, 1, 3]
        var tiers: [[String]] = []
        var cursor = 0
        var patternIndex = 0
        while cursor < semanticNodes.count - 1 {
            // The root is not part of the semantic-node count used for tiering.
            let thoughtCount = semanticNodes.count - 1
            let count = min(pattern[patternIndex % pattern.count], thoughtCount - cursor)
            tiers.append(Array(semanticNodes[(cursor + 1)..<(cursor + count + 1)].map(\.id)))
            cursor += count
            patternIndex += 1
        }
        var previous = [rootID]
        for tier in tiers {
            let relationship: ThoughtRelationship = tier.count > previous.count ? .expands : (tier.count < previous.count ? .leadsTo : .explains)
            for (offset, childID) in tier.enumerated() {
                let parentID = previous[offset % max(previous.count, 1)]
                guard let parent = semanticNodes.firstIndex(where: { $0.id == parentID }) else { continue }
                semanticNodes[parent].children.append(ThoughtEdge(nodeId: childID, relationship: relationship))
            }
            previous = tier
        }
        return ThoughtGraph(centralQuestion: question, rootNodeId: rootID, nodes: semanticNodes)
    }

    private static func centralQuestion(_ title: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.hasSuffix("?") { return title }
        return title.isEmpty ? "What is the thread connecting these captures?" : "What is the thread through \u{201C}\(title)\u{201D}?"
    }
}

private struct StoredNoteDocument: Codable {
    var title: String
    var steps: [ExplorationStep]
    var annotations: [String: String]
    var organized: String
    var organizationTemplate: OrganizationTemplate?
    var thoughtGraph: ThoughtGraph?
    /// The note written beside the captures — the thing the reader view lets
    /// you live-edit while scrolling the stream. It was rendered into the
    /// markdown but never stored here, and `loadNote` blanked it on every
    /// open, so any note typed beside a capture was lost the moment the note
    /// was reopened. Optional with a default so sidecars written before this
    /// field still decode, and so the existing initialiser call sites are
    /// unaffected.
    /// Every organized version this note has produced, keyed by template.
    /// Switching between Bullet list / Essay / Meeting notes then costs
    /// nothing — the model only runs for a shape that hasn't been made yet.
    var organizedVariants: [String: String]? = nil
    var rawDraft: String? = nil
    /// Same story for the free-standing thoughts block.
    var annotationDraft: String? = nil
}

@MainActor
final class AppState: ObservableObject {
    let sessionDir: URL
    let settingsURL: URL
    let permissionCenter: PermissionCenter
    private var noteDataDirectory: URL { sessionDir.appendingPathComponent("Note_Data", isDirectory: true) }
    private var workspaceURL: URL { sessionDir.appendingPathComponent("workspace.json") }

    @Published var workspace: Workspace = Workspace()
    @Published var settings: NotefySettings
    @Published var steps: [ExplorationStep] = []
    @Published var vlmResults: [UUID: String] = [:]
    @Published var isTracking = false
    @Published var isPaused = false
    @Published var isRecording = false
    @Published var recordingPurposeIsMeetingNote = false
    @Published var recordingStatus: String?
    @Published var lastSavedSummaryPath: String?
    @Published var historyFiles: [URL] = []
    @Published var audioModelState: ModelRuntimeState = .notDownloaded
    @Published var visionStatus: String = "Not checked"
    @Published var noteTitle: String = "Untitled capture"
    @Published var rawDraft: String = ""

    /// Non-nil while the text button is armed and waiting for a highlight.
    private var armedTextCaptureTask: Task<Void, Never>?
    /// Long enough to switch apps and find the passage, short enough that a
    /// forgotten arm doesn't sit live all afternoon.
    private static let armedTextCaptureTimeout: TimeInterval = 45
    @Published var annotationDraft: String = ""
    @Published var stepAnnotations: [UUID: String] = [:]
    @Published var selectedStepIDs: Set<UUID> = []
    @Published var activeNoteURL: URL?
    @Published var organizedDraft: String = ""
    @Published var organizedGraph: ThoughtGraph? = nil
    @Published var organizedTemplate: OrganizationTemplate = .bulletList
    @Published var organizedVariants: [String: String] = [:]
    @Published var isOrganizing = false
    @Published var audioInputDevices: [AudioInputDevice] = []
    @Published var microphonePowerDB: Float = -160
    @Published var systemAudioPowerDB: Float = -160
    @Published var microphoneSourceActive = false
    @Published var systemAudioSourceActive = false
    @Published var isShowingPermissionOnboarding: Bool
    /// Setup ends with the user taking their first capture, so the rail has to
    /// be reachable while onboarding is still on screen.
    @Published var onboardingCaptureUnlocked = false

    let whisperTranscriber = LocalWhisperTranscriber()

    private let tracker: ExplorationTracker
    private let meetingRecorder = MeetingRecorder()
    private let meetingDetection = MeetingDetectionController()
    private var audioClient: AudioClient
    private var visionClient: VisionClient
    private var isChangingRecordingState = false
    private var cancellables = Set<AnyCancellable>()
    private var autosaveTask: Task<Void, Never>?
    private let regionSelection = RegionSelectionController()
    private let captureReview = CaptureReviewController()
    private let recordingNotepad = RecordingNotepadController()
    private let instructionToast = InstructionToastController()
    private lazy var capturePet = CapturePetController(
        captureText: { [weak self] in self?.captureSelectedText() },
        capturePage: { [weak self] in self?.captureActivePage() },
        captureRegion: { [weak self] in self?.captureSelectedRegion() },
        toggleAudio: { [weak self] in self?.toggleSessionVoiceNote() },
        toggleMeeting: { [weak self] in self?.toggleMeetingNote() }
    )
    private lazy var hotkeys = GlobalHotkeyController(
        onMeeting: { [weak self] in
            guard let self, !self.isRecording || self.recordingPurposeIsMeetingNote else { return }
            self.toggleMeetingNote()
        },
        onSelectedText: { [weak self] in self?.captureSelectedTextFromHotkey() },
        onPage: { [weak self] in self?.captureActivePage() },
        onRegion: { [weak self] in self?.captureSelectedRegion() },
        onSessionAudio: { [weak self] in self?.toggleSessionVoiceNote() },
        onCaptureRail: { [weak self] in self?.capturePet.toggle() }
    )

    init() {
        let permissionCenter = PermissionCenter()
        self.permissionCenter = permissionCenter
        self.isShowingPermissionOnboarding = !UserDefaults.standard.bool(forKey: PermissionCenter.completionKey)
            || !permissionCenter.snapshot.allGranted

        let dir = MindspaceStorage.defaultDirectory()

        self.sessionDir = dir
        self.settingsURL = dir.appendingPathComponent("settings.json")
        var loaded = NotefySettings.load(from: settingsURL)
        // A hosted model name under the on-device provider is always wrong —
        // it produced hints like "ollama pull gemini-2.5-flash".
        if loaded.vision.provider == .local,
           loaded.vision.modelName.contains("gemini") || loaded.vision.modelName.contains("gpt")
            || loaded.vision.modelName.contains("claude") {
            loaded.vision.modelName = ModelProvider.local.defaultVisionModel
        }
        if loaded.audio.provider == .local && !Self.isLocalWhisperVariant(loaded.audio.modelName) {
            loaded.audio.modelName = "base"
            loaded.save(to: settingsURL)
        }
        // qwen2-vl was the old default before qwen3.5:9b (real vision + text synthesis,
        // confirmed working via Ollama) replaced it; carry existing installs forward.
        if loaded.vision.provider == .local && loaded.vision.modelName == "qwen2-vl" {
            loaded.vision.modelName = "qwen3.5:9b"
            loaded.save(to: settingsURL)
        }
        self.settings = loaded
        self.audioClient = AudioClient(config: loaded.audio)
        self.visionClient = VisionClient(config: loaded.vision)
        self.tracker = ExplorationTracker(outputDir: dir)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("Note_Data", isDirectory: true), withIntermediateDirectories: true)
        self.workspace = Workspace.load(from: dir.appendingPathComponent("workspace.json"))

        tracker.onStepCaptured = { [weak self] step in
            Task { @MainActor in
                self?.handleCaptured(step)
            }
        }

        meetingRecorder.onLevels = { [weak self] levels in
            Task { @MainActor in
                self?.microphonePowerDB = levels.microphoneDecibels
                self?.systemAudioPowerDB = levels.systemAudioDecibels
            }
        }

        meetingDetection.shouldSuggest = { [weak self] in
            guard let self else { return false }
            return !self.isRecording && !self.isChangingRecordingState
        }
        meetingDetection.onAccept = { [weak self] in
            guard let self, !self.isRecording, !self.isChangingRecordingState else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.toggleMeetingNote()
        }
        meetingDetection.start()

        whisperTranscriber.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.audioModelState = state }
            .store(in: &cancellables)

        refreshHistory()
        openMostRecentNoteOrCreate()
        refreshAudioInputDevices()

        if settings.audio.provider == .local {
            Task { await whisperTranscriber.ensureReady(variant: settings.audio.modelName) }
        }
        checkVisionStatus()
    }

    func installHotkeys() {
        hotkeys.start()
    }

    /// Bindings macOS would not register — the system already owns them.
    @Published var hotkeyConflicts: Set<HotkeyAction> = []

    /// Called after the user rebinds a shortcut.
    func reloadHotkeys() {
        hotkeyConflicts = Set(hotkeys.restart())
    }

    func showCapturePet() {
        guard !isShowingPermissionOnboarding || onboardingCaptureUnlocked else { return }
        capturePet.show()
    }

    func toggleCaptureRail() {
        guard !isShowingPermissionOnboarding || onboardingCaptureUnlocked else { return }
        capturePet.toggle()
    }

    func showPermissionOnboarding() {
        capturePet.hide()
        permissionCenter.refresh()
        isShowingPermissionOnboarding = true
    }

    func finishPermissionOnboarding() {
        permissionCenter.markComplete()
        isShowingPermissionOnboarding = false
        capturePet.show()
    }

    func refreshAudioInputDevices() {
        audioInputDevices = MeetingRecorder.availableInputDevices()
    }

    var recentNoteDestinations: [NoteDestination] {
        Array(allNoteDestinationsByRecency.prefix(5))
    }

    /// Every real note (excluding generated "Organized_Note_" exports), newest-opened first.
    var allNoteDestinationsByRecency: [NoteDestination] {
        realNoteFiles.map { NoteDestination(url: $0, title: title(for: $0)) }
            .sorted { lastOpened($0.url) > lastOpened($1.url) }
    }

    /// Oldest first: this is the stable reading order used by the bounded canvas.
    /// Opening a note never changes its position.
    var canvasNoteSnapshots: [CanvasNoteSnapshot] {
        realNoteFiles.map { url in
            let document = loadDocument(for: url)
            let resource = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let createdAt = resource?.creationDate ?? resource?.contentModificationDate ?? .distantPast
            let folderID = folderID(for: url)
            let organized = document?.organized.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let firstCapture = document?.steps.reversed().first
            let captureText = firstCapture?.selectedText
                ?? firstCapture?.pageText
                ?? firstCapture?.windowTitle
                ?? ""
            let rawFile = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let excerptSource = organized.isEmpty ? (captureText.isEmpty ? rawFile : captureText) : organized
            return CanvasNoteSnapshot(
                url: url,
                title: document?.title ?? title(for: url),
                excerpt: canvasExcerpt(from: excerptSource),
                createdAt: createdAt,
                folderID: folderID,
                folderName: folderPath(for: folderID),
                captureCount: document?.steps.count ?? 0,
                hasOrganizedNote: !organized.isEmpty
            )
        }
        .sorted { lhs, rhs in
            let leftPosition = workspace.noteMeta[lhs.url.lastPathComponent]?.canvasPosition
            let rightPosition = workspace.noteMeta[rhs.url.lastPathComponent]?.canvasPosition
            switch (leftPosition, rightPosition) {
            case let (left?, right?) where left != right: return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if lhs.createdAt == rhs.createdAt {
                    return lhs.url.lastPathComponent < rhs.url.lastPathComponent
                }
                return lhs.createdAt < rhs.createdAt
            }
        }
    }

    /// Reorders one capture within the open note, for the grid's drag.
    ///
    /// `steps` is stored oldest-first and every view renders it reversed, so
    /// "drop A before B" in the grid is an insert AFTER B in storage. Doing
    /// the flip here rather than at the call site keeps the one place that
    /// knows about the reversal in the model.
    func moveCapture(_ sourceID: UUID, before targetID: UUID) {
        guard sourceID != targetID,
              let from = steps.firstIndex(where: { $0.id == sourceID })
        else { return }
        let step = steps.remove(at: from)
        guard let target = steps.firstIndex(where: { $0.id == targetID }) else {
            steps.insert(step, at: from)
            return
        }
        steps.insert(step, at: target + 1)
        scheduleActiveNoteAutosave()
    }

    /// Nudges a capture one place along the grid's display order, for the
    /// arrow keys. `steps` is stored oldest-first and displayed reversed, so
    /// moving RIGHT on screen is moving LEFT in storage — the flip lives here
    /// alongside moveCapture rather than at the call site.
    @discardableResult
    func nudgeCapture(_ id: UUID, by delta: Int) -> Bool {
        guard delta != 0, let from = steps.firstIndex(where: { $0.id == id }) else { return false }
        let to = from - delta
        guard steps.indices.contains(to) else { return false }
        let step = steps.remove(at: from)
        steps.insert(step, at: to)
        scheduleActiveNoteAutosave()
        return true
    }

    func moveCanvasNote(_ sourceURL: URL, to targetURL: URL) {
        var ordered = canvasNoteSnapshots.map(\.url)
        guard let sourceIndex = ordered.firstIndex(of: sourceURL),
              let targetIndex = ordered.firstIndex(of: targetURL),
              sourceIndex != targetIndex else { return }
        let source = ordered.remove(at: sourceIndex)
        ordered.insert(source, at: targetIndex)
        persistCanvasOrder(ordered)
    }

    func swapCanvasNotes(_ firstURL: URL, _ secondURL: URL) {
        var ordered = canvasNoteSnapshots.map(\.url)
        guard let firstIndex = ordered.firstIndex(of: firstURL),
              let secondIndex = ordered.firstIndex(of: secondURL),
              firstIndex != secondIndex else { return }
        ordered.swapAt(firstIndex, secondIndex)
        persistCanvasOrder(ordered)
    }

    private func persistCanvasOrder(_ ordered: [URL]) {
        for (index, url) in ordered.enumerated() {
            var meta = workspace.noteMeta[url.lastPathComponent] ?? NoteMeta()
            meta.canvasPosition = index
            workspace.noteMeta[url.lastPathComponent] = meta
        }
        saveWorkspace()
        objectWillChange.send()
    }

    private func canvasExcerpt(from markdown: String) -> String {
        let cleaned = markdown
            .components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(of: #"^\s{0,3}(#{1,6}|[-*]>?|\d+\.)\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"[`*_\[\]()]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty && !$0.hasPrefix("!") }
            .dropFirst()
            .joined(separator: " ")
        return cleaned.isEmpty ? "A new note waiting for its first capture." : String(cleaned.prefix(210))
    }

    var pinnedNoteDestinations: [NoteDestination] {
        realNoteFiles
            .filter { isPinned($0) }
            .map { NoteDestination(url: $0, title: title(for: $0)) }
            .sorted { lastOpened($0.url) > lastOpened($1.url) }
    }

    private var realNoteFiles: [URL] {
        historyFiles.filter { !$0.lastPathComponent.hasPrefix("Organized_Note_") }
    }

    var activeNoteTitle: String { noteTitle }

    func selectNoteDestination(_ destination: NoteDestination) {
        persistCurrentRawNote()
        loadNote(destination.url)
        recordingStatus = "Saving new captures to \(destination.title)"
    }

    /// General-purpose "open this note in the editor" used by the sidebar/library —
    /// unlike `selectNoteDestination` it doesn't announce a status message.
    func openNote(_ url: URL) {
        guard url != activeNoteURL else { return }
        persistCurrentRawNote()
        loadNote(url)
    }

    // MARK: - Folders & note organization

    func folders(withParent parentID: UUID?) -> [NoteFolder] {
        workspace.folders.filter { $0.parentID == parentID }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func notes(inFolder targetFolderID: UUID?) -> [NoteDestination] {
        realNoteFiles
            .filter { folderID(for: $0) == targetFolderID }
            .map { NoteDestination(url: $0, title: title(for: $0)) }
            .sorted { lastOpened($0.url) > lastOpened($1.url) }
    }

    /// Notes not yet filed into any folder.
    var unfiledNoteDestinations: [NoteDestination] { notes(inFolder: nil) }

    func folderID(for url: URL) -> UUID? {
        workspace.noteMeta[url.lastPathComponent]?.folderID
    }

    func folderPath(for folderID: UUID?) -> String {
        guard let folderID, let folder = workspace.folders.first(where: { $0.id == folderID }) else { return "" }
        let parentPath = self.folderPath(for: folder.parentID)
        return parentPath.isEmpty ? folder.name : "\(parentPath)/\(folder.name)"
    }

    @discardableResult
    func createFolder(name: String, parentID: UUID? = nil) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = NoteFolder(name: trimmed.isEmpty ? "New folder" : trimmed, parentID: parentID)
        workspace.folders.append(folder)
        saveWorkspace()
        return folder.id
    }

    /// Where a folder sits on the Aurora canvas. Stored on the folder itself so
    /// the arrangement survives relaunch like any other workspace metadata.
    func setFolderPoint(_ id: UUID, to point: CGPoint) {
        guard let i = workspace.folders.firstIndex(where: { $0.id == id }) else { return }
        workspace.folders[i].x = point.x
        workspace.folders[i].y = point.y
        saveWorkspace()
    }

    func folderPoint(_ id: UUID) -> CGPoint? {
        guard let f = workspace.folders.first(where: { $0.id == id }), let x = f.x, let y = f.y else { return nil }
        return CGPoint(x: x, y: y)
    }

    func renameFolder(_ id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = workspace.folders.firstIndex(where: { $0.id == id }) else { return }
        workspace.folders[idx].name = trimmed
        saveWorkspace()
    }

    func deleteFolder(_ id: UUID) {
        let parent = workspace.folders.first(where: { $0.id == id })?.parentID
        for idx in workspace.folders.indices where workspace.folders[idx].parentID == id {
            workspace.folders[idx].parentID = parent
        }
        workspace.folders.removeAll { $0.id == id }
        for key in workspace.noteMeta.keys where workspace.noteMeta[key]?.folderID == id {
            workspace.noteMeta[key]?.folderID = parent
        }
        saveWorkspace()
    }

    func moveNote(_ url: URL, toFolder folderID: UUID?) {
        var meta = workspace.noteMeta[url.lastPathComponent] ?? NoteMeta()
        meta.folderID = folderID
        workspace.noteMeta[url.lastPathComponent] = meta
        saveWorkspace()
    }

    func togglePinned(_ url: URL) {
        var meta = workspace.noteMeta[url.lastPathComponent] ?? NoteMeta()
        meta.pinned.toggle()
        workspace.noteMeta[url.lastPathComponent] = meta
        saveWorkspace()
    }

    func isPinned(_ url: URL) -> Bool {
        workspace.noteMeta[url.lastPathComponent]?.pinned ?? false
    }

    func lastOpened(_ url: URL) -> Date {
        if let recorded = workspace.noteMeta[url.lastPathComponent]?.lastOpenedAt { return recorded }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private func touchLastOpened(_ url: URL) {
        var meta = workspace.noteMeta[url.lastPathComponent] ?? NoteMeta()
        meta.lastOpenedAt = Date()
        workspace.noteMeta[url.lastPathComponent] = meta
        saveWorkspace()
    }

    func saveWorkspace() {
        workspace.save(to: workspaceURL)
    }

    func renameNote(_ url: URL, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if url == activeNoteURL {
            noteTitle = trimmed
            persistCurrentRawNote()
        } else if var doc = loadDocument(for: url) {
            doc.title = trimmed
            saveDocument(doc, for: url)
        }
    }

    /// Search notes by title or folder path, e.g. "matchpoint/overhaul" or just "overhaul".
    func searchNotes(query: String) -> [NoteDestination] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return allNoteDestinationsByRecency }
        return allNoteDestinationsByRecency.filter { destination in
            let path = folderPath(for: folderID(for: destination.url))
            let full = (path.isEmpty ? destination.title : "\(path)/\(destination.title)").lowercased()
            return full.contains(q)
        }
    }

    private func movePendingCapture(_ step: ExplorationStep, to destination: NoteDestination) {
        steps.removeAll { $0.id == step.id }
        tracker.removeStep(id: step.id)
        persistCurrentRawNote()
        loadNote(destination.url)
        steps.insert(step, at: 0)
    }

    func createNewNote() {
        persistCurrentRawNote()
        _ = tracker.stop()
        _ = tracker.start()
        isTracking = true
        steps = []
        stepAnnotations = [:]
        vlmResults = [:]
        rawDraft = ""
        annotationDraft = ""
        organizedDraft = ""
        organizedTemplate = .bulletList
        noteTitle = "Untitled note"
        activeNoteURL = sessionDir.appendingPathComponent("Note_\(Int(Date().timeIntervalSince1970)).md")
        persistCurrentRawNote()
        touchLastOpened(activeNoteURL!)
        recordingStatus = "New note ready"
    }

    /// Creates a new note filed directly into the given folder (used by the sidebar's
    /// "New note" action within a folder, and by the note-search picker's "New note" option).
    @discardableResult
    func createNewNote(inFolder folderID: UUID?) -> NoteDestination {
        createNewNote()
        let url = activeNoteURL!
        moveNote(url, toFolder: folderID)
        return NoteDestination(url: url, title: noteTitle)
    }

    func saveActiveNote() {
        persistCurrentRawNote()
        recordingStatus = "Saved to \(activeNoteTitle)"
    }

    /// Quiet, debounced persistence for the canvas editor. Editing should feel like
    /// writing on paper, not submitting a form, so this deliberately has no toast.
    func scheduleActiveNoteAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }
            self.persistCurrentRawNote()
        }
    }

    private func movePendingCaptureToNewNote(_ step: ExplorationStep) {
        steps.removeAll { $0.id == step.id }
        tracker.removeStep(id: step.id)
        createNewNote()
        steps.insert(step, at: 0)
    }

    // MARK: - Tracking controls

    func toggleTracking() {
        persistCurrentRawNote()
        recordingStatus = "Saved to \(activeNoteTitle)"
    }

    func togglePause() {
        guard isTracking else { return }
        if isPaused {
            tracker.resume()
        } else {
            tracker.pause()
        }
        isPaused.toggle()
    }

    /// Two ways in, and they want opposite behaviour:
    ///
    ///   ⌘⇧T — you highlight FIRST, then fire the shortcut. Take it now.
    ///   Rail button — you press the button first, THEN go and highlight.
    ///
    /// The old version did the first thing for both, which is why the button
    /// never worked: it told you to "select any text" and then read the
    /// selection in the same breath, always finding nothing. So: if something
    /// is already highlighted, capture it; otherwise arm and wait for a
    /// selection to appear.
    func captureSelectedText() {
        guard ensureCaptureSession() else { return }
        if tracker.peekSelectedText() != nil {
            performSelectedTextCapture()
        } else {
            armSelectedTextCapture()
        }
    }

    /// A global shortcut is an explicit "capture what is selected now" action.
    /// Go straight through the capture path so web editors such as Google Docs,
    /// which do not expose AXSelectedText, can use the clipboard-preserving copy
    /// fallback. The rail button keeps its useful arm-then-highlight behavior.
    func captureSelectedTextFromHotkey() {
        guard ensureCaptureSession() else { return }
        cancelArmedTextCapture()
        performSelectedTextCapture()
    }

    /// Pressing the button again while armed cancels, so an accidental press
    /// isn't a thing you have to wait out.
    func armSelectedTextCapture() {
        if armedTextCaptureTask != nil {
            cancelArmedTextCapture(status: "Text capture cancelled")
            return
        }
        instructionToast.show("Highlight any text — it gets captured automatically")
        recordingStatus = "Waiting for a highlight…"
        armedTextCaptureTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(Self.armedTextCaptureTimeout)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled, let self else { return }
                // Ignore our own windows: the rail and the review panel are
                // ours, and lifting text out of Noted into Noted is never
                // what the button meant.
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    == Bundle.main.bundleIdentifier { continue }
                guard self.tracker.peekSelectedText() != nil else { continue }
                self.armedTextCaptureTask = nil
                self.performSelectedTextCapture()
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.armedTextCaptureTask = nil
            self.recordingStatus = "Nothing highlighted — press the text button or ⌘⇧T again."
        }
    }

    func cancelArmedTextCapture(status: String? = nil) {
        armedTextCaptureTask?.cancel()
        armedTextCaptureTask = nil
        recordingStatus = status
    }

    private func performSelectedTextCapture() {
        recordingStatus = "Lifting selected text…"
        Task { [weak self] in
            guard let self else { return }
            let captured = await self.tracker.captureSelectedText()
            self.recordingStatus = captured
                ? "Selected text ready to keep"
                : "No selected text was available. Keep the text highlighted, then try again."
            self.permissionCenter.refresh()
            if !self.permissionCenter.snapshot.accessibility { self.showPermissionOnboarding() }
        }
    }

    func captureActivePage() {
        guard ensureCaptureSession() else { return }
        recordingStatus = "Capturing active page…"
        Task { [weak self] in
            guard let self else { return }
            let captured = await self.tracker.captureActiveWindow()
            self.recordingStatus = captured
                ? nil
                : "Grant Screen & System Audio Recording access, then quit and reopen Mindspace."
            self.permissionCenter.refresh()
            if !captured && !self.permissionCenter.snapshot.screenRecording {
                self.showPermissionOnboarding()
            }
        }
    }

    func captureSelectedRegion() {
        guard ensureCaptureSession() else { return }
        let source = tracker.currentSourceContext()
        recordingStatus = "Drag over the region to add"
        regionSelection.begin(outputDirectory: sessionDir) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                self.tracker.captureScreenshotFile(url, source: source)
                self.recordingStatus = "Selected region added"
            case .failure(let error):
                self.recordingStatus = error.localizedDescription
                self.permissionCenter.refresh()
                if !self.permissionCenter.snapshot.screenRecording { self.showPermissionOnboarding() }
            }
        }
    }

    /// The name used to refer to the user in generated notes — third person always,
    /// e.g. "Sanjana noted that..." rather than "I noted that...".
    var authorName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if full.isEmpty { return "The author" }
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    /// Full display name for the sidebar's user row — falls back the same way as `authorName`.
    var fullUserDisplayName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "Mindspace user" : full
    }

    /// Real disk usage of the sessions folder (screenshots, audio, notes), sized against a
    /// soft 2GB visual cap — matches the "Storage used" meter shown in the sidebar footer.
    var storageUsedPercent: Int {
        let cap: Double = 2 * 1024 * 1024 * 1024
        let used = Double(directorySizeInBytes(sessionDir))
        return Int((min(used / cap, 1)) * 100)
    }

    private func directorySizeInBytes(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Builds the full system prompt for a template: the shared voice/citation rules plus
    /// that template's exact required Markdown structure. Shared by every provider (local
    /// Ollama, generic cloud API, Gemini) so results are consistent regardless of backend.
    private func systemPrompt(for template: OrganizationTemplate) -> String {
        """
        You are Mindspace's note-synthesis assistant. You are shown one or more screenshots \
        \(authorName) captured while researching or working, each labeled with a source (a \
        website domain, app name, or "Screen region"), and optionally \(authorName)'s own \
        thought about it — typed on the spot, or spoken aloud and transcribed to text.

        Write the note about \(authorName)'s session using EXACTLY this Markdown structure. \
        Fill it in with real content — do not explain the structure, do not add extra \
        top-level sections, do not rename the given headings:

        \(template.structure(authorName: authorName))

        Rules:
        - Third person only. Never write "I" or "my" — \(authorName) is being described, not speaking.
        - Reference concrete details actually visible in each image; never invent facts.
        - Cite each distinct source inline using a descriptive Markdown link to its full URL the first time it is mentioned.
        - Do not add a Sources section; Mindspace renders a verified source ledger below the document.
        - Output valid Markdown only — no commentary about what you're doing, no meta text before or after.
        """
    }

    /// Shows a shape that has already been written; only calls the model when
    /// this note has never been organized that way. `force` re-runs it.
    func showOrganized(_ template: OrganizationTemplate, force: Bool = false) {
        if !force, let cached = organizedVariants[template.rawValue], !cached.isEmpty {
            organizedTemplate = template
            organizedDraft = cached
            recordingStatus = nil
            persistCurrentRawNote()
            return
        }
        organizeCurrentSession(as: template)
    }

    func organizeCurrentSession(as template: OrganizationTemplate = .bulletList) {
        guard !steps.isEmpty || !rawDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recordingStatus = "Add something to the raw note first."
            return
        }
        isOrganizing = true
        organizedTemplate = template
        organizedGraph = ThoughtGraph.build(steps: orderedStepsForGraph, annotations: stepAnnotations, noteTitle: noteTitle)
        let fallback = organizedFallback(for: template)
        let orderedSteps = Array(steps.reversed())

        if template == .diagram && settings.vision.provider == .gemini {
            recordingStatus = "Finding the thread between your thoughts with Gemini…"
            visionClient.generateNote(
                systemPrompt: thoughtGraphPrompt,
                context: thoughtGraphContext(steps: orderedSteps),
                completion: { [weak self] result in
                    Task { @MainActor in
                        guard let self else { return }
                        if case .success(let raw) = result,
                           let graph = self.decodeThoughtGraph(raw, validSourceIDs: Set(orderedSteps.map { $0.id.uuidString })) {
                            self.organizedGraph = graph
                            self.organizedDraft = ""
                            self.recordingStatus = nil
                        } else {
                            self.recordingStatus = "Used a local graph fallback; Gemini did not return valid graph data."
                        }
                        self.persistCurrentRawNote()
                        self.isOrganizing = false
                    }
                }
            )
            return
        }

        let capturesWithScreenshots = orderedSteps.filter { $0.screenshotPath != nil }
        let prompt = systemPrompt(for: template)

        // Notes read best when the model actually looks at the screenshots instead of just
        // their OCR/alt-text — synthesize from the real images whenever the configured
        // provider can see them (local Ollama, Gemini, or a vision-capable cloud API).
        let canUseImages = settings.vision.provider != .api || !settings.vision.apiKey.isEmpty
        if !capturesWithScreenshots.isEmpty, canUseImages {
            recordingStatus = "Looking at \(capturesWithScreenshots.count) capture\(capturesWithScreenshots.count == 1 ? "" : "s") with \(settings.vision.modelName)… this can take a couple of minutes"
            let captures: [VisionClient.MentalNoteCapture] = orderedSteps.map { step in
                let imageBase64 = step.screenshotPath
                    .flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
                    .map { $0.base64EncodedString() }
                return VisionClient.MentalNoteCapture(
                    sourceLabel: mentalNoteSourceLabel(for: step),
                    sourceURL: step.url,
                    thought: stepAnnotations[step.id],
                    imageBase64: imageBase64
                )
            }
            visionClient.generateMentalNote(captures: captures, systemPrompt: prompt) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    switch result {
                    case .success(let note):
                        self.organizedDraft = note
                        self.organizedVariants[template.rawValue] = note
                        self.recordingStatus = nil
                    case .failure(let error):
                        self.organizedDraft = fallback
                        self.recordingStatus = "Model unavailable; made this \(template.rawValue.lowercased()) on-device. \(error.localizedDescription)"
                    }
                    self.persistCurrentRawNote()
                    self.isOrganizing = false
                }
            }
            return
        }

        recordingStatus = "Organizing with \(settings.vision.modelName)…"
        let context = """
        Raw note:
        \(rawDraft)

        \(authorName)'s annotations:
        \(annotationDraft)

        Captures:
        \(explorationContext(steps: orderedSteps, fallback: fallback))
        """
        visionClient.generateNote(systemPrompt: prompt, context: context) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let note):
                    self.organizedDraft = note
                    self.organizedVariants[template.rawValue] = note
                    self.recordingStatus = nil
                case .failure(let error):
                    self.organizedDraft = fallback
                    self.recordingStatus = "Model unavailable; made this \(template.rawValue.lowercased()) on-device. \(error.localizedDescription)"
                }
                self.persistCurrentRawNote()
                self.isOrganizing = false
            }
        }
    }

    private var orderedStepsForGraph: [ExplorationStep] {
        Array(steps.reversed())
    }

    private var thoughtGraphPrompt: String {
        """
        You are reconstructing a person's thinking, not organizing files. First read ALL
        source items together. Extract atomic thoughts, merge repeated ideas, identify the
        central question, then construct a semantic reasoning tree. Preserve uncertainty.

        Return JSON only, with exactly this shape:
        {"centralQuestion":"short conversational question","rootNodeId":"root","nodes":[{"id":"root","title":"...","summary":"...","type":"question","sourceIds":[],"children":[{"nodeId":"...","relationship":"expands"}]}]}

        Allowed types: question, observation, insight, concern, hypothesis, evidence, solution, conclusion.
        Allowed relationships: expands, explains, supports, questions, contradicts, example_of,
        leads_to, consequence, possible_solution, evidence_for.
        Every non-root thought must have a concise semantic title, not a source label or URL.
        Every thought must preserve one or more exact sourceIds from the input. Merge duplicate
        ideas by putting all of their sourceIds on one node. Each node may have 0–3 children;
        never invent branches just to make the graph symmetrical. Do not include Markdown fences.
        """
    }

    private func thoughtGraphContext(steps: [ExplorationStep]) -> String {
        var lines = ["NOTE TITLE: \(noteTitle)", ""]
        for step in steps {
            lines.append("SOURCE ID: \(step.id.uuidString)")
            lines.append("SOURCE: \(mentalNoteSourceLabel(for: step))")
            lines.append("TEXT: \((step.selectedText ?? step.pageText ?? step.windowTitle).prefix(1800))")
            if let thought = stepAnnotations[step.id], !thought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("USER THOUGHT: \(thought.prefix(1800))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func decodeThoughtGraph(_ raw: String, validSourceIDs: Set<String>) -> ThoughtGraph? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            value = value.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = value.firstIndex(of: "{"), let end = value.lastIndex(of: "}") else { return nil }
        let json = String(value[start...end])
        guard let data = json.data(using: .utf8), var graph = try? JSONDecoder().decode(ThoughtGraph.self, from: data), graph.rootNodeId == "root" else { return nil }
        guard graph.nodes.contains(where: { $0.id == graph.rootNodeId }), graph.nodes.allSatisfy({ $0.children.count <= 3 && $0.sourceIds.allSatisfy(validSourceIDs.contains) }) else { return nil }
        graph.nodes = graph.nodes.map { node in
            var cleaned = node
            cleaned.sourceIds = Array(NSOrderedSet(array: node.sourceIds)) as? [String] ?? node.sourceIds
            return cleaned
        }
        return graph
    }

    /// Mirrors the source normalization shown on capture cards (Views/DashboardView.swift)
    /// so the model sees the same clean domain/app label the user sees.
    private func mentalNoteSourceLabel(for step: ExplorationStep) -> String {
        if let host = step.url.flatMap(URL.init(string:))?.host, !host.isEmpty { return host }
        if step.appName == "Audio" { return "Computer audio" }
        if ["Notefy", "Noted", "notefy-app"].contains(step.appName) { return "Screen region" }
        return step.appName
    }

    private func organizedFallback(for template: OrganizationTemplate) -> String {
        let ordered = Array(steps.reversed())
        func excerpt(_ step: ExplorationStep) -> String {
            let value = step.selectedText ?? step.pageText ?? step.windowTitle
            return value.replacingOccurrences(of: "\n", with: " ").prefix(260).description
        }
        switch template {
        case .bulletList:
            var lines = ["# \(noteTitle)", "", "## Key ideas"]
            if ordered.isEmpty, !rawDraft.isEmpty { lines.append("- \(rawDraft.replacingOccurrences(of: "\n", with: " "))") }
            for step in ordered {
                let source = inlineSource(for: step)
                lines.append("- **\(source):** \(excerpt(step))")
                if let thought = stepAnnotations[step.id], !thought.isEmpty {
                    lines.append("  - *My thought:* \(thought)")
                }
            }
            return lines.joined(separator: "\n")
        case .essay:
            var paragraphs = ["# \(noteTitle)", ""]
            if ordered.isEmpty, !rawDraft.isEmpty { paragraphs += [rawDraft, ""] }
            for step in ordered {
                paragraphs += ["## \(step.windowTitle.isEmpty ? step.appName : step.windowTitle)", "", excerpt(step)]
                if let thought = stepAnnotations[step.id], !thought.isEmpty {
                    paragraphs += ["", "My reflection: \(thought)"]
                }
                paragraphs.append("")
            }
            return paragraphs.joined(separator: "\n")
        case .meetingNotes:
            var lines = ["# \(noteTitle)", "", "## Key discussion points"]
            if ordered.isEmpty, !rawDraft.isEmpty {
                lines.append("- \(rawDraft.replacingOccurrences(of: "\n", with: " "))")
            }
            for step in ordered {
                lines.append("- **\(step.appName):** \(excerpt(step))")
                if let thought = stepAnnotations[step.id], !thought.isEmpty {
                    lines.append("  - *Note:* \(thought)")
                }
            }
            lines += ["", "## Decisions", "- No decisions recorded.", "", "## Action items", "- [ ] No action items recorded."]
            return lines.joined(separator: "\n")
        case .diagram:
            var lines = ["# \(noteTitle)", "", "```mermaid", "flowchart TD"]
            if ordered.isEmpty, !rawDraft.isEmpty {
                let clean = rawDraft.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ").prefix(240)
                lines.append("  S0[\"\(clean)\"]")
            }
            for (index, step) in ordered.enumerated() {
                let label = "\(step.appName): \(excerpt(step))"
                    .replacingOccurrences(of: "\"", with: "'")
                lines.append("  S\(index)[\"\(label)\"]")
                if index > 0 { lines.append("  S\(index - 1) --> S\(index)") }
                if let thought = stepAnnotations[step.id], !thought.isEmpty {
                    let clean = thought.replacingOccurrences(of: "\"", with: "'").prefix(180)
                    lines.append("  S\(index) --> T\(index)[\"My thought: \(clean)\"]")
                }
            }
            lines += ["```", ""]
            return lines.joined(separator: "\n")
        }
    }

    private func inlineSource(for step: ExplorationStep) -> String {
        guard let rawURL = step.url,
              let url = URL(string: rawURL),
              let host = url.host,
              !host.isEmpty
        else { return step.appName }
        return "[\(host)](\(rawURL))"
    }

    /// Voice note captured *during* an active exploration session — folded into that session's timeline.
    func toggleSessionVoiceNote() {
        guard ensureCaptureSession() else { return }
        guard !isChangingRecordingState,
              !isRecording || !recordingPurposeIsMeetingNote else { return }
        if isRecording && !recordingPurposeIsMeetingNote && recordingNotepad.isVisible {
            recordingNotepad.insertTimestamp()
            recordingStatus = "Timestamp added to audio notes"
            return
        }
        isChangingRecordingState = true
        Task { [weak self] in
            guard let self else { return }
            if self.isRecording {
                await self.stopSessionAudio()
            } else {
                await self.startSessionAudio()
            }
            self.isChangingRecordingState = false
        }
    }

    private func startSessionAudio() async {
        recordingStatus = "Starting computer audio…"
        do {
            try await meetingRecorder.startComputerAudioOnly()
            isRecording = true
            recordingPurposeIsMeetingNote = false
            microphoneSourceActive = false
            systemAudioSourceActive = meetingRecorder.isSystemAudioActive
            recordingStatus = "Recording computer audio"
            let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Mac audio"
            recordingNotepad.show(
                kind: .audio,
                sourceApp: sourceApp,
                microphoneDB: { [weak self] in self?.microphonePowerDB ?? -60 },
                systemDB: { [weak self] in self?.systemAudioPowerDB ?? -60 },
                onEnd: { [weak self] in self?.endSessionAudioFromNotepad() }
            )
        } catch {
            microphoneSourceActive = false
            systemAudioSourceActive = false
            recordingStatus = "Could not start computer audio: \(error.localizedDescription)"
            permissionCenter.refresh()
            if !permissionCenter.snapshot.screenRecording {
                showPermissionOnboarding()
            }
        }
    }

    private func stopSessionAudio() async {
        recordingStatus = "Finishing session audio…"
        let notepadNotes = recordingNotepad.takeNotesAndClose()
        guard let artifacts = await meetingRecorder.stop() else {
            isRecording = false
            microphoneSourceActive = false
            systemAudioSourceActive = false
            recordingStatus = nil
            return
        }
        isRecording = false
        microphoneSourceActive = false
        systemAudioSourceActive = false
        var sections: [String] = []
        var failures: [String] = []
        if let systemURL = artifacts.systemAudioURL {
            switch await transcribe(audioURL: systemURL) {
            case .success(let text): sections.append(text)
            case .failure(let error): failures.append("Computer audio: \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: systemURL)
        }

        handleTranscription(
            sections.joined(separator: "\n\n"),
            purpose: .sessionVoiceNote,
            annotation: notepadNotes
        )
        persistCurrentRawNote()
        recordingStatus = failures.isEmpty
            ? "Computer audio saved to \(activeNoteTitle)"
            : "Computer audio saved, but transcription needs attention: \(failures.joined(separator: "; "))"
    }

    private func endSessionAudioFromNotepad() {
        guard isRecording, !recordingPurposeIsMeetingNote, !isChangingRecordingState else { return }
        isChangingRecordingState = true
        Task { [weak self] in
            guard let self else { return }
            await self.stopSessionAudio()
            self.isChangingRecordingState = false
        }
    }

    /// Standalone "meeting note" — works anytime, independent of exploration tracking,
    /// and is saved as its own note in History.
    func toggleMeetingNote() {
        guard !isChangingRecordingState else { return }
        isChangingRecordingState = true
        Task { [weak self] in
            guard let self else { return }
            if self.isRecording {
                await self.stopMeetingRecording()
            } else {
                await self.startMeetingRecording()
            }
            self.isChangingRecordingState = false
        }
    }

    private func startMeetingRecording() async {
        guard !isRecording else { return }
        recordingStatus = "Starting microphone and computer audio…"
        let microphoneURL = sessionDir.appendingPathComponent("meeting_mic_\(UUID().uuidString).wav")
        do {
            meetingRecorder.preferredInputDeviceUID = settings.audio.inputDeviceUID
            let warning = try await meetingRecorder.start(saveMicrophoneTo: microphoneURL)
            isRecording = true
            recordingPurposeIsMeetingNote = true
            microphoneSourceActive = true
            systemAudioSourceActive = meetingRecorder.isSystemAudioActive
            recordingStatus = warning ?? "Recording microphone and computer audio"
            let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Meeting app"
            recordingNotepad.show(
                kind: .meeting,
                sourceApp: sourceApp,
                microphoneDB: { [weak self] in self?.microphonePowerDB ?? -60 },
                systemDB: { [weak self] in self?.systemAudioPowerDB ?? -60 },
                onEnd: { [weak self] in self?.endMeetingFromNotepad() }
            )
        } catch {
            microphoneSourceActive = false
            systemAudioSourceActive = false
            recordingStatus = "Could not start meeting recording: \(error.localizedDescription)"
            permissionCenter.refresh()
            if !permissionCenter.snapshot.microphone || !permissionCenter.snapshot.screenRecording {
                showPermissionOnboarding()
            }
        }
    }

    private func stopMeetingRecording() async {
        recordingStatus = "Finishing recording…"
        let notepadNotes = recordingNotepad.takeNotesAndClose()
        guard let artifacts = await meetingRecorder.stop() else {
            isRecording = false
            recordingPurposeIsMeetingNote = false
            microphoneSourceActive = false
            systemAudioSourceActive = false
            recordingStatus = nil
            return
        }
        isRecording = false
        recordingPurposeIsMeetingNote = false
        microphoneSourceActive = false
        systemAudioSourceActive = false
        recordingStatus = "Transcribing locally…"

        var sections: [String] = []
        var failures: [String] = []
        if let microphoneURL = artifacts.microphoneURL {
            let microphoneResult = await transcribe(audioURL: microphoneURL)
            switch microphoneResult {
            case .success(let text):
                sections.append("## You (microphone)\n\n\(text)")
            case .failure(let error):
                failures.append("Microphone: \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: microphoneURL)
        }

        if let systemURL = artifacts.systemAudioURL {
            let systemResult = await transcribe(audioURL: systemURL)
            switch systemResult {
            case .success(let text):
                sections.append("## Other participants (computer audio)\n\n\(text)")
            case .failure(let error):
                failures.append("Computer audio: \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: systemURL)
        }

        handleTranscription(
            sections.joined(separator: "\n\n"),
            purpose: .standaloneMeetingNote,
            annotation: notepadNotes
        )
        recordingStatus = failures.isEmpty
            ? "Meeting note saved to \(activeNoteTitle)"
            : "Meeting notes saved, but transcription needs attention: \(failures.joined(separator: "; "))"
    }

    private func endMeetingFromNotepad() {
        guard isRecording, recordingPurposeIsMeetingNote, !isChangingRecordingState else { return }
        isChangingRecordingState = true
        Task { [weak self] in
            guard let self else { return }
            await self.stopMeetingRecording()
            self.isChangingRecordingState = false
        }
    }

    private func transcribe(audioURL: URL) async -> Result<String, Error> {
        if settings.audio.provider == .local {
            return await whisperTranscriber.transcribe(audioURL: audioURL, variant: settings.audio.modelName)
        }
        return await withCheckedContinuation { continuation in
            audioClient.transcribe(audioURL: audioURL) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func handleTranscription(_ text: String, purpose: RecordingPurpose, annotation: String = "") {
        guard !text.isEmpty || !annotation.isEmpty else { return }
        _ = ensureCaptureSession()
        let step = ExplorationStep(
            appName: purpose == .sessionVoiceNote ? "Computer audio" : "Meeting",
            windowTitle: purpose == .sessionVoiceNote ? "Computer audio recording" : "Meeting note",
            selectedText: text.isEmpty ? nil : text
        )
        tracker.captureCustomStep(step)
        if !annotation.isEmpty { stepAnnotations[step.id] = annotation }
        persistCurrentRawNote()
    }

    private func explorationContext(steps: [ExplorationStep], fallback: String) -> String {
        var context = fallback
        for step in steps {
            context += "\n\n---\nApp: \(step.appName)\nWindow: \(step.windowTitle)"
            if let url = step.url { context += "\nURL: \(url)" }
            if let selected = step.selectedText { context += "\nSelected text: \(selected)" }
            if let pageText = step.pageText { context += "\nBrowser page text:\n\(pageText)" }
            if let analysis = vlmResults[step.id] { context += "\nScreen analysis:\n\(analysis)" }
            if let thought = stepAnnotations[step.id], !thought.isEmpty {
                context += "\nUser annotation:\n\(thought)"
            }
        }
        return context
    }

    private func handleCaptured(_ step: ExplorationStep) {
        steps.insert(step, at: 0)
        let isRecordedTranscript = step.appName == "Audio"
            || step.appName == "Computer audio"
            || step.appName == "Meeting"
        let shouldReview = !isRecordedTranscript && (
            step.screenshotPath != nil
                || (step.appName != "Notefy Voice" && !(step.selectedText ?? "").isEmpty)
        )
        if shouldReview {
            captureReview.present(
                step: step,
                appState: self,
                destinationTitle: activeNoteTitle,
                destinations: recentNoteDestinations,
                onSelectDestination: { [weak self] destination in self?.movePendingCapture(step, to: destination) },
                onCreateNote: { [weak self] in self?.movePendingCaptureToNewNote(step) },
                onTranscribeVoice: { [weak self] url in
                    guard let self else {
                        return .failure(NSError(
                            domain: "Notefy.CaptureVoice",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Mindspace closed before transcription finished."]
                        ))
                    }
                    return await self.transcribe(audioURL: url)
                },
                onKeep: { [weak self] note, voiceURL in
                    self?.keepReviewedCapture(step, note: note, voiceURL: voiceURL)
                },
                onDiscard: { [weak self] in self?.discardReviewedCapture(step) }
            )
        } else {
            appendCaptureToRaw(step)
        }
        guard let screenshot = step.screenshotPath else { return }
        let screenshotURL = URL(fileURLWithPath: screenshot)
        visionClient.analyzeScreen(imageURL: screenshotURL) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                guard self.steps.contains(where: { $0.id == step.id }) else { return }
                switch result {
                case .success(let analysis):
                    self.vlmResults[step.id] = analysis
                case .failure:
                    self.vlmResults[step.id] = nil
                }
            }
        }
    }

    private func keepReviewedCapture(_ step: ExplorationStep, note: String, voiceURL: URL?) {
        appendCaptureToRaw(step)
        if !note.isEmpty {
            stepAnnotations[step.id] = note
        }
        persistCurrentRawNote()
        guard let voiceURL else { return }
        recordingStatus = "Transcribing capture voice note locally…"
        Task { [weak self] in
            guard let self else { return }
            let result = await self.transcribe(audioURL: voiceURL)
            try? FileManager.default.removeItem(at: voiceURL)
            if case .success(let text) = result, !text.isEmpty {
                let existing = self.stepAnnotations[step.id].map { $0 + "\n" } ?? ""
                self.stepAnnotations[step.id] = existing + text
            } else if case .failure(let error) = result {
                self.recordingStatus = "Voice note could not be transcribed: \(error.localizedDescription)"
            }
            self.persistCurrentRawNote()
            if case .success = result { self.recordingStatus = nil }
        }
    }

    private func discardReviewedCapture(_ step: ExplorationStep) {
        tracker.removeStep(id: step.id)
        steps.removeAll { $0.id == step.id }
        stepAnnotations[step.id] = nil
        vlmResults[step.id] = nil
        if let path = step.screenshotPath { try? FileManager.default.removeItem(atPath: path) }
        if let path = step.htmlPath { try? FileManager.default.removeItem(atPath: path) }
        persistCurrentRawNote()
        recordingStatus = "Capture discarded"
    }

    private func appendCaptureToRaw(_ step: ExplorationStep) {
        persistCurrentRawNote()
    }

    // MARK: - Chunk selection (move / forward / delete capture cards)

    func toggleStepSelection(_ id: UUID) {
        if selectedStepIDs.contains(id) {
            selectedStepIDs.remove(id)
        } else {
            selectedStepIDs.insert(id)
        }
    }

    func clearStepSelection() {
        selectedStepIDs = []
    }

    /// Removes the selected capture cards from the current note. Only strips them from this
    /// note's data — the underlying screenshot files are left alone, since a forwarded copy
    /// in another note may still reference them.
    func deleteSelectedSteps() {
        guard !selectedStepIDs.isEmpty else { return }
        let ids = selectedStepIDs
        for id in ids {
            tracker.removeStep(id: id)
            stepAnnotations[id] = nil
            vlmResults[id] = nil
        }
        steps.removeAll { ids.contains($0.id) }
        selectedStepIDs = []
        persistCurrentRawNote()
        recordingStatus = "Deleted \(ids.count) capture\(ids.count == 1 ? "" : "s")"
    }

    /// Moves (or copies, if `keepInCurrent`) the selected capture cards into another note,
    /// found via the search picker. Works whether or not that note is currently open.
    func relocateSelectedSteps(to destination: NoteDestination, keepInCurrent: Bool) {
        guard !selectedStepIDs.isEmpty else { return }
        let ids = selectedStepIDs
        let moved = steps.filter { ids.contains($0.id) }
        guard !moved.isEmpty else { selectedStepIDs = []; return }

        if destination.url == activeNoteURL {
            selectedStepIDs = []
            recordingStatus = "Already in \(destination.title)"
            return
        }

        var destinationDocument = loadDocument(for: destination.url) ?? StoredNoteDocument(
            title: destination.title,
            steps: [],
            annotations: [:],
            organized: "",
            organizationTemplate: .bulletList,
            thoughtGraph: nil
        )
        destinationDocument.steps = moved + destinationDocument.steps
        for step in moved {
            if let thought = stepAnnotations[step.id] {
                destinationDocument.annotations[step.id.uuidString] = thought
            }
        }
        saveDocument(destinationDocument, for: destination.url)

        if !keepInCurrent {
            for id in ids {
                tracker.removeStep(id: id)
                stepAnnotations[id] = nil
                vlmResults[id] = nil
            }
            steps.removeAll { ids.contains($0.id) }
            persistCurrentRawNote()
        }
        selectedStepIDs = []
        recordingStatus = keepInCurrent
            ? "Forwarded \(moved.count) capture\(moved.count == 1 ? "" : "s") to \(destination.title)"
            : "Moved \(moved.count) capture\(moved.count == 1 ? "" : "s") to \(destination.title)"
    }

    /// Creates a brand-new note and immediately relocates the current selection into it.
    @discardableResult
    func relocateSelectedSteps(toNewNoteNamed name: String, keepInCurrent: Bool) -> NoteDestination {
        let previousActive = activeNoteURL
        let previousTitle = noteTitle
        createNewNote()
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteTitle = name
            persistCurrentRawNote()
        }
        let destination = NoteDestination(url: activeNoteURL!, title: noteTitle)
        // Switch back to the note the selection came from so relocate(to:) can read `steps` from it.
        if let previousActive {
            loadNote(previousActive)
            noteTitle = previousTitle
        }
        relocateSelectedSteps(to: destination, keepInCurrent: keepInCurrent)
        return destination
    }

    @discardableResult
    private func ensureCaptureSession() -> Bool {
        if activeNoteURL == nil { createNewNote() }
        guard !isTracking else { return true }
        guard tracker.start() else {
            recordingStatus = "Could not start a working note."
            return false
        }
        isTracking = true
        isPaused = false
        return true
    }

    private func renderNoteMarkdown(
        title: String,
        rawDraft: String,
        steps: [ExplorationStep],
        annotations: [UUID: String],
        annotationDraft: String
    ) -> String {
        var lines = ["# \(title)", ""]
        if !rawDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines += [rawDraft, ""]
        }
        for step in steps.reversed() {
            lines += ["## \(step.appName) · \(step.timestamp.formatted(date: .omitted, time: .shortened))"]
            if let selected = step.selectedText, !selected.isEmpty { lines += ["", selected] }
            if let screenshot = step.screenshotPath { lines += ["", "![Capture](\(screenshot))"] }
            if let annotation = annotations[step.id], !annotation.isEmpty {
                lines += ["", "> My thought: \(annotation)"]
            }
            lines.append("")
        }
        if !annotationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines += ["## My thoughts", "", annotationDraft]
        }
        return lines.joined(separator: "\n")
    }

    private func persistCurrentRawNote() {
        guard let activeNoteURL else { return }
        let markdown = renderNoteMarkdown(
            title: noteTitle,
            rawDraft: rawDraft,
            steps: steps,
            annotations: stepAnnotations,
            annotationDraft: annotationDraft
        )
        try? markdown.write(to: activeNoteURL, atomically: true, encoding: .utf8)

        let document = StoredNoteDocument(
            title: noteTitle,
            steps: steps,
            annotations: Dictionary(uniqueKeysWithValues: stepAnnotations.map { ($0.key.uuidString, $0.value) }),
            organized: organizedDraft,
            organizationTemplate: organizedTemplate,
            thoughtGraph: organizedGraph,
            organizedVariants: organizedVariants,
            rawDraft: rawDraft,
            annotationDraft: annotationDraft
        )
        if let data = try? JSONEncoder().encode(document) {
            try? data.write(to: sidecarURL(for: activeNoteURL), options: .atomic)
        }
        refreshHistory()
    }

    /// Reads another note's sidecar document without disturbing the currently open note —
    /// used by chunk move/forward and by "save this recording to a different note".
    private func loadDocument(for url: URL) -> StoredNoteDocument? {
        guard let data = try? Data(contentsOf: sidecarURL(for: url)) else { return nil }
        guard let decoded = try? JSONDecoder().decode(StoredNoteDocument.self, from: data) else { return nil }
        let (document, changed) = documentByRepairingAssetPaths(decoded)
        if changed, let repairedData = try? JSONEncoder().encode(document) {
            try? repairedData.write(to: sidecarURL(for: url), options: .atomic)
        }
        return document
    }

    /// Sidecars historically stored absolute capture paths. When
    /// `Notefy_Sessions` became `Mindspace`, the directory moved intact but
    /// those strings did not. Rebase only references whose old target is gone
    /// and whose corresponding file is present in the active data directory.
    private func documentByRepairingAssetPaths(
        _ source: StoredNoteDocument
    ) -> (document: StoredNoteDocument, changed: Bool) {
        var document = source
        var changed = false
        document.steps = source.steps.map { step in
            let screenshot = MindspaceStorage.rebasedAssetPath(step.screenshotPath, in: sessionDir)
            let html = MindspaceStorage.rebasedAssetPath(step.htmlPath, in: sessionDir)
            if screenshot != step.screenshotPath || html != step.htmlPath { changed = true }
            return ExplorationStep(
                id: step.id,
                timestamp: step.timestamp,
                appName: step.appName,
                windowTitle: step.windowTitle,
                url: step.url,
                selectedText: step.selectedText,
                screenshotPath: screenshot,
                htmlPath: html,
                pageText: step.pageText
            )
        }
        return (document, changed)
    }

    /// Writes another note's sidecar document + regenerates its markdown file, again without
    /// touching the currently open note's editor state.
    private func saveDocument(_ document: StoredNoteDocument, for url: URL) {
        let annotations = Dictionary(uniqueKeysWithValues: document.annotations.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
        let markdown = renderNoteMarkdown(
            title: document.title,
            rawDraft: document.rawDraft ?? "",
            steps: document.steps,
            annotations: annotations,
            annotationDraft: document.annotationDraft ?? ""
        )
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
        if let data = try? JSONEncoder().encode(document) {
            try? data.write(to: sidecarURL(for: url), options: .atomic)
        }
        refreshHistory()
    }

    private func openMostRecentNoteOrCreate() {
        if let recent = historyFiles.first(where: { !$0.lastPathComponent.hasPrefix("Organized_Note_") }) {
            loadNote(recent)
        } else {
            createNewNote()
        }
    }

    func deleteNote(_ url: URL) {
        let wasActive = url == activeNoteURL
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: sidecarURL(for: url))
        workspace.noteMeta.removeValue(forKey: url.lastPathComponent)
        saveWorkspace()
        refreshHistory()
        if wasActive {
            activeNoteURL = nil
            openMostRecentNoteOrCreate()
        }
    }

    private func loadNote(_ url: URL) {
        activeNoteURL = url
        touchLastOpened(url)
        _ = tracker.stop()
        _ = tracker.start()
        isTracking = true
        vlmResults = [:]
        if let document = loadDocument(for: url) {
            noteTitle = document.title
            steps = document.steps
            stepAnnotations = Dictionary(uniqueKeysWithValues: document.annotations.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
            organizedDraft = document.organized
            organizedGraph = document.thoughtGraph
            organizedTemplate = document.organizationTemplate ?? .bulletList
            organizedVariants = document.organizedVariants ?? [:]
            if organizedVariants.isEmpty, !document.organized.isEmpty {
                organizedVariants[(document.organizationTemplate ?? .bulletList).rawValue] = document.organized
            }
            rawDraft = document.rawDraft ?? ""
            annotationDraft = document.annotationDraft ?? ""
        } else {
            let markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            noteTitle = markdown.split(separator: "\n").first(where: { $0.hasPrefix("# ") }).map { String($0.dropFirst(2)) }
                ?? url.deletingPathExtension().lastPathComponent
            steps = []
            stepAnnotations = [:]
            organizedDraft = ""
            organizedGraph = nil
            organizedTemplate = .bulletList
            organizedVariants = [:]
            rawDraft = markdown
            annotationDraft = ""
        }
    }

    private func sidecarURL(for noteURL: URL) -> URL {
        noteDataDirectory.appendingPathComponent(noteURL.deletingPathExtension().lastPathComponent + ".json")
    }

    private func title(for url: URL) -> String {
        if let data = try? Data(contentsOf: sidecarURL(for: url)),
           let document = try? JSONDecoder().decode(StoredNoteDocument.self, from: data) {
            return document.title
        }
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let heading = text.split(separator: "\n").first(where: { $0.hasPrefix("# ") }) {
            return String(heading.dropFirst(2))
        }
        return url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "Meeting_Note_", with: "Meeting note ")
            .replacingOccurrences(of: "Raw_Note_", with: "Captured note ")
    }

    private static func isLocalWhisperVariant(_ value: String) -> Bool {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty
            && !normalized.contains("whisper-1")
            && !normalized.contains("/")
            && !normalized.contains("http")
    }

    // MARK: - Settings

    func saveSettings() {
        settings.save(to: settingsURL)
        audioClient = AudioClient(config: settings.audio)
        visionClient = VisionClient(config: settings.vision)
        if settings.audio.provider == .local {
            Task { await whisperTranscriber.ensureReady(variant: settings.audio.modelName) }
        }
    }

    func checkVisionStatus() {
        if settings.vision.provider == .gemini {
            visionStatus = settings.vision.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Gemini selected — API key required"
                : "Gemini ready — model \(settings.vision.modelName)"
            return
        }
        guard settings.vision.provider == .local, let url = URL(string: settings.vision.apiURL) else {
            visionStatus = settings.vision.provider == .api ? "Using cloud API" : "Invalid URL"
            return
        }
        visionStatus = "Checking…"
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/api/tags"
        components?.query = nil
        guard let statusURL = components?.url else {
            visionStatus = "Invalid Ollama URL"
            return
        }
        var request = URLRequest(url: statusURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            Task { @MainActor in
                if error != nil || (response as? HTTPURLResponse)?.statusCode != 200 {
                    self?.visionStatus = "Ollama unreachable at \(url.host ?? url.absoluteString)"
                } else {
                    self?.visionStatus = "Ollama reachable — model \(self?.settings.vision.modelName ?? "")"
                }
            }
        }.resume()
    }

    // MARK: - History

    func refreshHistory() {
        let files = (try? FileManager.default.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        historyFiles = files
            .filter { $0.pathExtension == "md" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l > r
            }
    }
}
