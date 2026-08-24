import SwiftUI
import NotefyCore

struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Button {
                appState.toggleCaptureRail()
            } label: {
                HStack {
                    NotedMark(tint: NotefyTheme.ink, knockout: NotefyTheme.sand).frame(width: 23, height: 20)
                    Text("SHOW KAMI CAPTURE RAIL").font(NotefyFont.label).tracking(0.9)
                    Spacer()
                    Text("⌘⇧K").font(NotefyFont.caption).foregroundStyle(NotefyTheme.inkFaint)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(NotefyTheme.cardPaper, in: Capsule())
            }
            .buttonStyle(.plain)

            statusRow

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    NotefyPillButton(title: "Selected Text", systemImage: "text.quote", tint: NotefyTheme.ink, filled: false) {
                        appState.captureSelectedText()
                    }
                    NotefyPillButton(title: "Page", systemImage: "macwindow", tint: NotefyTheme.ink, filled: false) {
                        appState.captureActivePage()
                    }
                }

                HStack(spacing: 8) {
                    NotefyPillButton(title: "Region", systemImage: "viewfinder", tint: NotefyTheme.ink, filled: false) {
                        appState.captureSelectedRegion()
                    }
                    NotefyPillButton(
                        title: (appState.isRecording && !appState.recordingPurposeIsMeetingNote) ? "Add Timestamp" : "Computer Audio",
                        systemImage: (appState.isRecording && !appState.recordingPurposeIsMeetingNote) ? "pause.circle.fill" : "waveform",
                        tint: NotefyTheme.ink,
                        filled: appState.isRecording && !appState.recordingPurposeIsMeetingNote
                    ) { appState.toggleSessionVoiceNote() }
                    .disabled(appState.isRecording && appState.recordingPurposeIsMeetingNote)
                }

                NotefyPillButton(
                    title: (appState.isRecording && appState.recordingPurposeIsMeetingNote) ? "Stop Meeting Note" : "Record Meeting Note",
                    systemImage: (appState.isRecording && appState.recordingPurposeIsMeetingNote) ? "stop.circle.fill" : "person.2.wave.2",
                    tint: (appState.isRecording && appState.recordingPurposeIsMeetingNote) ? .red : NotefyTheme.gold,
                    filled: appState.isRecording && appState.recordingPurposeIsMeetingNote
                ) { appState.toggleMeetingNote() }
                .disabled(appState.isRecording && !appState.recordingPurposeIsMeetingNote)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(modelStateColor)
                    .frame(width: 6, height: 6)
                Text(appState.audioModelState.label)
                    .font(NotefyFont.caption)
                    .foregroundStyle(NotefyTheme.textSecondary)
            }

            if let recordingStatus = appState.recordingStatus {
                Text(recordingStatus)
                    .font(NotefyFont.caption)
                    .foregroundStyle(NotefyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.isRecording {
                DualAudioSourceMeters(
                    microphoneDB: appState.microphonePowerDB,
                    systemDB: appState.systemAudioPowerDB,
                    microphoneActive: appState.microphoneSourceActive,
                    systemActive: appState.systemAudioSourceActive
                )
            }

            if !appState.steps.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECENT ACTIVITY")
                        .font(NotefyFont.caption.weight(.bold))
                        .foregroundStyle(NotefyTheme.textSecondary)
                    ForEach(appState.steps.prefix(3)) { step in
                        CompactStepRow(step: step)
                    }
                }
            }

            Divider()

            Text("⌘⇧K rail • T text • P page • G region • A audio • M meeting")
                .font(NotefyFont.caption)
                .foregroundStyle(NotefyTheme.textSecondary)

            HStack {
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open Noted", systemImage: "sidebar.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(NotefyTheme.ink)

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .foregroundStyle(NotefyTheme.textSecondary)
            }
            .font(NotefyFont.caption.weight(.semibold))
        }
        .padding(16)
        .frame(width: 280)
        .background(NotefyTheme.surface(scheme))
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                PebbleShape().fill(NotefyTheme.pebbleTan.opacity(0.75))
                NotedMark(tint: NotefyTheme.ink, knockout: NotefyTheme.sand).frame(width: 28, height: 25)
            }
            .frame(width: 42, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("noted")
                    .font(NotefyFont.wordmark)
                Text("the intangible, made tangible")
                    .font(NotefyFont.caption)
                    .foregroundStyle(NotefyTheme.textSecondary)
            }
            Spacer()
        }
    }

    private var statusRow: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(NotefyFont.caption.weight(.medium))
                .foregroundStyle(NotefyTheme.textSecondary)
            Spacer()
            if appState.isTracking {
                Text("\(appState.steps.count) captured")
                    .font(NotefyFont.caption)
                    .foregroundStyle(NotefyTheme.textSecondary)
            }
        }
    }

    private var statusColor: Color {
        if !appState.isTracking { return .gray }
        return appState.isPaused ? NotefyTheme.gold : .green
    }

    private var statusText: String {
        if !appState.isTracking { return "Idle" }
        return appState.isPaused ? "Paused" : "Ready"
    }

    private var modelStateColor: Color {
        switch appState.audioModelState {
        case .ready: return .green
        case .downloading, .loadingModel, .transcribing: return NotefyTheme.gold
        case .failed: return .red
        case .notDownloaded: return .gray
        }
    }
}

struct CompactStepRow: View {
    let step: ExplorationStep
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName(for: step.appName))
                .font(.system(size: 12))
                .foregroundStyle(NotefyTheme.ink)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.appName)
                    .font(NotefyFont.caption.weight(.semibold))
                Text(step.windowTitle)
                    .font(NotefyFont.caption)
                    .foregroundStyle(NotefyTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private func iconName(for appName: String) -> String {
        switch appName {
        case "Google Chrome": return "globe"
        case "Notefy Voice": return "waveform"
        default: return "app.dashed"
        }
    }
}
