# Mindspace

Keep the things you see and the thoughts you had about them, in one place.

Press a key, grab whatever is on your screen — a window, part of a window, text you have
selected, something you say out loud, a whole meeting — and write a line about why you kept
it. When a note has enough in it, Mindspace writes the tidy version for you, and shows you
what it was written from.

For Macs running macOS 14 (Sonoma) or newer. Works on Apple silicon and Intel.

---

## Install it

### The easy way

1. **[Download Mindspace](https://github.com/sanjana-venkat/mindspace/releases/latest)** — the
   file ending in `.dmg` on that page.
2. Open the downloaded file.
3. Drag the **Mindspace** icon onto the **Applications** folder shown beside it.
4. Open Mindspace from Applications (or Launchpad).

That is all. The app is signed and approved by Apple, so it opens straight away — no scary
warnings, nothing to click through in System Settings.

### With Homebrew

If you already use Homebrew, paste these three lines into Terminal instead:

```bash
brew tap sanjana-venkat/mindspace
brew trust sanjana-venkat/mindspace 2>/dev/null || true
brew install --cask sanjana-venkat/mindspace/mindspace
```

Later, to get the newest version:

```bash
brew update && brew upgrade --cask mindspace
```

(If you have not heard of Homebrew, ignore this section — use the easy way above.)

---

## The first few minutes

Mindspace walks you through setup the first time you open it. Three things it will ask for,
and why:

- **Screen recording** — this is how it captures anything at all. Without it nothing works.
- **Microphone** — only for voice notes and meetings.
- **Accessibility** — so it can read the text you have selected when you ask it to.

macOS asks for each one in its own window. Say yes, and setup carries on.

It also downloads a **215MB speech model** during setup, once. That is what turns talking into
text, on your own Mac, without sending audio anywhere. You can keep setting things up while it
downloads.

---

## Using it

**The moon.** A small moon floats on your desktop. It is how you capture things without
leaving whatever you are doing. Hover it and its options fan out around it:

| Icon | What it does |
|---|---|
| Camera | Take a picture of a whole window, or drag a box around part of the screen |
| Text | Save the text you have selected right now |
| Waveform | Record — your microphone, or the sound your Mac is playing |
| People | Take meeting notes: you on one side, everyone else on the other |

Drag the moon anywhere you like. It stays put, out of the way, and tells you where things are
being saved.

**Or use the keyboard**, without touching the moon:

| Shortcut | What it does |
|---|---|
| ⌘⇧K | Show the moon's options |
| ⌘⇧G | Grab part of the screen |
| ⌘⇧P | Grab the whole window |
| ⌘⇧T | Save the text you have selected |
| ⌘⇧A | Start or stop recording audio |
| ⌘⇧M | Start or stop meeting notes |

**After each capture** Mindspace asks what you were thinking, in a line or two. That line is
the point — it is what makes the capture worth anything later.

**In a meeting?** If you join a Zoom or Google Meet call, Mindspace offers to take notes. It
records nothing until you click **Take notes**.

**Your notes** live in a folder on your Desktop called **Mindspace**. They are ordinary text
files — readable in any app, yours to move or back up, and there whether or not Mindspace is
running.

---

## Questions people ask

**Does anything leave my Mac?** Not unless you ask it to. Captures, recordings and notes stay
in that Desktop folder, and speech is transcribed on your own machine. Only if you add a key
for a cloud model (below) does anything get sent anywhere.

**Do I need to pay for anything?** No. Mindspace works on its own using the model on your Mac.
Connecting a paid service makes the write-ups better, and is entirely optional.

**Will it record me without asking?** No. Recording begins when you start it, and stops when
you stop it. In meetings it offers, and waits.

**How do I get a newer version?** If you installed the easy way, download the new file and drag
it over the old one. With Homebrew, `brew update && brew upgrade --cask mindspace`.

---

## Connecting a smarter model (optional)

Out of the box the write-ups are done by a model running on your Mac — free and private, but
slower and rougher. In **Settings** you can paste a key from any of these instead:

| Service | Where the key comes from |
|---|---|
| OpenAI | platform.openai.com |
| Gemini | aistudio.google.com |
| Claude | console.anthropic.com |
| Ollama | Nothing to paste — install Ollama and pull a model |

Each service keeps its own key, so switching between them does not lose the others. Keys are
stored on your Mac in a file only your account can read.

---

## For developers

Build it yourself — macOS 14+ and Xcode 16+:

```bash
git clone https://github.com/sanjana-venkat/mindspace.git
cd mindspace
./scripts/build_app.sh release
open Mindspace.app
```

Swift Package Manager, no Xcode project. `NotefyCore` holds capture, storage and the model
clients; `NotefyApp` is the SwiftUI app. Speech recognition is Parakeet, via a vendored copy of
[FluidAudio](https://github.com/FluidInference/FluidAudio) under `ThirdParty/`. `swift test`
runs the suite. `./scripts/publish.sh <version>` cuts a signed, notarized release and updates
the Homebrew tap.

Notes are Markdown with a JSON sidecar beside them holding the captures, your thoughts and any
write-ups. Nothing is in a database.

## Privacy

No analytics, no accounts, no meeting bot. Meeting detection looks at the frontmost window and
whether the microphone is in use, entirely on your Mac, and never starts recording on its own.
Whatever you send to a cloud provider, by choosing one, is handled under that provider's terms.

## License

No open-source license has been selected yet.
