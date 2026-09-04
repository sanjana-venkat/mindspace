import SwiftUI
import NotefyCore

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.ground) private var ground
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false
    @AppStorage(GroundStorage.key) private var groundRaw = GroundMode.ink.rawValue
    @AppStorage(GroundSurface.storageKey) private var surfaceRaw = GroundSurface.paper.rawValue

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("THE WORKBENCH")
                        .font(StoneFont.label()).tracking(1.3)
                        .foregroundStyle(ground.onGround42)
                    Text("Settings")
                        .font(StoneFont.title())
                        .foregroundStyle(ground.onGround)
                }
                groundSection
                surfaceSection
                permissionSection
                providerSection(
                    title: "Voice Transcription",
                    icon: "waveform",
                    provider: $appState.settings.audio.provider,
                    apiURL: $appState.settings.audio.apiURL,
                    apiKey: $appState.settings.audio.apiKey,
                    modelName: $appState.settings.audio.modelName,
                    localHint: "WhisperKit — downloads the chosen Whisper model once, then transcribes fully on-device.",
                    modelNamePlaceholder: "tiny / base / small / medium"
                ) {
                    audioModelStatus
                }

                providerSection(
                    title: "Screen Understanding",
                    icon: "eye",
                    provider: $appState.settings.vision.provider,
                    apiURL: $appState.settings.vision.apiURL,
                    apiKey: $appState.settings.vision.apiKey,
                    modelName: $appState.settings.vision.modelName,
                    localHint: "Local Ollama endpoint — run `ollama pull \(appState.settings.vision.modelName)` and keep Ollama running.",
                    modelNamePlaceholder: "qwen2-vl"
                ) {
                    visionModelStatus
                }

                HStack {
                    NotefyPillButton(title: "Save Settings", systemImage: "checkmark") {
                        appState.saveSettings()
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                    }
                    .fixedSize()

                    if saved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(StoneFont.markMedium())
                    }
                }

                Text("Settings are stored at \(appState.settingsURL.path)")
                    .font(StoneFont.mark())
                    .foregroundStyle(ground.onGround72)
                }
                .padding(24)
                .padding(.top, 34)
            }
            .scrollIndicators(.visible)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Stoneink.surfaceSlip, in: Circle())
                    .overlay(Circle().stroke(Stoneink.textPrimary.opacity(0.14)))
                    .shadow(color: Stoneink.textPrimary.opacity(0.10), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close settings")
            .padding(18)
        }
        .background(Color.clear)
        .onAppear { appState.checkVisionStatus() }
    }

    /// The one control for `data-ground`. It lives here rather than on the
    /// canvas because the canvas layout is frozen — and because this is a
    /// surface choice made once, not a control you reach for while working.
    /// Ink is the default, and neither mode follows the system appearance.
    private var groundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GROUND")
                .font(StoneFont.markMedium())
                .tracking(Stoneink.trMark * 11)
                .foregroundStyle(ground.onGround42)

            HStack(spacing: 3) {
                ForEach(GroundMode.allCases) { mode in
                    let active = mode.rawValue == groundRaw
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { groundRaw = mode.rawValue }
                    } label: {
                        Text(mode.label)
                            .font(StoneFont.bodyMedium())
                            .foregroundStyle(active ? Stoneink.clay050 : Stoneink.textSecondary)
                            .padding(.horizontal, 18)
                            .frame(height: 30)
                            .background {
                                if active { Capsule().fill(Stoneink.cobalt600) }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Stoneink.surfacePress, in: Capsule())
            .fixedSize()

            Text("Same object, different light. The panels stay paper either way — only the ground swaps.")
                .font(StoneFont.body())
                .foregroundStyle(ground.onGround72)
        }
    }

    /// Paper or glass. Paper is the default and the product's original
    /// thesis — the one opaque object on a screen full of glass. Glass
    /// inverts the ground only: the sheet goes translucent over your
    /// desktop, the captures on it stay opaque paper.
    private var surfaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SURFACE")
                .font(StoneFont.markMedium())
                .tracking(Stoneink.trMark * 11)
                .foregroundStyle(ground.onGround42)

            HStack(spacing: 3) {
                ForEach(GroundSurface.allCases) { option in
                    let active = option.rawValue == surfaceRaw
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { surfaceRaw = option.rawValue }
                    } label: {
                        Text(option.label)
                            .font(StoneFont.bodyMedium())
                            .foregroundStyle(active ? Stoneink.clay050 : Stoneink.textSecondary)
                            .padding(.horizontal, 18)
                            .frame(height: 30)
                            .background { if active { Capsule().fill(Stoneink.cobalt600) } }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Stoneink.surfacePress, in: Capsule())
            .fixedSize()

            Text("Glass makes the window a frosted sheet over your desktop. Your captures stay opaque paper on top of it.")
                .font(StoneFont.body())
                .foregroundStyle(ground.onGround72)
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Mac Permissions", systemImage: "checkmark.shield")
                .font(StoneFont.subhead())
            HStack(spacing: 10) {
                permissionBadge("MICROPHONE", granted: appState.permissionCenter.snapshot.microphone)
                permissionBadge("ACCESSIBILITY", granted: appState.permissionCenter.snapshot.accessibility)
                permissionBadge("SCREEN & AUDIO", granted: appState.permissionCenter.snapshot.screenRecording)
                Spacer()
                Button("REVIEW PERMISSIONS") { appState.showPermissionOnboarding() }
                    .buttonStyle(.plain)
                    .font(StoneFont.label()).tracking(0.8)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .overlay(Capsule().stroke(Stoneink.textPrimary.opacity(0.65), lineWidth: 1.2))
            }
        }
        .padding(16)
        .background(Stoneink.surfaceSlip)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { appState.permissionCenter.refresh() }
    }

    private func permissionBadge(_ title: String, granted: Bool) -> some View {
        Label(title, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(StoneFont.mark()).tracking(0.5)
            .foregroundStyle(granted ? Stoneink.textPrimary : Stoneink.oxide600)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background((granted ? Stoneink.celadon600 : Stoneink.oxide600).opacity(0.55), in: Capsule())
    }

    private var audioModelStatus: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(audioStateColor)
                    .frame(width: 8, height: 8)
                Text(appState.audioModelState.label)
                    .font(StoneFont.markMedium())
                if case .downloading(let progress) = appState.audioModelState {
                    ProgressView(value: progress).frame(width: 120)
                }
                Spacer()
                if appState.settings.audio.provider == .local {
                    NotefyPillButton(title: "Prepare Model", systemImage: "arrow.down.circle", tint: Stoneink.textPrimary, filled: false) {
                        Task { await appState.whisperTranscriber.ensureReady(variant: appState.settings.audio.modelName) }
                    }
                    .fixedSize()
                }
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MEETING MICROPHONE")
                        .font(StoneFont.label()).tracking(1.1)
                    Text("Recorded as “You”. Computer audio is captured separately as “Others”.")
                        .font(StoneFont.mark())
                        .foregroundStyle(Stoneink.textSecondary)
                }
                Spacer()
                Picker("Microphone", selection: $appState.settings.audio.inputDeviceUID) {
                    Text("System Default").tag(nil as String?)
                    ForEach(appState.audioInputDevices) { device in
                        Text(device.name + (device.isSystemDefault ? " (Default)" : ""))
                            .tag(Optional(device.uid))
                    }
                }
                .labelsHidden()
                .frame(width: 260)
                Button { appState.refreshAudioInputDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh microphones")
            }
        }
    }

    private var audioStateColor: Color {
        switch appState.audioModelState {
        case .ready: return .green
        case .downloading, .loadingModel, .transcribing: return Stoneink.amber600
        case .failed: return .red
        case .notDownloaded: return .gray
        }
    }

    private var visionModelStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.visionStatus.contains("reachable") ? .green : .gray)
                .frame(width: 8, height: 8)
            Text(appState.visionStatus)
                .font(StoneFont.markMedium())
            Spacer()
            if appState.settings.vision.provider == .local {
                NotefyPillButton(title: "Check Status", systemImage: "arrow.clockwise", tint: Stoneink.textPrimary, filled: false) {
                    appState.checkVisionStatus()
                }
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func providerSection<Footer: View>(
        title: String,
        icon: String,
        provider: Binding<ModelProvider>,
        apiURL: Binding<String>,
        apiKey: Binding<String>,
        modelName: Binding<String>,
        localHint: String,
        modelNamePlaceholder: String,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(StoneFont.subhead())

            LabeledContent("Provider") {
                Picker("", selection: provider) {
                    ForEach(ModelProvider.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
            }

            switch provider.wrappedValue {
            case .local:
                Text(localHint)
                    .font(StoneFont.mark())
                    .foregroundStyle(Stoneink.textSecondary)
                LabeledContent("Model") {
                    TextField(modelNamePlaceholder, text: modelName)
                        .textFieldStyle(.roundedBorder)
                }
            case .api:
                LabeledContent("API URL") {
                    TextField("https://...", text: apiURL)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("API Key") {
                    SecureField("sk-...", text: apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Model") {
                    TextField(modelNamePlaceholder, text: modelName)
                        .textFieldStyle(.roundedBorder)
                }
            case .gemini:
                Text("Uses Google's Gemini API for both transcription and note synthesis — one key covers everything.")
                    .font(StoneFont.mark())
                    .foregroundStyle(Stoneink.textSecondary)
                LabeledContent("Gemini API Key") {
                    SecureField("AIza...", text: apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Model") {
                    Picker("", selection: modelName) {
                        Text("gemini-2.5-flash").tag("gemini-2.5-flash")
                        Text("gemini-2.5-pro").tag("gemini-2.5-pro")
                        Text("gemini-2.0-flash").tag("gemini-2.0-flash")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
            }

            Divider()
            footer()
        }
        .padding(16)
        .background(Stoneink.surfaceSlip)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
