import SwiftUI
import AppKit
import AVFoundation
import NotefyCore

/// First run. What Mindspace is, what it needs from macOS, whose model does the
/// tidying, the keys you'll actually press, and then your first capture — so
/// the app is never empty the first time you see it.
struct AuroraOnboarding: View {
    @EnvironmentObject private var appState: AppState
    var onFinish: () -> Void
    /// Where the camera should be: how far along the panorama, and how far
    /// down toward the ice. The window owns the scene; this only says where to
    /// point it.
    var onCamera: (_ pan: Double, _ tilt: Double) -> Void = { _, _ in }

    @Environment(\.colorScheme) private var scheme

    @State private var step = 0
    /// What each provider says it can run, so onboarding never offers a model
    /// name that only ever existed in this app's source.
    @State private var onboardingModels: [ModelProvider: [String]] = [:]
    @State private var highlighted: NotedPermission = .screenRecording
    @State private var listeningFor: HotkeyAction?
    @State private var bindingsTick = 0
    @State private var displaced: HotkeyAction?
    @State private var capturesAtStart: Int?
    /// Setup arrives from below as the launch sequence lifts away, so the two
    /// read as one move rather than a cut.
    @State private var entered = false
    @StateObject private var meter = AuroraMicMeter()
    @StateObject private var recorder = HotkeyRecorder()
    @AppStorage(AuroraAppearance.storageKey) private var appearanceRaw = AuroraAppearance.system.rawValue

    /// How far along the panorama setup has walked: every step slides the
    /// world sideways, past mountains, through the spruce, out onto the lake.
    private var journey: Double { Double(step) / Double(max(1, lastStep)) }

    /// And how far the camera is tipped toward the ice. Setup keeps the sky in
    /// charge; only the last step — the one that asks — tips it, so choosing
    /// light or dark is done by looking at each.
    private var cameraTilt: Double {
        guard step >= lastStep else { return 0.26 }
        switch appearanceRaw {
        case AuroraAppearance.light.rawValue: return 0.98
        case AuroraAppearance.dark.rawValue: return 0.04
        // Matching the Mac is the view with both in it — the horizon held so
        // you can see sky and ice at once. Pointing it at whatever the Mac
        // happens to be set to made this choice look identical to that one.
        default: return 0.5
        }
    }

    private var macIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    /// Type follows the camera, not the step: white while you are looking at
    /// the night, ink once the ice fills the window. Half way between the two
    /// is grey on grey, so the crossing is steep rather than linear.
    /// The copy on this screen sits low in the frame, so what matters is what
    /// is under *there*: any tilt past the horizon puts ice behind it, and ink
    /// is the legible choice from that point on.
    private var inkCrossing: Double {
        let t = max(0, min(1, (cameraTilt - 0.26) / 0.16))
        return t * t * (3 - 2 * t)
    }

    /// True while white type is still the legible one.
    private var dark: Bool { inkCrossing < 0.5 }

    private func crossing(_ night: Color, _ day: Color) -> Color {
        Aurora.blend(night, day, inkCrossing)
    }

    // Written out rather than taken from `Aurora.*`: this window is pinned to
    // the dark appearance, so every dynamic token resolves to its night value.
    // Asking for `Aurora.ink` here returns white, which is how the light half
    // of this screen ended up as white type on white ice.
    private static let dayInk = Color(red: 0.07, green: 0.09, blue: 0.12)
    private static let dayInk2 = Color(red: 0.24, green: 0.28, blue: 0.33)
    private static let dayInk3 = Color(red: 0.40, green: 0.45, blue: 0.50)
    private static let dayGood = Color(red: 0.05, green: 0.48, blue: 0.35)

    private var fg: Color { crossing(.white, Self.dayInk) }
    private var fgSoft: Color { crossing(.white.opacity(0.76), Self.dayInk2) }
    private var fgFaint: Color { crossing(.white.opacity(0.52), Self.dayInk3) }
    private var panelFill: Color { crossing(.white.opacity(0.07), Color.white.opacity(0.80)) }
    private var panelStroke: Color { crossing(.white.opacity(0.16), Color.black.opacity(0.12)) }
    private var solidFill: Color { crossing(.white, Self.dayInk) }
    private var solidText: Color { crossing(.black, .white) }
    private var good: Color { crossing(Color(red: 0.45, green: 0.90, blue: 0.68), Self.dayGood) }

    private var snapshot: NotedPermissionSnapshot { appState.permissionCenter.snapshot }
    private var canLeavePermissions: Bool { snapshot.screenRecording }
    private var lastStep: Int { 7 }

