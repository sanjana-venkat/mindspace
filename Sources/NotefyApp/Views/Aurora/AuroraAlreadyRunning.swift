import SwiftUI
import AppKit

/// Shown instead of the app when another copy already holds the notes folder.
///
/// It says which copy, and since when, because the whole trap is that the other
/// one is invisible: a build you opened days ago and forgot, still running, still
/// writing. Being told "already running" without being told *what* is running
/// leaves you force-quitting at random.
struct AuroraAlreadyRunning: View {
    let holder: StoreLock.Holder?
    let directory: URL?

    private var since: String {
        guard let holder else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(holder.since)
            ? "'today at' HH:mm"
            : "'on' d MMM 'at' HH:mm"
        return formatter.string(from: holder.since)
    }

    var body: some View {
        ZStack {
            Aurora.ground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text("Mindspace is already open")
                    .font(Aurora.serif(22, .semibold))
                    .foregroundStyle(Aurora.ink)

                Text(explanation)
                    .font(Aurora.ui(13.5, .regular))
                    .foregroundStyle(Aurora.ink2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let directory {
                    Text(directory.path)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Aurora.ink3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.top, 2)
                }

                HStack(spacing: 10) {
                    Spacer()

                    if holder?.path.hasSuffix(".app") == true {
                        Button {
                            StoreLock.shared.revealHolder()
                            NSApp.terminate(nil)
                        } label: {
                            Text("Show me that one")
                                .font(Aurora.ui(13, .medium))
                                .foregroundStyle(Aurora.ink)
                                .padding(.horizontal, 18).padding(.vertical, 9)
                                .contentShape(Capsule())
                                .overlay(Capsule().strokeBorder(Aurora.ink.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(AuroraTapDown())
                    }

                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Text("Quit")
                            .font(Aurora.ui(13, .semibold))
                            .foregroundStyle(Aurora.onSolid)
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Aurora.solid, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(AuroraTapDown())
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
            .padding(24)
            .frame(width: 470, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Aurora.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Aurora.line, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 34, y: 14)
            }
            .padding(30)
        }
        .frame(minWidth: 530, minHeight: 300)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var explanation: String {
        guard let holder else {
            return """
            Another copy of Mindspace is using your notes folder. Two copies writing \
            the same folder overwrite each other's work, so this one has not opened \
            anything and nothing has been changed.
            """
        }
        return """
        \(holder.appName) has been using your notes folder since \(since). Two copies \
        writing the same folder overwrite each other's work, so this one has not opened \
        anything and nothing has been changed.
        """
    }
}
