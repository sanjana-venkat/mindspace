import SwiftUI
import NotefyCore

/// Settings in Aurora's surface: permissions, then the two model providers —
/// the one that hears you and the one that reads your screen.
struct AuroraSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false
    /// What each provider can actually run, asked of the provider itself
    /// rather than hardcoded — model names get retired.
    @State private var liveModels: [ModelProvider: [String]] = [:]
    @State private var loadingProvider: ModelProvider?
    @State private var modelListProblem: [ModelProvider: String] = [:]
    @AppStorage(AuroraAppearance.storageKey) private var appearanceRaw = AuroraAppearance.system.rawValue
    @Environment(\.colorScheme) private var scheme

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
                        localHint: "Parakeet runs on-device — the same model writes the live transcript and the finished one. It downloads once, about 215MB.",
                        modelPlaceholder: "parakeet",
                        localRunsOllama: false,
                        hostedNote: "A hosted provider only writes the finished transcript, when you stop. The live transcript you watch while recording is always Parakeet on this Mac — it downloads once, about 215MB, whichever provider is set here."
                    ) { audioFooter }
                    provider(
                        title: "Screen understanding",
                        icon: "eye",
                        provider: $appState.settings.vision.provider,
                        apiURL: $appState.settings.vision.apiURL,
                        apiKey: $appState.settings.vision.apiKey,
                        modelName: $appState.settings.vision.modelName,
                        localHint: "Ollama serves the model over HTTP on this Mac — install it, `ollama pull` a vision model such as `qwen2.5vl:7b`, and leave it running. Endpoint is where Mindspace asks for it; the default is Ollama's own address.",
                        modelPlaceholder: "qwen2.5vl:7b",
                        localRunsOllama: true
                    ) { visionFooter }
                    save
                }
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 36)
                .padding(.top, 34).padding(.bottom, 44)
            }
            .scrollIndicators(.never)

            EmptyView()
                .onChange(of: appState.settings) { _, _ in appState.saveSettings() }

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
        /// On-device means Ollama for screen understanding and Parakeet for
        /// speech. Only the first has a model to choose or an address to reach.
        localRunsOllama: Bool,
        /// Said when a hosted provider is chosen — what it will and won't do.
        hostedNote: String? = nil,
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

                let current = provider.wrappedValue
                if current.needsKey {
                    secure(current.keyLabel, current.keyPlaceholder, apiKey)
                    hint(current.keyHint)
                }

                // Providers retire model names on their own schedule, so the
                // list comes from the provider rather than from whatever was
                // true when this app was built.
                let live = liveModels[current] ?? []
                let offered = live.isEmpty ? current.visionModels : live

                // Speech on-device is Parakeet and nothing else — no model to
                // pick, no address to reach.
                if current != .local || localRunsOllama {
                    AuroraSelect(
                        label: "Model",
                        options: offered.map { AuroraSelect.Option(id: $0, title: $0) },
                        selection: Binding(
                            get: { modelName.wrappedValue },
                            set: { modelName.wrappedValue = $0 ?? current.defaultVisionModel }
                        ),
                        dark: scheme == .dark
                    )
                    // Switching provider rebuilds the picker, so it cannot be
                    // left hanging open over a list that no longer applies.
                    .id(current)

                    if offered.isEmpty {
                        hint(current == .local
                             ? "Nothing pulled yet — run `ollama pull qwen2.5vl:7b`, then refresh."
                             : (apiKey.wrappedValue.isEmpty
                                ? "Add a key to load the models this account can use."
                                : "Refresh to load the models this key can use."))
                    }
                }

                // Refreshing needs something to ask with: a key for the hosted
                // three, a running Ollama for the local one.
                let canRefresh = current == .local ? localRunsOllama : !apiKey.wrappedValue.isEmpty
                if canRefresh {
                    HStack(spacing: 10) {
                        Button(loadingProvider == current ? "Checking…" : refreshLabel(for: current)) {
                            Task { await loadModels(for: current, key: apiKey.wrappedValue, endpoint: apiURL.wrappedValue) }
                        }
                        .buttonStyle(.plain)
                        .font(Aurora.ui(12, .medium))
                        .foregroundStyle(Aurora.accent)
                        .contentShape(Rectangle())
                        .disabled(loadingProvider != nil)

                        // Each provider keeps its own answer: one failing to
                        // list its models said nothing about the others.
                        if let problem = modelListProblem[current] {
                            Text(problem).font(Aurora.ui(11.5)).foregroundStyle(Aurora.warning)
                        } else if !live.isEmpty {
                            Text(current == .local
                                 ? "\(live.count) pulled locally"
                                 : "\(live.count) models this key can use")
                                .font(Aurora.ui(11.5)).foregroundStyle(Aurora.ink3)
                        }
                        Spacer(minLength: 0)
                    }
                    .task(id: "\(current.rawValue)|\(apiKey.wrappedValue)") {
                        guard liveModels[current] == nil else { return }
                        guard !current.needsKey || !apiKey.wrappedValue.isEmpty else { return }
                        // A key is typed or pasted a character at a time; wait
                        // for it to settle before asking the provider about it.
                        try? await Task.sleep(for: .milliseconds(800))
                        await loadModels(for: current, key: apiKey.wrappedValue, endpoint: apiURL.wrappedValue)
                    }
                }

                if current.showsEndpointField && localRunsOllama {
                    field("Endpoint", "http://localhost:11434/api/chat", apiURL)
                }
                if current == .local {
                    hint(localHint)
                } else if let hostedNote {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "waveform.badge.exclamationmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Aurora.warning)
                        Text(hostedNote)
                            .font(Aurora.ui(11.5))
                            .foregroundStyle(Aurora.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Aurora.surface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Aurora.warning.opacity(0.3), lineWidth: 1))
                }

                Rectangle().fill(Aurora.line).frame(height: 1)
                footer()
            }
        }
    }

    private func refreshLabel(for provider: ModelProvider) -> String {
        provider == .local ? "Refresh pulled models" : "Refresh model list"
    }

    /// Asks the provider what it can run, so the picker stays honest through
    /// model retirements without shipping a new build. Each provider is asked
    /// with its own key and keeps its own answer.
    @MainActor
    private func loadModels(for provider: ModelProvider, key: String, endpoint: String) async {
        guard loadingProvider == nil else { return }
        loadingProvider = provider
        modelListProblem[provider] = nil

        var found: [String] = []
        switch provider {
        case .local:
            found = await ProviderCatalog.ollamaModels(endpoint: endpoint)
            if found.isEmpty { modelListProblem[provider] = "Ollama isn't answering on that endpoint." }
        case .api:
            found = await ProviderCatalog.openAIModels(apiKey: key)
            if found.isEmpty { modelListProblem[provider] = "OpenAI didn't return a model list for that key." }
        case .anthropic:
            found = await ProviderCatalog.anthropicModels(apiKey: key)
            if found.isEmpty { modelListProblem[provider] = "Anthropic didn't return a model list for that key." }
        case .gemini:
            let result: Result<[String], Error> = await withCheckedContinuation { continuation in
                GeminiClient.availableModels(apiKey: key) { continuation.resume(returning: $0) }
            }
            switch result {
            case .success(let models): found = models
            case .failure(let error):
                modelListProblem[provider] = (error as? GeminiFailure)?.summary ?? error.localizedDescription
            }
        }

        loadingProvider = nil
        liveModels[provider] = found
        guard !found.isEmpty, provider != .local else { return }
        // The saved model may no longer exist — move to the closest thing this
        // provider still has rather than failing on the next note.
        let saved = appState.settings.vision.modelName
        if appState.settings.vision.provider == provider, saved.isEmpty || !found.contains(saved) {
            appState.settings.vision.modelName = Self.pick(from: found)
            appState.saveSettings()
        }
    }

    /// A sensible default out of whatever a provider offers: the everyday
    /// model rather than whatever happens to sort first.
    static func pick(from models: [String]) -> String {
        let preferred = ["flash", "gpt", "sonnet", "claude"]
        for hint in preferred {
            if let match = models.first(where: { $0.lowercased().contains(hint) }) { return match }
        }
        return models[0]
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
                        Task { await appState.localTranscriber.ensureReady() }
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