    private var capturedSomething: Bool {
        guard let capturesAtStart else { return false }
        return appState.steps.count > capturesAtStart
    }

    var body: some View {
        ZStack {
            backdrop
            VStack(alignment: .leading, spacing: 0) {
                // The last page is a choice, not a station on the way: the
                // dots would be one more thing in a view that is already full.
                Text("MINDSPACE")
                    .font(Aurora.mono(10)).tracking(3)
                    .foregroundStyle(fgFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 14)

                if step < lastStep { progress } else { Color.clear.frame(height: 4) }
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permissions
                    case 2: microphone
                    case 3: speechModelStep
                    case 4: model
                    case 5: tryIt
                    case 6: shortcuts
                    default: appearanceStep
                    }
                }
                // Every step is the same height. They were each as tall as
                // their own content, so the panel resized between them and the
                // whole page appeared to hop up or down on the way across.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // The appearance page needs enough room for three proper
                // preview cards. Other pages retain their tighter stage.
                .frame(height: step == lastStep ? 560 : 452)
                // The landscape behind is busy by design, and small type laid
                // straight onto a ridgeline cannot be read. Everything with
                // controls in it gets a sheet of frosted glass to sit on; the
                // last step keeps the open sky, since its cards run off the
                // edges of the window and a panel would fence them in.
                .padding(step < lastStep ? 26 : 0)
                .background {
                    if step < lastStep {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            // Frosted glass, the same material the app's own
                            // ground is made of: the landscape should be
                            // visible through it, not behind a dark card.
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .fill(.white.opacity(0.05)))
                            .overlay {
                                AuroraGrain.tile
                                    .resizable(resizingMode: .tile)
                                    .blendMode(.overlay)
                                    .opacity(0.12)
                                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                            }
                            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .strokeBorder(.white.opacity(0.28), lineWidth: 1))
                            .shadow(color: .black.opacity(0.20), radius: 36, y: 14)
                            .opacity(0.88)
                    }
                }
                // Anything that grows past the panel — an open dropdown, a
                // long list — is cut at its edge rather than spilling over the
                // landscape. The last step has no panel and its cards bleed on
                // purpose, so it is left alone.
                .modifier(PanelClip(active: step < lastStep))
                .id(step)
                // Content travels the way the camera does: the world slides
                // left, so the next step comes in from the right and the one
                // you just finished leaves to the left. Nothing moves upward.
                // The panel fades; the landscape behind it does the travelling.
                // Sliding the panel as well made two competing movements.
                .transition(.opacity)
                controls
            }
            .padding(.horizontal, 44)
            .padding(.top, step == lastStep ? 24 : 40)
            .padding(.bottom, step == lastStep ? 24 : 56)
            .frame(maxWidth: 980)
            .offset(y: entered ? 0 : 34)
            .opacity(entered ? 1 : 0)
        }
        .onAppear {
            guard !entered else { return }
            withAnimation(.easeOut(duration: 0.8).delay(0.35)) { entered = true }
        }
        // A key typed here is worth nothing if it never reaches disk, and the
        // vision client is rebuilt from settings on save.
        .onChange(of: appState.settings) { _, _ in appState.saveSettings() }
        .onAppear {
            appState.permissionCenter.startPolling()
            onCamera(journey, cameraTilt)
        }
        .onChange(of: step) { _, _ in onCamera(journey, cameraTilt) }
        // The last step's cards move the camera: pick light and the world tips
        // down onto the ice, pick dark and it tips back up into the sky.
        .onChange(of: appearanceRaw) { _, _ in onCamera(journey, cameraTilt) }
        .onDisappear {
            appState.permissionCenter.stopPolling()
            appState.onboardingCaptureUnlocked = false
        }
    }

    /// The sky belongs to the window now — one tall aurora the launch screen
    /// and this share — so all that is left here is the veil that keeps the
    /// type legible over it.
    /// The sky belongs to the window now — one tall aurora the launch screen
    /// and this share — so all that is left here is the veil that keeps the
    /// type legible over it. It crosses over too: a dark veil under the night,
    /// a pale one once the snow is what the type is sitting on.
    private var backdrop: some View {
        ZStack {
            // While the type is still white, the veil deepens as the scene
            // brightens — that is what keeps the early steps readable on a sky
            // that is getting lighter under them.
            LinearGradient(stops: [
                .init(color: .black.opacity(0.40), location: 0),
                .init(color: .black.opacity(0.18), location: 0.45),
                .init(color: .black.opacity(0.42), location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .opacity(1 - inkCrossing)

            // And once it has crossed, the veil is pale and the snow carries
            // the type instead.
            LinearGradient(stops: [
                .init(color: .white.opacity(0.34), location: 0),
                .init(color: .white.opacity(0.58), location: 0.55),
                .init(color: .white.opacity(0.40), location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .opacity(inkCrossing)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.9), value: cameraTilt)
    }

    // MARK: chrome

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(0...lastStep, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? fg.opacity(0.9) : fg.opacity(0.22))
                    .frame(width: i == step ? 34 : 16, height: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 30)
        .animation(.smooth(duration: 0.3), value: step)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            if step > 0 {
                Button("Back") { withAnimation(.easeInOut(duration: 0.45)) { step -= 1 } }
                    .buttonStyle(.plain)
                    .font(Aurora.ui(13))
                    .foregroundStyle(fgSoft)
            }
            Spacer()
            if step == 1, !canLeavePermissions {
                Text("Screen recording is the one Mindspace can't work without.")
                    .font(Aurora.ui(12, .medium)).foregroundStyle(fgFaint)
            }
            if step < lastStep {
            Button {
                withAnimation(.smooth(duration: 0.3)) { step += 1 }
            } label: {
                Text("Continue")
                    .font(Aurora.ui(14, .bold))
                    .foregroundStyle(solidText)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(solidFill, in: Capsule())
            }
            .buttonStyle(AuroraPressStyle())
            .disabled(step == 1 && !canLeavePermissions)
            .opacity(step == 1 && !canLeavePermissions ? 0.45 : 1)
            }
        }
        .padding(.top, 30)
    }

    private func finish() {
        appState.saveSettings()
        appState.permissionCenter.markComplete()
        onFinish()
    }

    /// Every page is the same shape: centred, sitting a little below the middle,
    /// heading then explanation then the thing you act on.
    /// Every page is built the same way: a header block of fixed height at the
    /// top, then the body centred in whatever is left. Letting each page centre
    /// itself meant a short one and a tall one put their titles at different
    /// heights, so moving between them looked like the page hopping upward.
    private func page<Content: View>(_ title: String,
                                     _ subtitle: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Text(title)
                    .font(Aurora.display(30))
                    .foregroundStyle(fg)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(Aurora.ui(13.5, .regular))
                    .foregroundStyle(fgSoft)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 124, alignment: .top)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: 0 — what this is

    private var welcome: some View {
        page("Everything you want to remember, in one place.",
             "Capture your screen, save text, record thoughts and meetings, then come back to any of it later.") {
            AuroraDemoLoop(dark: dark)
                .frame(width: 500, height: 300)
        }
    }

    // MARK: 1 — permissions, one at a time

    /// The order they're asked in: screen first because nothing works without
    /// it, then voice, then selection.
    private var permissionOrder: [NotedPermission] { [.screenRecording, .microphone, .accessibility] }

    private var currentPermission: NotedPermission {
        permissionOrder.first { !snapshot.isGranted($0) } ?? .screenRecording
    }

    private var permissions: some View {
        let permission = currentPermission
        let granted = snapshot.isGranted(permission)
        let allDone = snapshot.allGranted

        return page(allDone ? "That's all three" : permission.title,
                    allDone
                    ? "Nothing else to turn on. Everything you keep stays on this Mac unless you point Mindspace at a cloud model yourself."
                    : permission.explanation) {
            VStack(spacing: 18) {
                HStack(spacing: 7) {
                    ForEach(permissionOrder) { item in
                        Circle()
                            .fill(snapshot.isGranted(item) ? good
                                  : (item == permission ? fg.opacity(0.55) : fg.opacity(0.2)))
                            .frame(width: 7, height: 7)
                    }
                }

                if allDone {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(good)
                        Text("Screen, voice and selection are all on.")
                            .font(Aurora.ui(13.5, .semibold)).foregroundStyle(fg)
                    }
                } else {
                    AuroraSettingsMap(permission: permission, dark: dark)
                        .frame(width: 420)

                    Button {
                        appState.permissionCenter.request(permission)
                        appState.permissionCenter.openSettings(for: permission)
                    } label: {
                        Text("Open System Settings")
                            .font(Aurora.ui(14, .bold))
                            .foregroundStyle(solidText)
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .background(solidFill, in: Capsule())
                    }
                    .buttonStyle(AuroraPressStyle())

                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("Go flip the switch — this page will notice when you do.")
                            .font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
                    }
                    .opacity(granted ? 0 : 1)
                }
            }
            .animation(.smooth(duration: 0.3), value: snapshot)
        }
    }

    // MARK: 2 — voice

    private var microphone: some View {
        page("Think out loud",
             "Half of what you think never survives being typed. Say something — the bars should move. If they don't, try another input below.") {
            VStack(spacing: 20) {
                HStack(spacing: 6) {
                    ForEach(0..<24, id: \.self) { i in
                        let threshold = Double(i) / 24.0
                        Capsule()
                            .fill(meter.level > threshold ? good : fg.opacity(0.14))
                            .frame(width: 8, height: 14 + CGFloat(sin(Double(i) / 3.4) * 10 + 14))
                    }
                }
                .animation(.easeOut(duration: 0.08), value: meter.level)
                .frame(height: 46)

                HStack(spacing: 10) {
                    Image(systemName: meter.heardSomething ? "checkmark.circle.fill" : "waveform")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(meter.heardSomething ? good : fgSoft)
                    Text(meter.statusLine)
                        .font(Aurora.ui(13, .medium)).foregroundStyle(fgSoft)
                }

                AuroraSelect(
                    label: "Input",
                    options: [AuroraSelect.Option(id: nil, title: "System default")]
                        + appState.audioInputDevices.map { AuroraSelect.Option(id: $0.uid, title: $0.name) },
                    selection: $appState.settings.audio.inputDeviceUID,
                    dark: dark
                )
                .frame(width: 320)

                Text("Your voice is transcribed right here on your Mac. Nothing gets uploaded unless you pick a cloud provider in Settings.")
                    .font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { appState.refreshAudioInputDevices(); meter.start() }
        .onDisappear { meter.stop() }
    }

    // MARK: 3 — the speech model

    /// Fetched here rather than the first time someone hits record. It is
    /// 215MB: a wait nobody minds while they are setting things up, and a wait
    /// that feels broken when they have just started talking. It starts on its
    /// own — nobody came here to press a download button.
    private var speechModelStep: some View {
        page("Words, as you say them",
             "Mindspace transcribes on this Mac, so recordings never leave it. That needs a one-off 215MB model.") {
            speechModel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    guard appState.audioModelState == .notDownloaded else { return }
                    await appState.localTranscriber.ensureReady()
                }
        }
    }

    @ViewBuilder
    private var speechModel: some View {
        VStack(spacing: 14) {
            switch appState.audioModelState {
            case .downloading(let fraction):
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Fetching the speech model — \(Int(fraction * 100))%")
                            .font(Aurora.ui(12.5, .medium)).foregroundStyle(fgSoft)
                    }
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 280)
                    Text("Carry on — it finishes in the background.")
                        .font(Aurora.ui(11.5)).foregroundStyle(fgFaint)
                }
            case .loadingModel:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading the speech model…")
                        .font(Aurora.ui(12.5, .medium)).foregroundStyle(fgSoft)
                }
            case .ready:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(good)
                    Text("Speech model is on this Mac — transcription works offline.")
                        .font(Aurora.ui(12.5, .medium)).foregroundStyle(fgSoft)
                }
            case .failed(let why):
                VStack(spacing: 6) {
                    Text("Couldn't fetch the speech model: \(why)")
                        .font(Aurora.ui(12)).foregroundStyle(fgSoft)
                        .multilineTextAlignment(.center)
                    Button("Try again") { Task { await appState.localTranscriber.ensureReady() } }
                        .buttonStyle(.plain)
                        .font(Aurora.ui(12.5, .semibold))
                        .foregroundStyle(solidText)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(fg.opacity(0.9), in: Capsule())
                }
            case .notDownloaded, .transcribing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Starting the download…")
                        .font(Aurora.ui(12.5, .medium)).foregroundStyle(fgSoft)
                }
            }

            if appState.audioModelState != .ready {
                Text("You can carry on setting up — this finishes on its own. Recording before it lands just means waiting a moment then.")
                    .font(Aurora.ui(11.5)).foregroundStyle(fgFaint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 480)
        .animation(.smooth(duration: 0.25), value: appState.audioModelState)
    }

    // MARK: 3 — the model

    private var model: some View {
        page("Help, on your terms",
             "Pick who writes the tidy version — or keep it all on your Mac.") {
            VStack(spacing: 16) {
                HStack(spacing: 3) {
                    ForEach(ModelProvider.allCases, id: \.self) { option in
                        Button { selectProvider(option) } label: {
                            Text(option.displayName)
                                .font(Aurora.ui(13))
                                .foregroundStyle(appState.settings.vision.provider == option ? solidText : fgSoft)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(appState.settings.vision.provider == option
                                            ? AnyShapeStyle(solidFill) : AnyShapeStyle(Color.clear), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(panelFill, in: Capsule())

                VStack(alignment: .leading, spacing: 12) {
                    let provider = appState.settings.vision.provider
                    if provider.needsKey {
                        secure(provider.keyLabel, provider.keyPlaceholder, text: $appState.settings.vision.apiKey)
                        Text(provider.keyHint)
                            .font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // What this account or this Mac can actually run, asked of
                    // the provider. Empty until there is something to ask with.
                    let offered = onboardingModels[provider] ?? provider.visionModels

                    AuroraSelect(
                        label: "Model",
                        options: offered.map { AuroraSelect.Option(id: $0, title: $0) },
                        selection: Binding(
                            get: { appState.settings.vision.modelName },
                            set: { appState.settings.vision.modelName = $0 ?? provider.defaultVisionModel }
                        ),
                        dark: dark
                    )
                    .id(provider)
                    .task(id: "\(provider.rawValue)|\(appState.settings.vision.apiKey)") {
                        guard onboardingModels[provider] == nil else { return }
                        guard !provider.needsKey || !appState.settings.vision.apiKey.isEmpty else { return }
                        try? await Task.sleep(for: .milliseconds(800))
                        await loadOnboardingModels(for: provider)
                    }

                    if offered.isEmpty {
                        Text(provider == .local
                             ? "Nothing pulled yet — run `ollama pull qwen2.5vl:7b` and it will appear here."
                             : "Add a key above and the models this account can use will appear here.")
                            .font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if provider == .local {
                        Text("Ollama serves the model over HTTP on this Mac — install it, `ollama pull` a vision model such as `qwen2.5vl:7b`, and leave it running. Slower than a hosted model, and nothing leaves the machine.")
                            .font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if needsKeyWarning {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(red: 0.88, green: 0.68, blue: 0.25))
                            Text("No key? That's fine — Mindspace falls back to the model on your Mac. It's slower and a bit rougher, and you can add a key whenever you like.")
                                .font(Aurora.ui(12, .regular)).foregroundStyle(fgSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(panelStroke, lineWidth: 1))
                    }
                }
                .frame(width: 460)

                HStack(spacing: 12) {
                    Button {
                        appState.saveSettings()
                        appState.checkVisionStatus()
                    } label: {
                        Text("Test connection")
                            .font(Aurora.ui(13))
                            .foregroundStyle(fg)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(panelFill, in: Capsule())
                            .overlay(Capsule().strokeBorder(panelStroke, lineWidth: 1))
                    }
                    .buttonStyle(AuroraPressStyle())
                    Text(appState.visionStatus)
                        .font(Aurora.ui(12, .medium)).foregroundStyle(fgSoft)
                }
            }
        }
    }

    private func selectProvider(_ option: ModelProvider) {
        appState.settings.rememberKey(appState.settings.vision.apiKey,
                                      for: appState.settings.vision.provider)
        appState.settings.vision.provider = option
        appState.settings.vision.apiKey = appState.settings.key(for: option)
        appState.settings.vision.apiURL = option.defaultVisionURL
        appState.settings.vision.modelName = option.defaultVisionModel
        appState.visionStatus = "Not checked"
    }

    private var needsKeyWarning: Bool {
        appState.settings.vision.provider.needsKey
            && appState.settings.vision.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: 4 — the keys you'll press

    private var shortcuts: some View {
        page("The keys you'll press",
             "Click one, then type the ⌘ combination you want.") {
            VStack(spacing: 2) {
                ForEach(HotkeyAction.allCases) { action in
                    shortcutRow(action)
                }
                Button("Reset to defaults") {
                    HotkeyBindings.resetAll()
                    bindingsTick += 1
                    appState.reloadHotkeys()
                }
                .buttonStyle(.plain)
                .font(Aurora.ui(12))
                .foregroundStyle(fgFaint)
                .padding(.top, 4)
            }
            .frame(width: 560)
            .id(bindingsTick)
        }
    }

    private func shortcutRow(_ action: HotkeyAction) -> some View {
        let listening = listeningFor == action
        let clashes = appState.hotkeyConflicts.contains(action)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title).font(Aurora.ui(13.5, .semibold)).foregroundStyle(fg)
                // No description line: six of them made this page taller than
                // the window and pushed the button off the bottom.
                if clashes {
                    HStack(spacing: 8) {
                        Text("macOS is holding this one.")
                            .font(Aurora.ui(11.5, .regular))
                            .foregroundStyle(Color(red: 0.92, green: 0.74, blue: 0.36))
                        Button("Free it in Keyboard Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(Aurora.ui(11.5, .semibold))
                        .foregroundStyle(fg)
                        .underline()
                    }
                } else if displaced == action {
                    Text("Lost its shortcut to another action — press keys to give it a new one.")
                        .font(Aurora.ui(11.5, .regular))
                        .foregroundStyle(Color(red: 0.92, green: 0.74, blue: 0.36))
                }
            }
            Spacer(minLength: 8)
            Button {
                if listening {
                    recorder.stop()
                    listeningFor = nil
                } else {
                    listeningFor = action
                    recorder.start { binding in
                        displaced = HotkeyBindings.set(binding, for: action)
                        appState.reloadHotkeys()
                        listeningFor = nil
                        bindingsTick += 1
                    }
                }
            } label: {
                Text(listening ? "press keys" : HotkeyBindings.label(for: action))
                    .font(Aurora.mono(12))
                    .foregroundStyle(listening ? solidText : fg)
                    .frame(minWidth: 92)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(listening ? AnyShapeStyle(solidFill) : AnyShapeStyle(panelFill), in: Capsule())
                    .overlay(Capsule().strokeBorder(listening ? .clear : Aurora.ink.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(AuroraPressStyle())
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        // No card around each row. Six of them stacked up were mostly border
        // and inner padding, and the list ran past the bottom of the panel.
        // Only the one being recorded, or one macOS has taken, gets a shape.
        .background((listening || clashes) ? panelFill : .clear,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(panelStroke.opacity(0.5))
                .frame(height: 1)
                .padding(.horizontal, 10)
                .opacity(action == HotkeyAction.allCases.last ? 0 : 1)
        }
    }

    // MARK: 5 — your first one

    private var tryIt: some View {
        page(capturedSomething ? "Nice — that's the whole loop" : "Let's try it out",
             capturedSomething
             ? "It's saved in your first note with your thought attached. Next, pick the keys you'll use to do that from anywhere."
             : "Hit \(HotkeyBindings.label(for: .captureRail)) and grab anything on screen — this window works fine. Jot a line about why you kept it, hit Keep, and you'll land in Mindspace with something already in it.") {
            VStack(spacing: 16) {
                if capturedSomething {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(good)
                        Text("\(appState.steps.count) capture\(appState.steps.count == 1 ? "" : "s") in “\(appState.noteTitle)”")
                            .font(Aurora.ui(14, .semibold)).foregroundStyle(fg)
                    }
                    .padding(16)
                    .background(panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(panelStroke, lineWidth: 1))
                } else {
                    HStack(spacing: 14) {
                        Text(HotkeyBindings.label(for: .captureRail))
                            .font(Aurora.mono(15))
                            .foregroundStyle(solidText)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(solidFill, in: Capsule())
                        Text("or").font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
                        Button { appState.showCapturePet() } label: {
                            Text("Open the moon pet for me")
                                .font(Aurora.ui(13))
                                .foregroundStyle(fg)
                                .padding(.horizontal, 16).padding(.vertical, 11)
                                .background(panelFill, in: Capsule())
                                .overlay(Capsule().strokeBorder(panelStroke, lineWidth: 1))
                        }
                        .buttonStyle(AuroraPressStyle())
                    }
                    Text("Waiting for your first one…")
                        .font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
                }
            }
        }
        .onAppear {
            appState.onboardingCaptureUnlocked = true
            if capturesAtStart == nil { capturesAtStart = appState.steps.count }
        }
        .animation(.smooth(duration: 0.35), value: capturedSomething)
    }


    // MARK: appearance

    /// Setup runs dark whatever the Mac is doing, so this last step is the
    /// first time the choice is theirs. The swatches are drawn from fixed
    /// colours rather than the environment — you have to see the other one to
    /// pick it.
    private var appearanceStep: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last thing — how should it look?")
                    .font(Aurora.display(28))
                    .foregroundStyle(fg)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Try them. Light tips the world down onto the ice; dark takes it back up into the sky. Either way you can flip it any time with the moon in the bottom-right corner.")
                    .font(Aurora.serif(16))
                    .foregroundStyle(fgSoft)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: finish) {
                    Text("Open Mindspace")
                        .font(Aurora.ui(14, .bold))
                        .foregroundStyle(solidText)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(solidFill, in: Capsule())
                }
                .buttonStyle(AuroraPressStyle())
                .padding(.top, 8)
            }
            .frame(width: 380, alignment: .leading)
            // Low in the frame on purpose: below the horizon is ice at every
            // tilt that matters, which is what keeps this readable.
            .offset(y: 54)

            Spacer(minLength: 24)

            // Dark on top, the Mac's own setting in the middle, light at the
            // bottom — the same axis the camera moves on. The ends run off the
            // window, because they are places you can go rather than a row of
            // options to compare.
            // Taller than the window on purpose: dark runs off the top and
            // light off the bottom, so they read as somewhere to go rather
            // than three options in a row. Hung in an overlay so the overflow
            // costs the layout nothing — otherwise it pushes the buttons off
            // the bottom of the window with it.
            // All three in view, none of them cut: they are a choice, and a
            // choice you can only half see is a worse one.
            VStack(spacing: 14) {
                appearanceCard(.dark)
                appearanceCard(.system)
                appearanceCard(.light)
            }
            .frame(width: 330)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func appearanceCard(_ option: AuroraAppearance) -> some View {
        let chosen = appearanceRaw == option.rawValue
        return Button {
            withAnimation(.smooth(duration: 0.3)) { appearanceRaw = option.rawValue }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                appearanceSwatch(option)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(option == .system ? "Match my Mac" : option.label)
                        .font(Aurora.ui(16, .bold))
                        .foregroundStyle(fg)
                    Text(blurb(option))
                        .font(Aurora.ui(12, .medium))
                        .foregroundStyle(fgFaint)
                        .lineLimit(1)
                }
                .frame(height: 40, alignment: .top)
                .padding(.bottom, 4)
            }
            .padding(14)
            .padding(.bottom, 8)
            // All three the same, with enough breathing room below the blurb.
            .frame(height: 200)
            // Selection must not remove the glass underneath the copy. On the
            // light preview that exposed the mountain artwork directly behind
            // dark text; keep the translucent sheet and tint it instead.
            .background(panelFill,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                if chosen {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(good.opacity(0.07))
                }
            }
            // No radio: the tile is the control, and its border is the answer.
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(chosen ? good : panelStroke, lineWidth: chosen ? 2.4 : 1))
            // The words are part of the button, not scenery beside it: a click
            // anywhere on the tile picks it.
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(chosen ? 0.22 : 0), radius: 22, y: 10)
        }
        .buttonStyle(AuroraPressStyle())
    }

    private func blurb(_ option: AuroraAppearance) -> String {
        switch option {
        case .dark: return "The night sky. Where it was drawn."
        case .system: return macIsDark ? "Your Mac is dark right now." : "Your Mac is light right now."
        case .light: return "Ice and snow, for a bright desk."
        }
    }

    /// A doll's-house Mindspace: ground, an aurora over a folder, a line of
    /// type. Enough to tell the two apart at a glance.
    /// The preview is the world itself at that tilt: dark looks up into the
    /// sky, light looks down onto the ice, and matching the Mac holds the
    /// horizon where you can see both.
    private func appearanceSwatch(_ option: AuroraAppearance) -> some View {
        Group {
            if option == .system {
                GeometryReader { geo in
                    ZStack {
                        AuroraSceneThumbnail(tilt: 0.04)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: geo.size.width / 2)
                            }
                        AuroraSceneThumbnail(tilt: 0.98)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .mask(alignment: .trailing) {
                                Rectangle().frame(width: geo.size.width / 2)
                            }
                    }
                }
            } else {
                AuroraSceneThumbnail(tilt: tiltPreview(option))
            }
        }
    }

    private func tiltPreview(_ option: AuroraAppearance) -> Double {
        switch option {
        case .dark: return 0.04
        case .light: return 0.98
        case .system: return 0.52
        }
    }

    // MARK: fields

    private func field(_ title: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Aurora.mono(9.5)).tracking(1.1).foregroundStyle(fgFaint)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Aurora.ui(13, .regular))
                .foregroundStyle(fg)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(panelStroke, lineWidth: 1))
        }
    }

    @MainActor
    private func loadOnboardingModels(for provider: ModelProvider) async {
        let key = appState.settings.vision.apiKey
        var found: [String] = []
        switch provider {
        case .local:
            found = await ProviderCatalog.ollamaModels(endpoint: appState.settings.vision.apiURL)
        case .api:
            found = await ProviderCatalog.openAIModels(apiKey: key)
        case .gemini:
            found = await withCheckedContinuation { continuation in
                GeminiClient.availableModels(apiKey: key) { result in
                    continuation.resume(returning: (try? result.get()) ?? [])
                }
            }
        case .anthropic:
            found = await ProviderCatalog.anthropicModels(apiKey: key)
        }
        onboardingModels[provider] = found
        if !found.isEmpty,
           appState.settings.vision.provider == provider,
           !found.contains(appState.settings.vision.modelName) {
            appState.settings.vision.modelName = AuroraSettingsView.pick(from: found)
        }
    }

    private func secure(_ title: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Aurora.mono(9.5)).tracking(1.1).foregroundStyle(fgFaint)
            // AppKit's own field: the SwiftUI one never took the keyboard here,
            // so this step asked for a key it gave you no way to enter.
            AuroraKeyField(text: text,
                           placeholder: placeholder,
                           textColor: dark ? .white : NSColor(Self.dayInk),
                           focusOnAppear: true)
                .frame(height: 20)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(panelStroke, lineWidth: 1))
        }
    }
}

