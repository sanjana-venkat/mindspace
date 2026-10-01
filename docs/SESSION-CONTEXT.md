# Where things stand

Written for whoever picks this up next, human or model, so the first twenty
minutes are not spent asking questions that already have answers.

Last updated: 30 Sep 2026.

## The release is blocked, and not on the profile name

The notarytool keychain profile is called **`mindspace`**. Do not go looking
for it again.

Knowing the name does not unblock anything. A full publish was run with
`MINDSPACE_SIGN_IDENTITY="Developer ID Application: Sanjana Venkat (5GV64S6S7C)"`
and `MINDSPACE_NOTARY_PROFILE=mindspace`, and Apple answered:

    Error: HTTP status code: 401. Invalid credentials.

The stored app-specific password is dead. Apple revokes those when the Apple ID
password changes. The only fix is for Sanjana to generate a new one at
appleid.apple.com and run, herself:

    xcrun notarytool store-credentials "mindspace" --apple-id sanjanavnkt20@gmail.com --team-id 5GV64S6S7C

Everything before that step already works: the universal binary builds
(`x86_64 arm64`), the app signs, the DMG is created and signed. Only
notarize → staple → publish → tap remain.

## Do not run two sessions against this working tree

Two agent sessions edited this checkout at the same time on 30 Sep. One
committed the other's in-progress work (`790cd8b`), `pitch/figma-plugin/manifest.json`
vanished twice, and an `output/` directory appeared mid-edit. Nothing was lost,
but only by luck.

The app enforces one copy per notes folder now (see below). Nothing enforces one
editor per repo.

## One copy of the app at a time

`Sources/NotefyApp/StoreLock.swift` takes an advisory `flock` on
`~/Desktop/Mindspace/.lock` before `AppState` is constructed. A second copy shows
a card naming which app holds the folder, and opens no files at all.

This exists because a dev build left running since 19 September was overwriting
`workspace.json` with a week-old view of the folders. Notes survived that, since
they are found by scanning the directory, but folder organization did not.

`scripts/build_app.sh` smoke-launches the app for four seconds and therefore
holds the lock. It now waits for that process to die, or the next launch meets
its own corpse and reports "already open".

## The data lives on the Desktop

`~/Desktop/Mindspace`. Notes are `Note_*.md` with a JSON sidecar in `Note_Data/`.
Back it up before anything destructive:

    cp -R ~/Desktop/Mindspace ~/Desktop/Mindspace-backup-$(date +%H%M%S)

API keys are in `~/Library/Application Support/Notefy/model-keys.json`, 0600
inside a 0700 directory. Deliberately not the Keychain: the prompts were
unbearable. Do not move them back without asking.

## What is unverified

- The x86_64 slice of the universal binary has never been run. All testers are
  on Apple Silicon.
- Retrieval for asking is keyword scoring with a recency tiebreak, not
  embeddings. It finds "pricing" and misses "that thing about money".
- An unexplained outbound beacon was seen on this Mac and never identified:
  `http://45.94.47.204/api/tasks/...`. Not from this project. Worth remembering
  before granting anything standing access to signing keys.

## Things not to do

- Do not invent model names. Real ones: `gpt-6-astra`, `gpt-5.6-sol`,
  `gpt-5.6-luna`, `gpt-5.6-terra`. Gemini and Ollama lists come from the
  provider APIs.
- Do not handle passwords or API keys. Sanjana runs those commands.
- Do not put numbers on the pitch deck that nobody has checked. Every figure in
  `pitch/` is a dashed blank on purpose.
