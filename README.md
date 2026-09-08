# Mindspace

An infinite canvas for the things you clip and the thoughts you had while clipping them.

Mindspace captures what's on your screen — a window, a region, text you selected, what you
said out loud, a meeting — and keeps your own note attached to each capture. When a note has
enough in it, a model reads the captures *and* your thoughts and writes the thing up, with its
sources.

macOS 14+. Everything is stored as plain Markdown on your Mac.

---

## Install

### Download

Grab the latest `.dmg` from [Releases](https://github.com/abisubramanya27/notefy/releases),
open it, and drag Mindspace to Applications.

Mindspace isn't notarized yet, so the first launch needs a right-click → **Open** (or
System Settings → Privacy & Security → *Open Anyway*). After that it opens normally.

### Homebrew

```bash
brew tap abisubramanya27/mindspace
brew install --cask mindspace
```

### Build from source

Requires macOS 14+ and Xcode 16+.

```bash
git clone https://github.com/abisubramanya27/notefy.git
cd notefy
./scripts/build_app.sh release
open Mindspace.app
```

---

## What it does

**Capture** — ⌘⇧K brings up the capture rail anywhere: full window, a region you drag, the
text you have selected, a voice note, or a meeting (your mic as *You*, system audio as
*Others*). Every capture lands in a note with room for the thought behind it.

**Canvas** — folders live on an infinite canvas you arrange yourself. Scroll to pan, pinch to
zoom, drag folders anywhere. The pile of notes peeking over each folder is how many captures
are inside. A list view sorts the same library.

**Read** — a note opens in three views:

- **Panels** — captures on the right, and the single thought attached to whichever one you're
  looking at on the left, under an aurora.
- **Organized** — the model's write-up: bullet list, essay, or meeting notes. Each shape is
  cached, so switching between them doesn't re-run the model.
- **Grid** — every capture-and-thought pair as a tile. Drag to rearrange, ⇧+arrows to move one.

Right-click any capture to forward or copy it into another note, or delete it.

---

## Models

Transcription runs on-device with WhisperKit by default. The organized note can come from:

| Provider | What it needs |
|---|---|
| On-device | [Ollama](https://ollama.com) running locally — no key, slower |
| OpenAI | key from platform.openai.com |
| Gemini | key from aistudio.google.com — also covers transcription |
| Claude | key from console.anthropic.com |

Keys are kept per provider, so switching between them doesn't lose the others. Without any key
Mindspace still works — it falls back to the on-device model and says so.

---

## Permissions

macOS asks once, and setup walks you through each one:

- **Screen & System Audio Recording** — required; it's how anything gets captured.
- **Microphone** — voice notes and the *You* side of meetings.
- **Accessibility** — reads only the text you have selected, when you press ⌘⇧T.

---

## Where your notes live

`~/Desktop/Notefy_Sessions` — one Markdown file per note, with a JSON sidecar holding the
captures, your thoughts, and any organized versions. Settings live beside them.

## License

See [LICENSE](LICENSE).
