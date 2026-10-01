#if DEBUG
import SwiftUI
import AppKit
import NotefyCore

/// Draws the orbit offscreen, for checking layout without a screen.
///
/// The dock and the suggestion pills live in the workspace, not the orbit, so
/// they are drawn here as outlined boxes at the positions the workspace gives
/// them. Anything that collides with a box collides in the real window.
@MainActor
enum OrbitSnapshot {
    static let size = CGSize(width: 1180, height: 780)

    static func renderAll(into directory: String) {
        AuroraFolderPanel.drawsUnscrolled = true
        AuroraGrid.drawsUnscrolled = true
        defer { AuroraFolderPanel.drawsUnscrolled = false; AuroraGrid.drawsUnscrolled = false }
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let one = [tile("Unfiled", unfiled: true, counts: [8], tint: 2)]
        let five = [
            tile("Cognitive Psych", counts: [6, 5, 4, 3], tint: 0),
            tile("Research Methods", counts: [5, 4], tint: 1),
            tile("Readings", counts: [3, 2, 2], tint: 2),
            tile("Half ideas", counts: [1], tint: 3),
            tile("Unfiled", unfiled: true, counts: [2], tint: 4)
        ]
        let many = (0..<40).map { tile("Folder \($0)", counts: [1], tint: $0) }
        let hundred = (0..<100).map { tile("Course \($0)", counts: [($0 % 7) + 1], tint: $0) }

        render(one, hover: "Unfiled", to: dir.appendingPathComponent("1-one-folder.png"))
        render(five, hover: "Readings", to: dir.appendingPathComponent("2-five-folders.png"))
        render(five, hover: "Half ideas", to: dir.appendingPathComponent("3-hover-small.png"))
        render(many, hover: nil, to: dir.appendingPathComponent("4-forty-folders.png"))
        render(hundred, hover: AuroraOrbitView.overflowID, to: dir.appendingPathComponent("7-hundred-overflow.png"))
        let starters = [("Work", 3), ("Hobbies", 2), ("Learning", 0),
                        ("Reading", 1), ("Research", 4)]
            .map { tile($0.0, counts: [], tint: $0.1, chosen: true) }
        renderFaces(to: dir.appendingPathComponent("faces.png"))
        renderGridAndViewer(into: dir)
        probeHover(starters + [tile("Unfiled", unfiled: true, counts: [8], tint: 2)], into: dir)
        render(starters, hover: "Learning", to: dir.appendingPathComponent("8-new-user.png"))
        render(starters + [tile("Unfiled", unfiled: true, counts: [8], tint: 2)],
               hover: nil, to: dir.appendingPathComponent("9-you-after-seeding.png"))
        let psych = tile("Cognitive Psych", counts: [6, 5, 4, 3], tint: 0, chosen: true,
                         titles: ["Correlation is not causation", "Memory and encoding",
                                  "Seminar 9, the bits I missed", "Exam 2, likely themes"])
        render([psych] + Array(five.dropFirst()), panel: psych,
               to: dir.appendingPathComponent("10-folder-open.png"))
        render(five, listening: "what did I save about correlation",
               to: dir.appendingPathComponent("5-listening-short.png"))
        render(five, listening: "so the thing I keep coming back to is whether a correlation in my readings was ever reported as a cause and what the seminar said about it",
               to: dir.appendingPathComponent("6-listening-long.png"))
    }

    /// Walks the pointer once around the ring, a degree at a time, on the arc
    /// line and just outside the band, and writes down what it hit. Each folder
    /// should appear once, in ring order, and the band's edge should hit
    /// nothing.
    private static func probeHover(_ tiles: [AuroraFolderTile], into dir: URL) {
        let view = AuroraOrbitView(tiles: tiles, transcript: LiveTranscriptEngine(),
                                   onOpenFolder: { _ in }, onListen: {}, onStopListening: {},
                                   listening: false, onAsk: { _ in })
        let size = (116.0 + 9 + 24) * 2, c = size / 2
        var runs: [String] = []
        var outside = 0
        for deg in stride(from: 0.0, to: 360.0, by: 1.0) {
            let a = deg * .pi / 180
            let on = CGPoint(x: c + cos(a) * 116, y: c + sin(a) * 116)
            let id = view.segmentID(at: on) ?? "·gap"
            if runs.last != id { runs.append(id) }
            let off = CGPoint(x: c + cos(a) * (116 + 40), y: c + sin(a) * (116 + 40))
            if view.segmentID(at: off) != nil { outside += 1 }
        }
        let report = "on the line: " + runs.joined(separator: " → ")
            + "\nhits 40pt outside the band: \(outside)\n"
        try? report.write(to: dir.appendingPathComponent("hover-probe.txt"), atomically: true, encoding: .utf8)
    }

