# Notefy 🚀

Notefy is a native macOS exploration journal and note-taking companion. It runs directly on your Mac, watches active application focus shifts, captures browser context (URL/Title), grabs text highlights, takes silent screenshots, and records voice thoughts—all compiled into clean, structured Markdown reports with citations.

Developed in pure Swift, Notefy enforces strict data privacy: **all transcriptions, screenshots, and logs remain locally on your machine.**

---

## 🛠️ Architecture & Components
*   **Tracker (`Sources/Notefy/Tracker.swift`)**: Watches `NSWorkspace` window changes, triggers AppleScript to read active Chrome tabs, and copies highlighted selections.
*   **Capture (`Sources/Notefy/Capture.swift`)**: Invokes macOS `/usr/sbin/screencapture` silently to log screenshot states.
*   **Recorder (`Sources/Notefy/Recorder.swift`)**: Records audio journal thoughts via `AVAudioRecorder`.
*   **Summarizer (`Sources/Notefy/Summarizer.swift`)**: Automatically filters context-switching noise (Slack, Messages) and formats notes with citation indices.
*   **Main (`Sources/Notefy/main.swift`)**: Command line controller hosting the threading loops.
*   **notefy.swift**: A combined, single-file script for quick script-based execution.

---

## 🚀 Getting Started

### Prerequisites
- macOS 14.0 or later
- Swift 5.9+ compiler toolchain (installed by default with macOS command line tools)

### Running the App
On modern Apple Silicon macOS, locally compiled binaries require strict system certificates to bypass execution limits (SIGKILL 137). To get around this, run Notefy dynamically using the Swift interpreter:

```bash
swift notefy.swift
```

Once running, interact with the console using:
*   **`e`**: Start / Stop the Exploration Tracker session.
*   **`p`**: Pause / Resume monitoring.
*   **`r`**: Start / Stop recording a voice thought.
*   **`q`**: Quit the session.

All logs, summaries, and captured screenshots are exported directly to:
📁 `~/Desktop/Notefy_Sessions/`
