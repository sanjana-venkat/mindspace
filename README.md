# Notefy 🚀

Notefy is a native macOS exploration journal and note-taking companion. It runs directly on your Mac, watches active application focus shifts, captures browser context (URL/Title), grabs text highlights, takes silent screenshots, and records voice thoughts—all compiled into clean, structured Markdown reports with citations.

Developed in pure Swift, Notefy enforces strict data privacy: **all transcriptions, screenshots, and logs remain locally on your machine.**

## Kami capture overlays

- Press **⌘⇧K** to summon Kami's right-edge capture rail. Existing capture shortcuts still deep-link to their action.
- Capture offers a full-window screenshot or partial-region selector with a live size readout.
- Screenshots land in a stamp-and-sticky review; selected text opens as a blurred text lift. Add up to 280 characters or a 60-second voice annotation, then Keep or discard.
- Kept items immediately update `~/Desktop/Notefy_Sessions/Current_Raw_Note.md`. Finishing the working session creates timestamped Raw and Organized notes.
- Audio and Meeting open floating ruled-paper notepads. Handwritten notes and audio timestamps are included in the final locally captured transcript.

---

## 🛠️ Architecture & Components
*   **NotefyCore (`Sources/NotefyCore/`)**: Shared library — `Tracker.swift` (manual session items and Chrome context), `Capture.swift` (native ScreenCaptureKit screenshots), `Recorder.swift` (`AVAudioRecorder` voice notes), `Summarizer.swift` (Markdown notes), `AudioClient.swift` / `VisionClient.swift` (local or API transcription & vision), `ModelConfig.swift` (settings).
*   **Notefy (`Sources/Notefy/main.swift`)**: The original command-line controller, for headless/scripted use.
*   **NotefyApp (`Sources/NotefyApp/`)**: The SwiftUI menu bar app — `NotefyApp.swift` (menu bar + window scenes), `AppState.swift` (observable session state), `Theme.swift` (Notefy's own ink & paper color palette), `Views/` (menu bar dropdown, dashboard, history browser, settings).
*   **notefy.swift**: A combined, single-file script mirroring the CLI for quick interpreter-based execution.

---

## 🚀 Getting Started

### Prerequisites
- macOS 14.0 or later
- Swift 5.9+ compiler toolchain (installed by default with macOS command line tools)

### Running the GUI app (recommended)
Build and launch the menu bar app, packaged as a proper signed `.app` bundle:

```bash
./scripts/build_app.sh          # debug build → Noted.app
open Noted.app
```

Notefy lives in the menu bar (look for the pencil icon). Click it for quick
start/pause/record controls, or choose **Open Notefy** for the full window
with a live activity dashboard, session history browser, and model settings.

Pass `release` to build an optimized bundle: `./scripts/build_app.sh release`.

### Permissions and hotkeys

Grant Notefy **Screen & System Audio Recording** and **Microphone** access in
System Settings when macOS prompts. Accessibility access is optional and is
only used to read the currently selected text without changing the clipboard.
On first launch, Noted walks through Microphone, Accessibility, and Screen &
System Audio one at a time, polls macOS for the real status, and provides direct
links to each Privacy pane. Open Settings → Mac Permissions to run the flow
again. Capture actions never request permissions themselves, preventing repeated
or misleading prompts.

* **⌘⇧E** starts or finishes a manual capture session.
* **⌘⇧K** summons or dismisses Kami's capture rail.
* **⌘⇧T** adds the currently selected text.
* **⌘⇧P** captures the active page/window and its Chrome context.
* **⌘⇧G** opens the drag-selected partial-region overlay.
* **⌘⇧A** starts an audio notepad; while recording it inserts a timestamp.
* **⌘⇧M** starts or stops a standalone meeting note.

Notefy does not capture screenshots automatically. A session only contains the
items you explicitly add with these hotkeys or the matching UI controls.
For Chrome HTML archives, enable **View → Developer → Allow JavaScript from
Apple Events** in Chrome. URL/title and screenshot capture still work when that
option is disabled.

Meeting notes keep microphone and computer audio as separate tracks, transcribe
both, and label them as you vs. other participants. If macOS does not grant
system-audio capture, Notefy continues with a microphone-only recording.

The microphone can be set to **System Default** or a specific CoreAudio input
under Settings → Voice Transcription. During recording, independent **YOU** and
**OTHERS** meters show whether the microphone and computer-audio streams are
healthy. Both streams expose 16 kHz mono PCM inside `MeetingRecorder`, are saved
as separate WAV files, and are transcribed separately before being assembled
into the note. Zoom, Google Meet, Teams, and other meeting apps require no bot
or vendor integration because “Others” is captured locally with ScreenCaptureKit.

### Fully local models

Local speech transcription uses WhisperKit. The chosen model is downloaded
once and cached under Application Support. Screen understanding and final note
organization use the configured Ollama `/api/chat` endpoint; no cloud API is
called while both providers are set to **Local**.

### Running the console CLI
On modern Apple Silicon macOS, locally compiled binaries require strict system certificates to bypass execution limits (SIGKILL 137). To get around this, run the CLI dynamically using the Swift interpreter:

```bash
swift notefy.swift
```

Once running, interact with the console using:
*   **`e`**: Start / Stop the Exploration Tracker session.
*   **`p`**: Pause / Resume monitoring.
*   **`r`**: Start / Stop recording a voice thought.
*   **`q`**: Quit the session.

Both the GUI and CLI read/write the same session data and settings:
📁 `~/Desktop/Notefy_Sessions/`
