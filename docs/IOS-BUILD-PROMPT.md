# Build Mindspace for iPhone: brief for ChatGPT

Paste everything below the line into ChatGPT. Attach these files with it so it can match the
look exactly:

- `Sources/NotefyApp/Resources/Pet/moon-idle.png`, `moon-face-blank.png`, `moon-pleased.png`,
  `moon-holding.png`, `moon-catching.png` (the moon character)
- `docs/screenshots/home-ring.jpg`, `captures-grid.jpg`, `your-thought.jpg`,
  `ask-mindspace.jpg`, `talk-to-the-moon.jpg`, `topic-notes.jpg`, `write-up.jpg`
- `docs/screenshots/banner.jpg` (the aurora art style)
- The two font files: Hanken Grotesk and Geist Mono (both free, Google Fonts / Vercel)

---

## Who you are and what we are building

You are a senior iOS engineer and product designer. Help me build **Mindspace for iPhone**, a
native SwiftUI app. A macOS version already exists and ships; the iPhone app must feel like the
same product, share its file format, and follow its design language exactly.

Work in small, compiling steps. For every step give me complete files (never "rest of the file
unchanged"), tell me where each file goes in the Xcode project, and tell me what to test before
moving on. Ask me before adding any third-party dependency. Prefer Apple frameworks.

**Targets:** iOS 18+, iPhone first (iPad should simply work), Swift 6, SwiftUI, Xcode 26.
Bundle ID prefix `com.openhuman.mindspace`. Team: Open Human.

## The product in one line

**Imagine you could Cmd + F your brain.** Mindspace is a personal memory. You keep anything you
see, hear or think, add a line about why it mattered, and find it again later by asking. Answers
come only from what you kept, with citations to the exact capture.

Long term it becomes a record of how you think, a memory that helps you remember for yourself
and one day carries your context into the AI you already use. For now the focus is utilitarian:
it has to be the best place to keep and find things.

## Core concepts (same as the Mac app)

- **Capture (step):** one thing you kept. A screenshot or photo, a piece of text, a link, a voice
  note, or a meeting transcript. Each has a timestamp and a source (app, page title, URL).
- **Thought:** the line you write about why you kept a capture. Stored per capture. These words
  are what search, citations and summaries lean on most.
- **Note:** an ordered collection of captures plus their thoughts, with a title.
- **Topic:** a folder of notes. New users start with **Learning**, **Reading** and a built-in
  **Ungrouped** for notes not in a topic. The user can rename Ungrouped.
- **Write-up (organized note):** an AI version of a note as its key ideas, as a "Bullet list"
  or an "Essay", shown beside your own words, never replacing them.
- **Ask:** a question answered only from your captures, with numbered citations you can tap.
- **The moon:** the mascot and the voice entry point. Tap him to ask out loud.

## What changes on iPhone (platform limits, design around them)

iOS does not allow what the Mac app does with global hotkeys, screen capture of other apps,
or reading highlighted text in other apps. Replace each one like this:

| Mac feature | iPhone equivalent |
|---|---|
| Capture a window or region with a hotkey | **Share Extension** ("Save to Mindspace") from any app: images, screenshots, URLs, text, PDFs. Plus "Import screenshots" from Photos (PhotosPicker), with a smart filter for recent screenshots. |
| Highlight text with the moon | Share Extension receiving selected text, and a **"Paste from clipboard"** action in the app. |
| Desktop moon pet | **Home Screen widget** and **Lock Screen widget** with the moon; tapping opens voice Ask or a quick capture. |
| Global shortcut | **App Intents**: "Ask Mindspace", "Save to Mindspace", "Start voice note". Exposed to Siri, Shortcuts, Spotlight, the **Action Button** and a **Control Center control**. |
| Meeting transcription | In-app recording with a **Live Activity** (Dynamic Island) showing it is recording. Background audio mode. Clear consent copy; never record silently. |
| Live transcript (Parakeet on Mac) | Apple's on-device speech: `SpeechAnalyzer` / `SpeechTranscriber` on iOS 26, `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` as fallback. |

The Share Extension is the most important capture path. Build it early, and make it fast: it
should save and dismiss in under a second, with an optional "Why are you keeping this?" field.

## Data: the file format (must stay compatible with the Mac app)

Store everything as plain files in a **Mindspace** folder the user owns. Use the app's iCloud
Drive container (`NSUbiquitousContainers`) so the same folder can sync with the Mac later; fall
back to the local Documents folder when iCloud is off. Use an App Group container so the Share
Extension and widgets can write into the same store. Coordinate writes with
`NSFileCoordinator`.

Folder layout:

```
Mindspace/
  workspace.json            topics and per-note metadata
  settings.json             provider choices (no keys in here)
  Note_<unix seconds>.md    human-readable version of each note
  Note_Data/
    Note_<unix seconds>.json   the source of truth for each note
  region_<UUID>.png         screenshots and images
  voice_<UUID>.wav          voice notes (m4a is fine on iPhone; keep the voice_ prefix)
```

`Note_Data/Note_X.json` (keys the Mac app reads; keep them all, even if empty):

```json
{
  "title": "Test 1",
  "steps": [
    {
      "id": "35C1EDAE-37CC-4148-AE55-F06A0E0FDCE0",
      "timestamp": 812612364.65,
      "appName": "Google Chrome",
      "windowTitle": "MindSpace Moon Mascot Design",
      "url": "https://example.com/page",
      "selectedText": "text that was kept, if any",
      "screenshotPath": "region_<UUID>.png",
      "htmlPath": null,
      "pageText": "text read off the page or image, if any"
    }
  ],
  "annotations": { "<step id>": "the thought you wrote about this capture" },
  "organized": "# Title\n\n## Key Ideas\n- ...",
  "organizedVariants": { "Bullet list": "...", "Essay": "..." },
  "organizedStamps": { "Bullet list": "<hash of inputs>", "Essay": "<hash>" },
  "organizationTemplate": "Bullet list",
  "rawDraft": "",
  "annotationDraft": "",
  "thoughtGraph": { "nodes": [] }
}
```

Notes on the format:

- `timestamp` is a Swift `Date` encoded with the default `JSONEncoder` strategy: seconds since
  1 January 2001 (`timeIntervalSinceReferenceDate`), not Unix time.
- Voice notes are a step with `appName: "Your audio"`, `windowTitle: "Voice note"`, and the
  transcript in `selectedText`.
- The Mac app writes absolute `screenshotPath`s. On iPhone, write paths **relative** to the
  Mindspace folder and resolve both forms when reading (if absolute and missing, try the last
  path component inside the folder).
- `workspace.json`:

```json
{
  "folders": [
    { "id": "UUID", "name": "Learning", "tint": 0, "parentID": null, "x": 0, "y": 0 }
  ],
  "noteMeta": {
    "Note_1789810306.md": {
      "folderID": "UUID of its topic, or absent for Ungrouped",
      "pinned": false,
      "lastOpenedAt": 812618802.23,
      "canvasPosition": null
    }
  }
}
```

  A topic is a `folders` entry. A note belongs to a topic through `noteMeta[<note .md file
  name>].folderID`; no `folderID` means Ungrouped. Moving a note only changes that field, never
  the files. Ungrouped is not a folder entry; its display name is a local preference.
  `x`, `y`, `parentID` and `canvasPosition` are Mac-only: keep them when re-saving, ignore them
  otherwise. `tint` indexes the aurora palette below.
- Also write the `.md` file whenever a note changes, in this shape, so the notes are readable
  without the app:

```markdown
# Test 1

## Google Chrome · 12:29 PM

Selected screen region

![Capture](region_<UUID>.png)

> My thought: different types of research methods
```

Wrap all of this in a `MindspaceStore` (an `@Observable` class on the main actor) with async
load and save, and unit tests for encode/decode against the sample JSON above.

## AI providers and keys

The user picks a provider in Settings for two jobs:

1. **Multimodal summary and retrieval** (reads captures, writes summaries, powers Ask)
2. **Transcription** (finished meeting and voice transcripts)

Providers: **On-device**, **OpenAI**, **Gemini**, **Claude**. The user pastes their own key.

- On-device on iPhone: use Apple's **Foundation Models** framework (iOS 26, Apple Intelligence
  devices) for summaries and Ask, and Apple speech for transcription. Hide or explain it on
  devices without Apple Intelligence.
