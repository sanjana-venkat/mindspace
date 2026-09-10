import SwiftUI
import AppKit
import NotefyCore

/// What a right-click on a capture opens: the capture stays lit, the rest of
/// the note dims behind it, and the actions float alongside as the app's own
/// pill buttons rather than a system menu.
struct AuroraCaptureTarget: Identifiable, Equatable {
    let step: ExplorationStep
    let point: CGPoint
    var id: UUID { step.id }
    static func == (a: AuroraCaptureTarget, b: AuroraCaptureTarget) -> Bool { a.step.id == b.step.id }
}

// MARK: - right-click detection

/// A transparent AppKit layer that only answers to the right mouse button, so
/// left clicks still reach the SwiftUI card underneath.
private final class RightClickView: NSView {
    var onClick: ((CGPoint) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return super.hitTest(point)
        default:
            return nil
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        onClick?(CGPoint(x: local.x, y: bounds.height - local.y))
    }
}

private struct RightClickCatcher: NSViewRepresentable {
    var onClick: (CGPoint) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = RightClickView()
        v.onClick = onClick
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? RightClickView)?.onClick = onClick
    }
}

extension View {
    /// Reports right-clicks in the coordinates of the named space.
    func auroraRightClick(in space: String, perform: @escaping (CGPoint) -> Void) -> some View {
        overlay(
            GeometryReader { geo in
                RightClickCatcher { local in
                    let origin = geo.frame(in: .named(space)).origin
                    perform(CGPoint(x: origin.x + local.x, y: origin.y + local.y))
                }
            }
        )
    }
}

// MARK: - the floating actions

struct AuroraCaptureActions: View {
    let target: AuroraCaptureTarget
    let bounds: CGSize
    var onClose: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var picking: Bool? = nil   // nil = actions, true = forward, false = copy

    private let panelWidth: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let keep = picking {
                destinations(keep: !keep)
            } else {
                actions
            }
        }
        .frame(width: panelWidth, alignment: .leading)
        .position(x: clampedX, y: clampedY)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            pill("FORWARD", "arrowshape.turn.up.right") { picking = true }
            pill("COPY TO NOTE", "doc.on.doc") { picking = false }
            pill("COPY TO CLIPBOARD", "doc.on.clipboard") { copyToClipboard() }
            pill("DELETE", "trash") {
                appState.selectedStepIDs = [target.step.id]
                appState.deleteSelectedSteps()
                onClose()
            }
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let text = target.step.selectedText ?? target.step.pageText
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pasteboard.setString(text, forType: .string)
        } else if let path = target.step.screenshotPath,
                  let image = NSImage(contentsOfFile: path) {
            pasteboard.writeObjects([image])
        } else if let url = target.step.url {
            pasteboard.setString(url, forType: .string)
        }
        onClose()
    }

    @ViewBuilder
    private func destinations(keep: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { picking = nil } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                Text(keep ? "COPY TO" : "FORWARD TO")
                    .font(Aurora.mono(10)).tracking(1.2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Aurora.ink2)
            .padding(.horizontal, 14).padding(.vertical, 10)

            Rectangle().fill(Aurora.line).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(appState.workspace.folders) { folder in
                        rows(in: folder.id, label: folder.name, keep: keep)
                    }
                    rows(in: nil, label: "Unfiled", keep: keep)
                }
                .padding(6)
            }
            .frame(maxHeight: 260)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Aurora.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 30, y: 14)
    }

    @ViewBuilder
    private func rows(in folder: UUID?, label: String, keep: Bool) -> some View {
        let notes = appState.notes(inFolder: folder).filter { $0.url != appState.activeNoteURL }
        if !notes.isEmpty {
            Text(label.uppercased())
                .font(Aurora.mono(9)).tracking(1.1)
                .foregroundStyle(Aurora.ink3)
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 3)
            ForEach(notes) { note in
                Button {
                    appState.selectedStepIDs = [target.step.id]
                    appState.relocateSelectedSteps(to: note, keepInCurrent: keep)
                    onClose()
                } label: {
                    Text(note.title)
                        .font(Aurora.ui(13, .medium))
                        .foregroundStyle(Aurora.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AuroraHoverRow())
            }
        }
    }

    private func pill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(Aurora.mono(10.5)).tracking(1.1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Aurora.ground)
            .padding(.horizontal, 15).padding(.vertical, 10)
            .frame(width: 224, alignment: .leading)
            .background(Aurora.ink, in: Capsule())
            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        }
        .buttonStyle(AuroraPressStyle())
    }

    // keep the panel on screen
    private var clampedX: CGFloat {
        min(max(target.point.x + panelWidth / 2 + 16, panelWidth / 2 + 20), bounds.width - panelWidth / 2 - 20)
    }
    private var clampedY: CGFloat {
        let half: CGFloat = picking == nil ? 90 : 160
        return min(max(target.point.y, half + 30), bounds.height - half - 20)
    }
}

struct AuroraPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - notes

/// Right-click on a note card: file it somewhere else, or delete it. Same
/// floating pills as a capture, for the same reason — a system menu lands on
/// the aurora like a different app.
struct AuroraNoteTarget: Identifiable, Equatable {
    let url: URL
    let title: String
    let point: CGPoint
    var id: URL { url }
    static func == (a: AuroraNoteTarget, b: AuroraNoteTarget) -> Bool { a.url == b.url }
}

struct AuroraNoteActions: View {
    let target: AuroraNoteTarget
    let bounds: CGSize
    var onClose: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var moving = false
    @State private var confirmingDelete = false

    private let panelWidth: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if moving {
                folders
            } else {
                pill("MOVE TO", "folder") { moving = true }
                pill(confirmingDelete ? "DELETE — SURE?" : "DELETE NOTE", "trash") {
                    if confirmingDelete {
                        appState.deleteNote(target.url)
                        onClose()
                    } else {
                        confirmingDelete = true
                    }
                }
            }
        }
        .frame(width: panelWidth, alignment: .leading)
        .position(x: clampedX, y: clampedY)
    }

    private var folders: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { moving = false } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                Text("MOVE TO").font(Aurora.mono(10)).tracking(1.2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Aurora.ink2)
            .padding(.horizontal, 14).padding(.vertical, 10)

            Rectangle().fill(Aurora.line).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    row(title: "Unfiled", folder: nil)
                    ForEach(appState.workspace.folders) { folder in
                        row(title: folder.name, folder: folder.id)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 260)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Aurora.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 30, y: 14)
    }

    @ViewBuilder
    private func row(title: String, folder: UUID?) -> some View {
        let current = appState.folderID(for: target.url)
        Button {
            appState.moveNote(target.url, toFolder: folder)
            onClose()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(current == folder ? 1 : 0)
                Text(title).font(Aurora.ui(13, .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Aurora.ink)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(AuroraHoverRow())
    }

    private func pill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(Aurora.mono(10.5)).tracking(1.1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Aurora.ground)
            .padding(.horizontal, 15).padding(.vertical, 10)
            .frame(width: 178, alignment: .leading)
            .background(Aurora.ink, in: Capsule())
            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        }
        .buttonStyle(AuroraPressStyle())
    }

    private var clampedX: CGFloat {
        min(max(target.point.x + panelWidth / 2 + 16, panelWidth / 2 + 20), bounds.width - panelWidth / 2 - 20)
    }
    private var clampedY: CGFloat {
        let half: CGFloat = moving ? 160 : 70
        return min(max(target.point.y, half + 30), bounds.height - half - 20)
    }
}
