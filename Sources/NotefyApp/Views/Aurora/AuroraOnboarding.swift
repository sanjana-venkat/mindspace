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

    @Environment(\.colorScheme) private var scheme

    @State private var step = 0
    @State private var highlighted: NotedPermission = .screenRecording
    @State private var listeningFor: HotkeyAction?
    @State private var bindingsTick = 0
    @State private var capturesAtStart: Int?
    @StateObject private var meter = AuroraMicMeter()

    private var dark: Bool { scheme == .dark }
    private var fg: Color { dark ? .white : Aurora.ink }
    private var fgSoft: Color { dark ? .white.opacity(0.74) : Aurora.ink2 }
    private var fgFaint: Color { dark ? .white.opacity(0.5) : Aurora.ink3 }
    private var panelFill: Color { dark ? .white.opacity(0.07) : Color.white.opacity(0.7) }
    private var panelStroke: Color { dark ? .white.opacity(0.16) : Aurora.line }
    private var solidFill: Color { dark ? .white : Aurora.ink }
    private var solidText: Color { dark ? .black : Aurora.ground }
    private var good: Color { dark ? Color(red: 0.45, green: 0.90, blue: 0.68) : Aurora.accent }

    private var snapshot: NotedPermissionSnapshot { appState.permissionCenter.snapshot }
    private var canLeavePermissions: Bool { snapshot.screenRecording }
    private var lastStep: Int { 5 }

    private var capturedSomething: Bool {
        guard let capturesAtStart else { return false }
        return appState.steps.count > capturesAtStart
    }

    var body: some View {
        ZStack {
            backdrop
            VStack(alignment: .leading, spacing: 0) {
                progress
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permissions
                    case 2: microphone
                    case 3: model
                    case 4: shortcuts
                    default: tryIt
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(step)
                .transition(.opacity)
                controls
            }
            .padding(40)
            .frame(maxWidth: 980)
        }
        .onAppear { appState.permissionCenter.startPolling() }
        .onDisappear {
            appState.permissionCenter.stopPolling()
            appState.onboardingCaptureUnlocked = false
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if dark {
            AuroraNight(seed: 2).opacity(0.92).ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.42), .black.opacity(0.22)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        } else {
            AuroraGround()
            AuroraNight(seed: 2, onLight: true)
                .opacity(0.9)
                .ignoresSafeArea()
            // A pale veil so the type still has something quiet to sit on.
            LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.06)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    // MARK: chrome

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(0...lastStep, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? fg.opacity(0.9) : fg.opacity(0.22))
                    .frame(width: i == step ? 34 : 16, height: 4)
            }
            Spacer()
        }
        .padding(.bottom, 30)
        .animation(.smooth(duration: 0.3), value: step)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            if step > 0 {
                Button("Back") { withAnimation(.smooth(duration: 0.3)) { step -= 1 } }
                    .buttonStyle(.plain)
                    .font(Aurora.ui(13))
                    .foregroundStyle(fgSoft)
            }
            Spacer()
            if step == 1, !canLeavePermissions {
                Text("Screen recording is the one Mindspace can't work without.")
                    .font(Aurora.ui(12, .medium)).foregroundStyle(fgFaint)
            }
            if step == lastStep, !capturedSomething {
                Button("Skip for now") { finish() }
                    .buttonStyle(.plain)
                    .font(Aurora.ui(13))
                    .foregroundStyle(fgFaint)
            }
            Button {
                if step >= lastStep { finish() } else { withAnimation(.smooth(duration: 0.3)) { step += 1 } }
            } label: {
                Text(step >= lastStep ? "Open Mindspace" : "Continue")
                    .font(Aurora.ui(14, .bold))
                    .foregroundStyle(solidText)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(solidFill, in: Capsule())
            }
            .buttonStyle(AuroraPressStyle())
            .disabled(step == 1 && !canLeavePermissions)
            .opacity(step == 1 && !canLeavePermissions ? 0.45 : 1)
        }
        .padding(.top, 26)
    }

    private func finish() {
        appState.saveSettings()
        appState.permissionCenter.markComplete()
        onFinish()
    }

    // MARK: 0 — what this is

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            Text("OPENHUMAN")
                .font(Aurora.mono(10)).tracking(3)
                .foregroundStyle(fgFaint)

            Text("Everything you want to remember, in one place.")
                .font(Aurora.display(34))
                .foregroundStyle(fg)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
                .fixedSize(horizontal: false, vertical: true)

            Text("Capture your screen, save text, record thoughts and meetings, then come back to any of it later.")
                .font(Aurora.serif(17))
                .foregroundStyle(fgSoft)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)

            AuroraDemoLoop(dark: dark)
                .frame(width: 500, height: 300)
                .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 1 — permissions

    private var permissions: some View {
        HStack(alignment: .top, spacing: 34) {
            VStack(alignment: .leading, spacing: 14) {
                Text("What you let in")
                    .font(Aurora.display(30)).foregroundStyle(fg)
                Text("Three switches, granted once. What you keep stays on this Mac. Nothing is sent anywhere unless you point Mindspace at a cloud model yourself.")
                    .font(Aurora.ui(13, .regular)).foregroundStyle(fgSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340, alignment: .leading)

                ForEach(NotedPermission.allCases) { permission in
                    permissionRow(permission)
                }
            }
            .frame(width: 380, alignment: .leading)

            AuroraSettingsMap(permission: highlighted, dark: dark)
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func permissionRow(_ permission: NotedPermission) -> some View {
        let granted = snapshot.isGranted(permission)
        return Button {
            withAnimation(.smooth(duration: 0.25)) { highlighted = permission }
            if granted { return }
            appState.permissionCenter.request(permission)
            appState.permissionCenter.openSettings(for: permission)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: granted ? "checkmark.circle.fill" : permission.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(granted ? good : fgSoft)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(permission.title).font(Aurora.ui(14, .bold)).foregroundStyle(fg)
                    Text(permission.explanation)
                        .font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text(granted ? "ON" : "GRANT")
                    .font(Aurora.mono(9.5)).tracking(1)
                    .foregroundStyle(granted ? fgFaint : solidText)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(granted ? AnyShapeStyle(panelFill) : AnyShapeStyle(solidFill), in: Capsule())
            }
            .padding(14)
            .background(highlighted == permission ? panelFill : panelFill.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(highlighted == permission ? panelStroke : panelStroke.opacity(0.6), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(AuroraPressStyle())
    }

    // MARK: 2 — voice

    private var microphone: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Think out loud")
                .font(Aurora.display(30)).foregroundStyle(fg)
            Text("Half of what you think never survives being typed. Say something now: the bars should move. If they do not, pick a different input.")
                .font(Aurora.ui(13, .regular)).foregroundStyle(fgSoft)
                .frame(maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

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

            VStack(alignment: .leading, spacing: 7) {
                Text("INPUT").font(Aurora.mono(9.5)).tracking(1.1).foregroundStyle(fgFaint)
                Picker("", selection: $appState.settings.audio.inputDeviceUID) {
                    Text("System default").tag(nil as String?)
                    ForEach(appState.audioInputDevices) { device in
                        Text(device.name).tag(device.uid as String?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(fg)
                .frame(maxWidth: 320, alignment: .leading)
            }

            Text("Your voice is transcribed on this Mac by default. Nothing is uploaded unless you choose a cloud provider in Settings.")
                .font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { appState.refreshAudioInputDevices(); meter.start() }
        .onDisappear { meter.stop() }
    }

    // MARK: 3 — the model

    private var model: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Help, on your terms")
                .font(Aurora.display(30)).foregroundStyle(fg)
            Text("What you keep, and what you thought about it, is yours and stays here. When you ask for an organized version, a model reads it and writes it up, with every line pointing back at where it came from. Choose who does that, or keep it entirely on-device.")
                .font(Aurora.ui(13, .regular)).foregroundStyle(fgSoft)
                .frame(maxWidth: 600, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

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

            switch appState.settings.vision.provider {
            case .local:
                field("Model", ModelProvider.local.defaultVisionModel, text: $appState.settings.vision.modelName)
                Text("Runs against Ollama on this Mac — install it, run `ollama pull \(appState.settings.vision.modelName)`, and leave it running. Slower than a hosted model, and nothing leaves the machine.")
                    .font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560, alignment: .leading)
            case .anthropic:
                secure("Claude API key", "sk-ant-…", text: $appState.settings.vision.apiKey)
                Text("Claude writes the organized note. Voice stays on-device. Key from \(ModelProvider.anthropic.keyURL).")
                    .font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
            case .gemini:
                secure("Gemini API key", "AIza…", text: $appState.settings.vision.apiKey)
                Text("One key covers transcription and the organized note. Key from \(ModelProvider.gemini.keyURL).")
                    .font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
            case .api:
                field("API URL", "https://…", text: $appState.settings.vision.apiURL)
                secure("API key", "sk-…", text: $appState.settings.vision.apiKey)
                field("Model", "gpt-4o", text: $appState.settings.vision.modelName)
            }

            if needsKeyWarning {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.88, green: 0.68, blue: 0.25))
                    Text("No key yet — that's fine. Mindspace falls back to the on-device model, which is slower and rougher. You can add a key any time.")
                        .font(Aurora.ui(12, .regular)).foregroundStyle(fgSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(panelStroke, lineWidth: 1))
            }

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
            .padding(.top, 4)
        }
        .frame(maxWidth: 640, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 18) {
            Text("The keys you'll press")
                .font(Aurora.display(30)).foregroundStyle(fg)
            Text("Every shortcut is ⌘⇧ and a letter. These are the defaults — click one and press a different letter if it clashes with something you already use.")
                .font(Aurora.ui(13, .regular)).foregroundStyle(fgSoft)
                .frame(maxWidth: 580, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(HotkeyAction.allCases) { action in
                    shortcutRow(action)
                }
            }
            .id(bindingsTick)

            Button("Reset to defaults") {
                HotkeyBindings.resetAll()
                bindingsTick += 1
                appState.reloadHotkeys()
            }
            .buttonStyle(.plain)
            .font(Aurora.ui(12))
            .foregroundStyle(fgFaint)
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private func shortcutRow(_ action: HotkeyAction) -> some View {
        let listening = listeningFor == action
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title).font(Aurora.ui(13.5, .semibold)).foregroundStyle(fg)
                Text(action.detail).font(Aurora.ui(11.5, .regular)).foregroundStyle(fgFaint)
            }
            Spacer(minLength: 8)
            Button {
                listeningFor = listening ? nil : action
            } label: {
                Text(listening ? "press a letter" : HotkeyBindings.label(for: action))
                    .font(Aurora.mono(12))
                    .foregroundStyle(listening ? solidText : fg)
                    .frame(minWidth: 92)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(listening ? AnyShapeStyle(solidFill) : AnyShapeStyle(panelFill), in: Capsule())
                    .overlay(Capsule().strokeBorder(listening ? .clear : panelStroke, lineWidth: 1))
            }
            .buttonStyle(AuroraPressStyle())
            .focusable(listening)
            .onKeyPress(phases: .down) { press in
                guard listening else { return .ignored }
                let letter = String(press.characters).uppercased()
                guard letter.count == 1, HotkeyBindings.keyCode(for: letter) != nil else { return .handled }
                HotkeyBindings.set(letter, for: action)
                appState.reloadHotkeys()
                listeningFor = nil
                bindingsTick += 1
                return .handled
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(panelFill.opacity(listening ? 1 : 0.6),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(panelStroke.opacity(listening ? 1 : 0.6), lineWidth: 1))
    }

    // MARK: 5 — your first one

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(capturedSomething ? "That's the whole loop" : "Try one now")
                .font(Aurora.display(30)).foregroundStyle(fg)

            if capturedSomething {
                Text("It's in your first note, with whatever you wrote beside it. Open Mindspace and it'll be waiting — read it in Panels, or ask for an organized version once there's more in there.")
                    .font(Aurora.ui(13.5, .regular)).foregroundStyle(fgSoft)
                    .frame(maxWidth: 600, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

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
                Text("Press \(HotkeyBindings.label(for: .captureRail)) and grab anything on your screen — this window counts. Write a line about why you kept it, hit Keep, and you'll land in Mindspace with something already in it.")
                    .font(Aurora.ui(13.5, .regular)).foregroundStyle(fgSoft)
                    .frame(maxWidth: 600, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Text(HotkeyBindings.label(for: .captureRail))
                        .font(Aurora.mono(15))
                        .foregroundStyle(solidText)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(solidFill, in: Capsule())
                    Text("or")
                        .font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
                    Button { appState.showCapturePet() } label: {
                        Text("Open the capture rail")
                            .font(Aurora.ui(13))
                            .foregroundStyle(fg)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(panelFill, in: Capsule())
                            .overlay(Capsule().strokeBorder(panelStroke, lineWidth: 1))
                    }
                    .buttonStyle(AuroraPressStyle())
                }

                Text("Waiting for your first capture…")
                    .font(Aurora.ui(12, .regular)).foregroundStyle(fgFaint)
            }
        }
        .onAppear {
            appState.onboardingCaptureUnlocked = true
            if capturesAtStart == nil { capturesAtStart = appState.steps.count }
        }
        .animation(.smooth(duration: 0.35), value: capturedSomething)
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

    private func secure(_ title: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Aurora.mono(9.5)).tracking(1.1).foregroundStyle(fgFaint)
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Aurora.ui(13, .regular))
                .foregroundStyle(fg)
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