- OpenAI: `https://api.openai.com/v1/chat/completions`
- Claude: `https://api.anthropic.com/v1/messages`, default model `claude-sonnet-4-5`
- Gemini: the `generateContent` REST API; "Refresh model list" calls the models endpoint and
  shows how many models the key can use.
- Each provider has a model picker filled from that provider's model list.
- Store API keys in the **iOS Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
  shared with the extension through a keychain access group). Never in files, logs, analytics
  or UserDefaults. Show keys as dots once saved.

Write one small protocol, `ModelClient`, with `complete(system:, user:, images:) async throws ->
String`, and one implementation per provider using `URLSession` only. No SDKs.

## Ask: how answering works (port this exactly)

Two passes.

**Pass 1, retrieval (the librarian).** Build an index with one line per capture:
`[n] <note title> · <label> · <date> · <first ~200 characters of thought + text>`. Labels:
"your voice note, 3 Oct", "your screenshot, 3 Oct", the host without `www.`, or the app name.
Send it with this system prompt:

```
You pick sources for a question. You are given a question and an index of saved captures, one
per line, each starting with its number in brackets, then the note it belongs to, what it is,
when it was saved, and an excerpt.
Choose the captures that help answer the question, judging by meaning, not shared words:
synonyms, related topics and paraphrases count. Use the dates when the question is about time
("this week", "yesterday", "recently"). For a broad question ("what did I save", "summarise
everything") choose a wide spread. Choose at most 12, most useful first.
Reply with only a JSON array of the chosen numbers, like [4, 17, 2]. Reply [] if nothing is
relevant.
```