/// A drawn map of the System Settings pane the permission lives in, with the
/// row you need pulsing. Not a screenshot — it stays right when Apple moves
/// things around, and it can point at the exact switch.
struct AuroraSettingsMap: View {
    let permission: NotedPermission
    var dark: Bool = true
    @State private var pulse = false

    private var fg: Color { dark ? .white : Aurora.ink }
    private var chrome: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05) }
    private var body_: Color { dark ? Color.black.opacity(0.35) : Color.white.opacity(0.72) }

    private var paneTitle: String {
        switch permission {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen & System Audio Recording"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                // window chrome
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(.white.opacity(0.25)).frame(width: 7, height: 7)
                    }
                    Spacer()
                    Text("Privacy & Security")
                        .font(Aurora.ui(11, .semibold)).foregroundStyle(fg.opacity(0.6))
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(chrome)

                VStack(alignment: .leading, spacing: 0) {
                    Text(paneTitle)
                        .font(Aurora.ui(13, .bold)).foregroundStyle(fg.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

                    row(name: "Another app", on: false, highlight: false)
                    row(name: "Mindspace", on: true, highlight: true)
                    row(name: "Some other app", on: false, highlight: false)
                }
                .padding(.bottom, 14)
            }
            .background(body_)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(fg.opacity(0.16), lineWidth: 1))

            HStack(spacing: 9) {
                Image(systemName: "arrow.turn.left.up")
                    .font(.system(size: 11, weight: .bold))
                Text(permission == .accessibility
                     ? "Add Mindspace with +, then switch it on. macOS may ask you to quit and reopen."
                     : "Find Mindspace in the list and turn the switch on.")
                    .font(Aurora.ui(12, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(dark ? .black : Aurora.ground)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(dark ? AnyShapeStyle(Color.white) : AnyShapeStyle(Aurora.ink),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .scaleEffect(pulse ? 1 : 0.985)
            .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
            .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: pulse)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .onAppear { pulse = true }
    }

    private func row(name: String, on: Bool, highlight: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(fg.opacity(highlight ? 0.75 : 0.2))
                .frame(width: 18, height: 18)
            Text(name)
                .font(Aurora.ui(12.5, highlight ? .bold : .regular))
                .foregroundStyle(fg.opacity(highlight ? 0.95 : 0.45))
            Spacer()
            ZStack {
                Capsule()
                    .fill(on ? Color(red: 0.35, green: 0.78, blue: 0.55) : fg.opacity(0.18))
                    .frame(width: 34, height: 20)
                Circle().fill(.white).frame(width: 16, height: 16)
                    .offset(x: on ? 7 : -7)
            }
            .overlay {
                if highlight {
                    Capsule()
                        .strokeBorder(fg.opacity(0.9), lineWidth: 2)
                        .frame(width: 46, height: 32)
                        .scaleEffect(pulse ? 1.12 : 0.94)
                        .opacity(pulse ? 0 : 0.9)
                        .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(highlight ? fg.opacity(0.1) : .clear)
    }
}


/// Reads the input level straight off AVAudioEngine — no recording, nothing
/// written to disk, just enough to prove the microphone works.
@MainActor
final class AuroraMicMeter: ObservableObject {
    @Published var level: Double = 0
    @Published var heardSomething = false

    private let engine = AVAudioEngine()
    private var running = false

    var statusLine: String {
        if heardSomething { return "Microphone is working." }
        return running ? "Listening…" : "Microphone not started."
    }

    func start() {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Float = 0
            for i in 0..<frames { sum += channel[i] * channel[i] }
            let rms = sqrtf(sum / Float(frames))
            let db = 20 * log10f(max(rms, 0.000_001))
            let normalised = min(1, max(0, (Double(db) + 52) / 46))
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.level = normalised
                if normalised > 0.28 { self.heardSomething = true }
            }
        }
        do {
            try engine.start()
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        level = 0
    }
}


/// The sideways slide each step arrives and leaves on.
struct StepShift: ViewModifier {
    let x: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.offset(x: x).opacity(opacity)
    }
}


/// Clips a step's content to its panel — but only for the steps that have one.
/// Clipping with a zero radius still clips, which cut the corner off the last
/// step's cards.
struct PanelClip: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        } else {
            content
        }
    }
}
