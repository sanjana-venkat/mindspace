# Where things stand

Written for whoever picks this up next, human or model, so the first twenty
minutes are not spent asking questions that already have answers.

Last updated: 30 Sep 2026.

## Where the release got to

**0.1.8 shipped on 1 Oct 2026** and is verified: notarized, stapled, Gatekeeper
accepts it, and the cask checksum was checked against the DMG downloaded back
from GitHub rather than the local build. The tap is live and
`brew upgrade --cask mindspace` works.

The notarytool keychain profile is called **`mindspace`** and now holds valid
credentials. The earlier 401 was a dead app-specific password, regenerated on
1 Oct. `scripts/finish_release.sh` does store-credentials, verifies Apple
accepts it, and publishes, in one run.

To cut the next one:

    ./scripts/release.sh 0.1.9        # or ./scripts/publish.sh 0.1.9 for the lot

Release notes live in `docs/release-notes-<version>.md` and are picked up by
`MINDSPACE_RELEASE_NOTES`.

## What 0.1.8 added, and what is thin about it

The library opens as an **orbit**: folders as arcs around the moon, sized by
share of captures. Clicking an arc opens the folder as a sheet. The old grid is
one toggle away. Tapping the moon listens in place and sends the sentence as a
question. There is an ask box under the moon, and another inside every note's
write-up, both answering only from saved captures and citing them as clickable
chips.

All of that was written and shipped inside a few hours on 30 Sep and 1 Oct. It
had a bug found in every review round. Treat it as young code:

- Retrieval is **keyword scoring with a recency tiebreak, not embeddings**. It
  finds "pricing" and misses "that thing about money". Time phrases like "this
  week" are special-cased to a date window because stopword removal left them
  with no keywords at all.
- `AuroraFolderSheet` is a fixed 880x560. It has not been tried in a small
  window.
- Nobody has driven the orbit UI through a real usability pass. A static audit
  of the sixteen interactive paths passed, which only proves no button is wired
  to nothing.

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