Parse the first `[...]` in the reply, tolerating code fences and stray words.

Fallback if the model call fails or there are no keys: keyword scoring. Drop stopwords
(the, a, what, did, save, saved, note, notes, find, show, tell, anything, ...). Each keyword in
the text scores 1, in the title 1.5. Multiply by `1 / (1 + ageInMonths * 0.5)`. Detect time
words ("today", "yesterday", "this week", "last week", "this month", "recent", "lately") and
filter by date, because "what did I save this week" has no keywords left.

**Pass 2, the answer.** Send the chosen captures as numbered sources (with their full text,
thought, date, and images for screenshots when the provider takes images) and today's date
written out ("Saturday 3 October 2026"). System prompt:

```
You are the person's own memory, answering from material they saved themselves.
How to answer:
· Answer the question directly in the first sentence. Work from the numbered sources:
summarise, compare, connect and draw the takeaway out of them when that is what is asked.
· Stay grounded. Everything you claim must come from the sources. If they genuinely do not
cover the question, say so in one sentence and name what is missing. Never fill a gap from
general knowledge.
· Cite with bracketed numbers like [2] or [2, 5] right after the claim they support. Every
factual sentence carries at least one. Only cite numbers that exist.
· Quote their own words when they wrote something well. They will recognise it.
· Plain prose, second person, no headings, no bullet lists, under 150 words.
· You are the part of them that remembers, so say "you saved", "you wrote", "you were looking
at", "you said".
```

Parse citations from the answer (`[2]`, `[2, 3]`, `[2-4]`, `[2][3]`) and show **only the cited
sources** as chips under the answer. Tapping a chip opens that capture in its note. While
thinking, show a status line: "Searching what you saved…", then "Reading…".

