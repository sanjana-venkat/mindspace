import SwiftUI
import AppKit
import AVFoundation
import NotefyCore

/// First run: what Noted needs from macOS, and which model writes the organized
/// note. Each permission comes with a drawn map of the System Settings pane it
/// lives in, so nobody has to hunt for the toggle.
struct AuroraOnboarding: View {
    @EnvironmentObject private var appState: AppState
    var onFinish: () -> Void

    @State private var step = 0
    @State private var highlighted: NotedPermission = .screenRecording
    @StateObject private var meter = AuroraMicMeter()

    private var snapshot: NotedPermissionSnapshot { appState.permissionCenter.snapshot }
    private var canLeavePermissions: Bool { snapshot.screenRecording }

    var body: some View {
        ZStack {
            AuroraNight(seed: 2).opacity(0.9).ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.25)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                progress
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permissions
                    case 2: microphone
                    case 3: model
                    default: ready
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(step)
                .transition(.opacity)
                controls
            }
            .padding(40)
            .frame(maxWidth: 940)
        }
        .onAppear { appState.permissionCenter.startPolling() }
        .onDisappear { appState.permissionCenter.stopPolling() }
    }

    // MARK: chrome

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.white.opacity(0.9) : Color.white.opacity(0.22))
                    .frame(width: i == step ? 34 : 16, height: 4)
            }
            Spacer()
        }
        .padding(.bottom, 34)
        .animation(.smooth(duration: 0.3), value: step)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            if step > 0 {
                Button("Back") { withAnimation(.smooth(duration: 0.3)) { step -= 1 } }
                    .buttonStyle(.plain)
                    .font(Aurora.ui(13))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            if step == 1, !canLeavePermissions {
                Text("Screen recording is required to capture anything.")
                    .font(Aurora.ui(12, .medium)).foregroundStyle(.white.opacity(0.55))
            }
            Button {
                if step >= 4 {
                    appState.saveSettings()
                    appState.permissionCenter.markComplete()
                    onFinish()
                } else {
                    withAnimation(.smooth(duration: 0.3)) { step += 1 }
                }
            } label: {
                Text(step >= 4 ? "Start capturing" : "Continue")
                    .font(Aurora.ui(14, .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(AuroraPressStyle())
            .disabled(step == 1 && !canLeavePermissions)
            .opacity(step == 1 && !canLeavePermissions ? 0.45 : 1)
        }
        .padding(.top, 30)
    }

    // MARK: steps

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)

            VStack(spacing: 16) {
                Text("OPENHUMAN")
                    .font(Aurora.mono(10)).tracking(3)
                    .foregroundStyle(.white.opacity(0.45))
                Text("Mindspace")
                    .font(Aurora.display(62))
                    .foregroundStyle(.white)
                Text("A record of your own thinking. In your words, on your machine, for as long as you want it.")
                    .font(Aurora.serif(20))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineSpacing(7)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 34)

            HStack(alignment: .top, spacing: 14) {
                move("Keep it", "square.dashed",
                     "Anything in front of you: a window, a passage, something you said out loud. Held with the moment it mattered.")
                move("Say why", "text.quote",
                     "Write the thought you had when you saved it. A model can summarise the page. Only you have this part.")
                move("Come back", "arrow.counterclockwise",
                     "Walk back through what you were thinking last week, or the year you first learned it. Plain files that outlive the app.")
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func move(_ title: String, _ icon: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.55, green: 0.92, blue: 0.74))
            Text(title)
                .font(Aurora.ui(15, .bold)).foregroundStyle(.white)
            Text(body)
                .font(Aurora.ui(13, .regular))
                .foregroundStyle(.white.opacity(0.62))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: 262, minHeight: 196, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }

    private func bullet(_ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(.white.opacity(0.6)).frame(width: 5, height: 5).padding(.top, 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Aurora.ui(14, .bold)).foregroundStyle(.white)
                Text(body).font(Aurora.ui(13, .regular)).foregroundStyle(.white.opacity(0.65))
            }
        }
    }

    private var permissions: some View {
        HStack(alignment: .top, spacing: 34) {
            VStack(alignment: .leading, spacing: 14) {
                Text("What you let in")
                    .font(Aurora.display(30)).foregroundStyle(.white)
                Text("Three switches, granted once. What you keep stays on this Mac. Nothing is sent anywhere unless you point Mindspace at a cloud model yourself.")
                    .font(Aurora.ui(13, .regular)).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340, alignment: .leading)

                ForEach(NotedPermission.allCases) { permission in
                    permissionRow(permission)
                }
            }
            .frame(width: 380, alignment: .leading)

            AuroraSettingsMap(permission: highlighted)
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
                    .foregroundStyle(granted ? Color(red: 0.45, green: 0.87, blue: 0.66) : .white.opacity(0.8))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(permission.title).font(Aurora.ui(14, .bold)).foregroundStyle(.white)
                    Text(permission.explanation)
                        .font(Aurora.ui(12, .regular)).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text(granted ? "ON" : "GRANT")
                    .font(Aurora.mono(9.5)).tracking(1)
                    .foregroundStyle(granted ? .white.opacity(0.5) : .black)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(granted ? AnyShapeStyle(Color.white.opacity(0.14)) : AnyShapeStyle(Color.white),
                                in: Capsule())
            }
            .padding(14)
            .background(highlighted == permission ? Color.white.opacity(0.12) : Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(highlighted == permission ? .white.opacity(0.35) : .white.opacity(0.12), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(AuroraPressStyle())
    }

    /// A live level meter, so nobody finds out their input device is wrong
    /// halfway through their first meeting.
    private var microphone: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Think out loud")
                .font(Aurora.display(30)).foregroundStyle(.white)
            Text("Half of what you think never survives being typed. Say something now: the bars should move. If they do not, pick a different input.")
                .font(Aurora.ui(13, .regular)).foregroundStyle(.white.opacity(0.65))

            HStack(spacing: 6) {
                ForEach(0..<24, id: \.self) { i in
                    let threshold = Double(i) / 24.0
                    Capsule()
                        .fill(meter.level > threshold
                              ? Color(red: 0.45, green: 0.90, blue: 0.68)
                              : Color.white.opacity(0.14))
                        .frame(width: 8, height: 14 + CGFloat(sin(Double(i) / 3.4) * 10 + 14))
                }
            }
            .animation(.easeOut(duration: 0.08), value: meter.level)
            .frame(height: 46)

            HStack(spacing: 10) {
                Image(systemName: meter.heardSomething ? "checkmark.circle.fill" : "waveform")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(meter.heardSomething
                                     ? Color(red: 0.45, green: 0.90, blue: 0.68) : .white.opacity(0.6))
                Text(meter.statusLine)
                    .font(Aurora.ui(13, .medium)).foregroundStyle(.white.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("INPUT").font(Aurora.mono(9.5)).tracking(1.1).foregroundStyle(.white.opacity(0.5))
                Picker("", selection: $appState.settings.audio.inputDeviceUID) {
                    Text("System default").tag(nil as String?)
                    ForEach(appState.audioInputDevices) { device in
                        Text(device.name).tag(device.uid as String?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 320, alignment: .leading)
            }

            Text("Your voice is transcribed on this Mac by default. Nothing is uploaded unless you choose a cloud provider in Settings.")
                .font(Aurora.ui(12, .regular)).foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { appState.refreshAudioInputDevices(); meter.start() }
        .onDisappear { meter.stop() }
    }

    private var model: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Help, on your terms")
                .font(Aurora.display(30)).foregroundStyle(.white)
            Text("What you keep, and what you thought about it, is yours and stays here. When you ask for an organized version, a model reads it and writes it up, with every line pointing back at where it came from. Choose who does that, or keep it entirely on-device.")
                .font(Aurora.ui(13, .regular)).foregroundStyle(.white.opacity(0.65))
                .frame(maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 3) {
                ForEach(ModelProvider.allCases, id: \.self) { option in
                    Button { appState.settings.vision.provider = option } label: {
                        Text(option.displayName)
                            .font(Aurora.ui(13))
                            .foregroundStyle(appState.settings.vision.provider == option ? .black : .white.opacity(0.75))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(appState.settings.vision.provider == option
                                        ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.clear), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.white.opacity(0.1), in: Capsule())

            switch appState.settings.vision.provider {
            case .local:
                field("Model", "qwen2-vl", text: $appState.settings.vision.modelName)
                Text("Runs against your local Ollama endpoint — `ollama pull \(appState.settings.vision.modelName)` and leave Ollama running.")
                    .font(Aurora.ui(12, .regular)).foregroundStyle(.white.opacity(0.55))
            case .anthropic:
                secure("Claude API key", "sk-ant-…", text: $appState.settings.vision.apiKey)
                Text("Claude writes the organized note. Voice stays on-device. Key from \(ModelProvider.anthropic.keyURL).")
                    .font(Aurora.ui(12, .regular)).foregroundStyle(.white.opacity(0.55))
            case .gemini:
                secure("Gemini API key", "AIza…", text: $appState.settings.vision.apiKey)
                Text("One key covers transcription and the organized note. Key from \(ModelProvider.gemini.keyURL).")
                    .font(Aurora.ui(12, .regular)).foregroundStyle(.white.opacity(0.55))
            case .api:
                field("API URL", "https://…", text: $appState.settings.vision.apiURL)
                secure("API key", "sk-…", text: $appState.settings.vision.apiKey)
                field("Model", "gpt-4o", text: $appState.settings.vision.modelName)
            }

            if needsKeyWarning {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.98, green: 0.82, blue: 0.42))
                    Text("No key yet. Mindspace will still organize notes using the on-device model — it works, but it's noticeably slower and rougher than a hosted model. You can add a key any time.")
                        .font(Aurora.ui(12, .regular)).foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1))
            }

            HStack(spacing: 12) {
                Button {
                    appState.saveSettings()
                    appState.checkVisionStatus()
                } label: {
                    Text("Test connection")
                        .font(Aurora.ui(13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.white.opacity(0.14), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(AuroraPressStyle())
                Text(appState.visionStatus)
                    .font(Aurora.ui(12, .medium)).foregroundStyle(.white.opacity(0.65))
            }
            .padding(.top, 4)

            Text("Changeable any time in Settings. Your notes never depend on it.")
                .font(Aurora.ui(12, .regular)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var needsKeyWarning: Bool {
        appState.settings.vision.provider.needsKey
            && appState.settings.vision.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("It is yours now")
                .font(Aurora.display(38)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 12) {
                bullet("⌘⇧K", "Keep whatever is in front of you: window, region, selection, voice or meeting.")
                bullet("⌘F", "Find anything you have kept, by what you saw or by what you thought.")
                bullet("Right-click a capture", "Move it somewhere it belongs, or let it go.")
                bullet("Your files", "Plain Markdown on your own disk. Readable without this app, in ten years.")
            }
            Text(readyLine)
                .font(Aurora.ui(13, .regular)).foregroundStyle(.white.opacity(0.6))
                .padding(.top, 6)
        }
    }

    private var readyLine: String {
        snapshot.allGranted
            ? "Everything is on. Go keep something."
            : "Grant the rest whenever. Mindspace asks only when it actually needs them."
    }

    // MARK: fields

    private func field(_ title: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Aurora.mono(9.5)).tracking(1.1).foregroundStyle(.white.opacity(0.5))
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Aurora.ui(13, .regular))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1))
        }
    }

    private func secure(_ title: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Aurora.mono(9.5)).tracking(1.1).foregroundStyle(.white.opacity(0.5))
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Aurora.ui(13, .regular))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1))
        }
    }
}