    /// The captures grid with a normal, a wide and a tall screenshot, and the
    /// viewer on the wide one. Fixtures come from the --fixtures directory if
    /// given; nothing here reads or writes the notes folder.
    private static func renderGridAndViewer(into dir: URL) {
        guard let i = CommandLine.arguments.firstIndex(of: "--fixtures"),
              i + 1 < CommandLine.arguments.count else { return }
        let f = CommandLine.arguments[i + 1]
        func step(_ title: String, _ file: String?) -> ExplorationStep {
            ExplorationStep(appName: "Chrome", windowTitle: title, url: "https://example.com/\(title)",
                            selectedText: file == nil ? "A text capture with no picture, to check it still sits in the grid." : nil,
                            screenshotPath: file.map { "\(f)/\($0).png" })
        }
        let steps = [step("one", "normal"), step("two", "tall"), step("three", nil),
                     step("four", "wide"), step("five", "normal"), step("six", "normal")]
        let grid = AuroraGrid(steps: steps, active: .constant(0), thought: { _ in .constant("why I kept this") },
                              onRightClick: { _, _ in }, commit: { _ in }, open: { _ in },
                              selection: .constant([]))
            .frame(width: 1180, height: 1500)
            .background(Aurora.ground)
            .environment(\.colorScheme, .dark)
        save(grid, scale: 1, to: dir.appendingPathComponent("grid.png"))

        let viewer = AuroraCaptureViewer(steps: steps, index: .constant(3), thought: { _ in "Saved because the layout here is the one I want to copy." })
            .frame(width: 1180, height: 780)
            .environment(\.colorScheme, .dark)
        save(viewer, scale: 1, to: dir.appendingPathComponent("viewer.png"))
    }

    private static func save<V: View>(_ view: V, scale: CGFloat, to url: URL) {
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: url)
        }
    }

    /// The painted original beside the three drawn faces, large, so the idle
    /// face can be checked against the art it replaces.
    private static func renderFaces(to url: URL) {
        let art = MoonPetArt.load()
        let cell: CGFloat = 300
        let view = HStack(spacing: 24) {
            VStack(spacing: 10) {
                art.idle?.resizable().scaledToFit().frame(width: cell, height: cell)
                Text("ORIGINAL ART").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            ForEach([("IDLE", MoonMood.Face.idle), ("ATTENTIVE", .attentive), ("SURPRISED", .surprised)], id: \.0) { label, face in
                VStack(spacing: 10) {
                    ZStack {
                        art.blank?.resizable().scaledToFit()
                        MoonFace(face: face)
                    }
                    .frame(width: cell, height: cell)
                    Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                }
            }
        }
        .padding(24)
        .background(Color(red: 0.06, green: 0.07, blue: 0.09))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    private static func tile(_ name: String, unfiled: Bool = false, counts: [Int], tint: Int,
                             chosen: Bool = false, titles: [String] = []) -> AuroraFolderTile {
        let notes = counts.enumerated().map { i, n in
            CanvasNoteSnapshot(url: URL(fileURLWithPath: "/tmp/\(name)-\(i).md"),
                               title: i < titles.count ? titles[i] : "\(name) \(i)",
                               excerpt: i < titles.count ? "Two lecture slides and a voice note from after the seminar." : "",
                               createdAt: Date().addingTimeInterval(-Double(i) * 86_400 * 3),
                               folderID: nil, folderName: name, captureCount: n,
                               hasOrganizedNote: false)
        }
        return AuroraFolderTile(id: name, folderID: unfiled ? nil : UUID(), name: name,
                                point: .zero, notes: notes,
                                tints: chosen ? Aurora.triad(chosen: tint) : [tint, tint + 2, tint + 4])
    }

    private static func render(_ tiles: [AuroraFolderTile], hover: String? = nil,
                               listening: String? = nil, panel: AuroraFolderTile? = nil,
                               to url: URL) {
        let transcript = LiveTranscriptEngine()
        if let listening { transcript.debugSay(listening) }

        let view = ZStack {
            Aurora.ground
            AuroraOrbitView(tiles: tiles, transcript: transcript,
                            onOpenFolder: { _ in }, onListen: {}, onStopListening: {},
                            listening: listening != nil, onAsk: { _ in },
                            focusedID: panel?.id,
                            shiftedFraction: panel == nil ? nil : AuroraFolderPanel.widthFraction,
                            previewHover: hover)
            if let panel {
                AuroraFolderPanel(tile: panel, onOpenNote: { _ in }, onClose: {}, renaming: .constant(false))
            }
            if listening == nil && panel == nil { chromeOutline }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)

        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.5
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: url)
        }
    }

    /// Where the workspace puts the dock and the pills, from its own numbers:
    /// 30 from the bottom, a 51 high bar at most 620 wide, 12 above it a row
    /// of pills about 36 high.
    private static var chromeOutline: some View {
        VStack(spacing: 12) {
            Spacer()
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.red.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .overlay(Text("PILLS").font(.system(size: 11, weight: .bold)).foregroundStyle(.red))
                .frame(width: 560, height: 36)
            Capsule()
                .strokeBorder(Color.red.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .overlay(Text("SEARCH DOCK").font(.system(size: 11, weight: .bold)).foregroundStyle(.red))
                .frame(width: 620, height: 51)
        }
        .padding(.bottom, 30)
        .allowsHitTesting(false)
    }
}
#endif