Log every question locally (never sent anywhere) to `questions.jsonl` in Application Support:
`{"date", "question", "kind": "ask" | "voice" | "search", "scope": "all" | "<note title>"}`.

## Screens

1. **Onboarding** (first launch only; never again after it is finished). Full-bleed aurora
   scenes that continue from one page to the next as you swipe. Pages:
   "Imagine you could Cmd + F your brain." · How you'll use it (keep, add why, ask) ·
   Permissions (microphone, speech, photos, each asked only when needed, with a reason) ·
   Add the Share Extension (show how to pin "Save to Mindspace" in the share sheet) ·
   Add the widget · Choose a model or stay on-device · Closing: **"Start remembering"** with the
   line "It remembers for you now, and in time it will help you remember for yourself."
2. **Home (Orbit).** The moon centred, ringed by one arc per topic. Arc length is proportional to
   how many notes the topic has, with a minimum so small topics stay tappable and a cap so one
   topic can't take the whole ring. The ring is always a complete circle with small gaps.
   Tapping an arc fans that topic's notes on a curve beside the ring, with the topic name as
   plain text above them; tapping outside closes the fan. When the fan is open, the "New topic"
   button becomes "New note". A segmented **Orbit / List** switch shows topics as a plain list.
3. **Note.** Captures as a grid (2 columns on iPhone, 3+ on iPad), every tile the same height
   so rows line up. Screenshots fill the box from the top and are cropped below. Very wide
   screenshots span two columns. Text captures sit on a soft green wash. Tap a tile to open it
   with its thought; long-press for a menu (move, delete, share); tap the image to view it full
   size on a dark background, swiping left and right between captures. Pinch zooms the grid.
   A "Write-up" tab shows the AI version as Bullet list or Essay.
4. **Ask.** The ✦ Ask pill sits at the bottom centre of every screen. Tapping it widens the same
   pill into a text field (do not swap in a different view) with the placeholder
   `Ask "what did I save last week?"`, a mic button and a send button. ✕ shrinks it back into
   the pill. Return sends. Inside a note, it asks about that note and the placeholder reads
   "Ask about this note". Answers open in a sheet with citation chips.
5. **Voice.** Tap the moon to ask out loud. Live transcript appears under him as you speak.
   His face changes: a soft smiling listening face with blinks while you talk, a surprised face
   when you pause, and back to idle when done.
6. **Settings.** Two cards: **Multimodal summary and retrieval** and **Transcription**, each with
   a provider switch (On-device / OpenAI / Gemini / Claude), key field, model picker and
   "Refresh model list". Also: appearance (system/light/dark), rename Ungrouped, "Show tips"
   to replay the tour, and "Delete all data".
7. **First-run tips.** A six-step spotlight tour the first time Home appears: the moon, the ring,
   Ask, the Orbit/List switch, New topic, the widget. Next, Skip, and "Got it" on the last.

## Design language (follow exactly)

**Writing rules for every word in the UI:** no em dashes, ever. Plain, warm, short. Sentence
case. No "AI-powered", no exclamation marks, no emojis except the ✦ spark.

**Colours** (light, dark), sRGB 0 to 255:

| Token | Light | Dark | Use |
|---|---|---|---|
| ground | 233,234,231 | 11,14,12 | app background |
| surface | 255,255,255 | 20,26,23 | cards |
| surface2 | 238,240,236 | 26,33,29 | capture headers, insets |
| ink | 16,20,16 | 255,255,255 | primary text |
| ink2 | 89,99,90 | 201,207,216 | secondary text |
| ink3 | 139,148,139 | 139,146,156 | captions, metadata |
| line | 214,219,211 | 42,47,55 | hairlines |
| accent | 14,109,85 | 52,211,153 | links, selection |
| accentSoft | 220,239,231 | 17,41,31 | soft accent fills |