/// A drawn map of the System Settings pane the permission lives in, with the
/// row you need pulsing. Not a screenshot — it stays right when Apple moves
/// things around, and it can point at the exact switch.
struct AuroraSettingsMap: View {
    let permission: NotedPermission
    @State private var pulse = false

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
                        .font(Aurora.ui(11, .semibold)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 0) {
                    Text(paneTitle)
                        .font(Aurora.ui(13, .bold)).foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

                    row(name: "Another app", on: false, highlight: false)
                    row(name: "Mindspace", on: true, highlight: true)
                    row(name: "Some other app", on: false, highlight: false)
                }
                .padding(.bottom, 14)
            }
            .background(.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1))

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
            .foregroundStyle(.black)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
                .fill(.white.opacity(highlight ? 0.9 : 0.2))
                .frame(width: 18, height: 18)
            Text(name)
                .font(Aurora.ui(12.5, highlight ? .bold : .regular))
                .foregroundStyle(.white.opacity(highlight ? 0.95 : 0.45))
            Spacer()
            ZStack {
                Capsule()
                    .fill(on ? Color(red: 0.35, green: 0.78, blue: 0.55) : .white.opacity(0.18))
                    .frame(width: 34, height: 20)
                Circle().fill(.white).frame(width: 16, height: 16)
                    .offset(x: on ? 7 : -7)
            }
            .overlay {
                if highlight {
                    Capsule()
                        .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                        .frame(width: 46, height: 32)
                        .scaleEffect(pulse ? 1.12 : 0.94)
                        .opacity(pulse ? 0 : 0.9)
                        .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(highlight ? Color.white.opacity(0.1) : .clear)
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
