import SwiftUI
import NotefyCore

/// Settings in Aurora's surface: permissions, then the two model providers —
/// the one that hears you and the one that reads your screen.
struct AuroraSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false
    @AppStorage(AuroraAppearance.storageKey) private var appearanceRaw = AuroraAppearance.system.rawValue

    var body: some View {
        ZStack {
            AuroraGround()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    appearance
                    permissions
                    provider(
                        title: "Voice transcription",
                        icon: "waveform",
                        provider: $appState.settings.audio.provider,
                        apiURL: $appState.settings.audio.apiURL,
                        apiKey: $appState.settings.audio.apiKey,
                        modelName: $appState.settings.audio.modelName,
                        localHint: "WhisperKit downloads the chosen Whisper model once, then transcribes on-device.",
                        modelPlaceholder: "tiny / base / small / medium"
                    ) { audioFooter }
                    provider(
                        title: "Screen understanding",
                        icon: "eye",
                        provider: $appState.settings.vision.provider,
                        apiURL: $appState.settings.vision.apiURL,
                        apiKey: $appState.settings.vision.apiKey,
                        modelName: $appState.settings.vision.modelName,
                        localHint: "Local Ollama endpoint — run `ollama pull \(appState.settings.vision.modelName)` and keep Ollama running.",
                        modelPlaceholder: "qwen2-vl"
                    ) { visionFooter }
                    save
                }
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 36)
                .padding(.top, 34).padding(.bottom, 44)
            }
            .scrollIndicators(.never)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Aurora.ink2)
                    .frame(width: 30, height: 30)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Aurora.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings").font(Aurora.display(30)).foregroundStyle(Aurora.ink)
        }
    }

    private var appearance: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Appearance", icon: "circle.lefthalf.filled")
                HStack(spacing: 3) {
                    ForEach(AuroraAppearance.allCases) { option in
                        Button { appearanceRaw = option.rawValue } label: {
                            Text(option.label)
                                .font(Aurora.ui(12.5))
                                .foregroundStyle(appearanceRaw == option.rawValue ? Aurora.ground : Aurora.ink2)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(appearanceRaw == option.rawValue
                                            ? AnyShapeStyle(Aurora.ink) : AnyShapeStyle(Color.clear),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Aurora.surface2.opacity(0.8), in: Capsule())
                hint("System follows your Mac — including the automatic switch at sunset.")
            }
        }
    }

    // MARK: permissions

    private var permissions: some View {
        let snap = appState.permissionCenter.snapshot
        return card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Mac permissions", icon: "checkmark.shield")
                HStack(spacing: 8) {
                    badge("Microphone", snap.microphone)
                    badge("Accessibility", snap.accessibility)
                    badge("Screen & audio", snap.screenRecording)
                    Spacer(minLength: 0)
                    Button("Run setup") { dismiss(); appState.showPermissionOnboarding() }
                        .buttonStyle(.plain)
                        .font(Aurora.ui(12))
                        .foregroundStyle(Aurora.ink)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Aurora.surface2, in: Capsule())
                        .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
                }
            }
        }
    }

    private func badge(_ title: String, _ granted: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .bold))
            Text(title.uppercased()).font(Aurora.mono(9)).tracking(0.8)
        }
        .foregroundStyle(granted ? Aurora.accent : Aurora.ink3)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(granted ? Aurora.accentSoft : Aurora.surface2, in: Capsule())
    }

    // MARK: providers

    private func provider<Footer: View>(
        title: String,
        icon: String,
        provider: Binding<ModelProvider>,
        apiURL: Binding<String>,
        apiKey: Binding<String>,
        modelName: Binding<String>,
        localHint: String,
        modelPlaceholder: String,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle(title, icon: icon)

                HStack(spacing: 3) {
                    ForEach(ModelProvider.allCases, id: \.self) { option in
                        Button { switchProvider(to: option, provider: provider, apiURL: apiURL, apiKey: apiKey, modelName: modelName) } label: {
                            Text(option.displayName)
                                .font(Aurora.ui(12.5))
                                .foregroundStyle(provider.wrappedValue == option ? Aurora.ground : Aurora.ink2)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(provider.wrappedValue == option ? AnyShapeStyle(Aurora.ink) : AnyShapeStyle(Color.clear),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Aurora.surface2.opacity(0.8), in: Capsule())

                switch provider.wrappedValue {
                case .local:
                    hint(localHint)
                    field("Model", modelPlaceholder, modelName)
                case .api:
                    field("API URL", "https://…", apiURL)
                    secure("API key", "sk-…", apiKey)
                    field("Model", modelPlaceholder, modelName)
                case .anthropic:
                    hint("Claude writes the organized note. Transcription stays on-device — Anthropic has no speech-to-text endpoint.")
                    secure("Claude API key", "sk-ant-…", apiKey)
                    field("Model", "claude-sonnet-4-5", modelName)
                case .gemini:
                    hint("One Gemini key covers both transcription and note synthesis.")
                    secure("Gemini API key", "AIza…", apiKey)
                    HStack(spacing: 8) {
                        label("Model")
                        ForEach(["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"], id: \.self) { m in
                            Button { modelName.wrappedValue = m } label: {
                                Text(m.replacingOccurrences(of: "gemini-", with: ""))
                                    .font(Aurora.mono(10.5))
                                    .foregroundStyle(modelName.wrappedValue == m ? Aurora.accent : Aurora.ink3)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(modelName.wrappedValue == m ? Aurora.accentSoft : Aurora.surface2, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }

                Rectangle().fill(Aurora.line).frame(height: 1)
                footer()
            }
        }
    }

    private var audioFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(appState.audioModelState == .ready ? Aurora.accent : Aurora.ink3)
                    .frame(width: 7, height: 7)
                Text(appState.audioModelState.label)
                    .font(Aurora.ui(12, .medium)).foregroundStyle(Aurora.ink2)
                Spacer(minLength: 0)
                if case .downloading(let progress) = appState.audioModelState {
                    ProgressView(value: progress).frame(width: 110)
                }
                if appState.audioModelState != .ready, appState.settings.audio.provider == .local {
                    Button("Prepare model") {
                        Task { await appState.whisperTranscriber.ensureReady(variant: appState.settings.audio.modelName) }
                    }
                        .buttonStyle(.plain)
                        .font(Aurora.ui(12))
                        .foregroundStyle(Aurora.ink)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Aurora.surface2, in: Capsule())
                        .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                label("Meeting microphone")
                Picker("", selection: $appState.settings.audio.inputDeviceUID) {
                    Text("System default").tag(nil as String?)
                    ForEach(appState.audioInputDevices) { device in
                        Text(device.name + (device.isSystemDefault ? " (default)" : "")).tag(device.uid as String?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(Aurora.ui(12, .regular))
                .frame(maxWidth: 320, alignment: .leading)
                Text("Recorded as “You”. Computer audio is captured separately as “Others”.")
                    .font(Aurora.ui(11.5, .regular)).foregroundStyle(Aurora.ink3)
            }
        }
    }

    private var visionFooter: some View {
        HStack(spacing: 10) {
            Text(appState.visionStatus)
                .font(Aurora.ui(12, .medium)).foregroundStyle(Aurora.ink2)
            Spacer(minLength: 0)
            Button("Check status") { appState.checkVisionStatus() }
                .buttonStyle(.plain)
                .font(Aurora.ui(12))
                .foregroundStyle(Aurora.ink)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Aurora.surface2, in: Capsule())
                .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
        }
    }

    private var save: some View {
        HStack(spacing: 14) {
            Button {
                appState.saveSettings()
                saved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
            } label: {
                Text(saved ? "Saved" : "Save settings")
                    .font(Aurora.ui(14, .bold))
                    .foregroundStyle(Aurora.ground)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(saved ? Aurora.accent : Aurora.ink, in: Capsule())
            }
            .buttonStyle(.plain)
            Text(appState.settingsURL.path)
                .font(Aurora.mono(10)).foregroundStyle(Aurora.ink3).lineLimit(1).truncationMode(.middle)
        }
    }

    // MARK: bits

    /// Switching provider keeps each provider's own key, and fills in that
    /// provider's endpoint and model so a key is usually all you need.
    private func switchProvider(to option: ModelProvider,
                                provider: Binding<ModelProvider>,
                                apiURL: Binding<String>,
                                apiKey: Binding<String>,
                                modelName: Binding<String>) {
        let isAudio = provider.wrappedValue == appState.settings.audio.provider
            && apiKey.wrappedValue == appState.settings.audio.apiKey
        appState.settings.rememberKey(apiKey.wrappedValue, for: provider.wrappedValue, audio: isAudio)
        provider.wrappedValue = option
        apiKey.wrappedValue = appState.settings.key(for: option, audio: isAudio)
        if !isAudio {
            apiURL.wrappedValue = option.defaultVisionURL
            if modelName.wrappedValue.isEmpty || ModelProvider.allCases.contains(where: { $0.defaultVisionModel == modelName.wrappedValue }) {
                modelName.wrappedValue = option.defaultVisionModel
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Aurora.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Aurora.line, lineWidth: 1))
    }

    private func sectionTitle(_ text: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(Aurora.ink2)
            Text(text).font(Aurora.title(16)).foregroundStyle(Aurora.ink)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Aurora.mono(9.5)).tracking(1.1).foregroundStyle(Aurora.ink3)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(Aurora.ui(12, .regular)).foregroundStyle(Aurora.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ title: String, _ placeholder: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title)
            TextField(placeholder, text: binding)
                .textFieldStyle(.plain)
                .font(Aurora.ui(13, .regular))
                .foregroundStyle(Aurora.ink)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Aurora.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Aurora.line, lineWidth: 1))
        }
    }

    private func secure(_ title: String, _ placeholder: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title)
            SecureField(placeholder, text: binding)
                .textFieldStyle(.plain)
                .font(Aurora.ui(13, .regular))
                .foregroundStyle(Aurora.ink)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Aurora.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Aurora.line, lineWidth: 1))
        }
    }
}