**Topic arc palette, the aurora** (dark-mode values; use slightly deeper versions on light):
green 52,176,124 · violet 146,112,224 · amber 208,158,74 · blue 72,138,220 ·
teal 56,176,186 · rose 224,110,160. **Ungrouped is aurora teal** #54BDBD (dark) /
46,160,162 (light). New topics pick the next unused tint.

**Glass** (the Ask pill, arrows, floating controls): `.regularMaterial` plus a fill of white 14%
with a white 30% edge in dark mode; black 16% with a black 14% edge in light mode. Behind text
you must read (the open Ask field, answers), use near-solid glass: rgb 28,30,33 at 86% in dark,
white at 86% in light. Fields lift on a soft shadow with no outline.

**Type:** UI in Hanken Grotesk (semibold by default), reading text in the system serif
(`.serif` design, 15pt, line spacing 5), metadata in Geist Mono 9.5 to 10pt. Respect Dynamic
Type by scaling from these sizes.

**Shapes:** corner radius 18 continuous for tiles and cards, capsules for pills, 1pt hairlines.
Subtle film grain over the ground. Motion uses springs (`.smooth(duration: 0.2)`,
`.spring(response: 0.3, dampingFraction: 0.62)`), nothing bouncy or slow.

**The moon:** use the attached PNGs. Draw the face (eyes, mouth) in code over
`moon-face-blank.png` with `Canvas`, so expressions can animate: idle, attentive (soft smile,
blinking every 1.1 to 2.1 s), surprised (round eyes, small O mouth), happy (closed upward-arc
eyes, open grin). On press, show the happy face and lift him slightly (scale 1.07, up 3pt). In
light mode put a faint aurora glow behind him (teal 30%, violet 24%, green 18%, blurred 34pt).
No purple halo.

**The spark:** a custom four-point star with curved sides plus a small second star, drawn as a
`Shape`, not an SF Symbol (the symbol reads as a plus).

**Accessibility:** VoiceOver labels on every control, including the moon ("Ask out loud") and
each arc ("Learning, 4 notes"); 44pt minimum hit targets; Reduce Motion turns the fan and moon
animations into fades; contrast at least 4.5:1 for text.

## Privacy rules (non-negotiable)

- Everything lives on the device (and the user's own iCloud, if on). No accounts, no server of
  ours, no analytics, no crash reporters that send content.
- Only the provider the user chose is ever called, only with the captures needed for that
  request, and never in the background without the user asking.
- Keys only in the Keychain. Never log keys, captures or questions.
- Fill in the App Privacy "nutrition label" as: no data collected.
- Microphone and speech permission strings must say exactly what is recorded and that it stays
  on the device unless a cloud provider is chosen.

## Build order (one milestone at a time, each must compile and run)

1. Xcode project: app target, Share Extension, Widget extension, App Group, iCloud container,
   design tokens, fonts, moon assets, spark shape.
2. `MindspaceStore` with the file format above, plus unit tests against the sample JSON.
3. Home Orbit with the ring, moon and topic fan, and the List view. Seed Learning, Reading,
   Ungrouped on first launch.
4. Note screen: capture grid, capture detail with thought editing, full-size viewer.
5. Share Extension and Photos import, writing into the shared store.
6. Provider settings, Keychain, `ModelClient` for all four providers.
7. Ask pill and the two-pass Ask with citations; question log.
8. Voice: moon expressions, on-device live transcript, voice notes.
9. Meetings: recording, Live Activity, transcript into a note.
10. Write-up (Bullet list / Essay), with a stamp so it only regenerates when inputs change.
11. Widgets, App Intents, Control Center control, Action Button.
12. Onboarding and first-run tips.
13. Polish: accessibility pass, light/dark check of every screen, App Store assets.

At the end of each milestone, list what you built, anything you were unsure about, and what I
should try on a real iPhone.
