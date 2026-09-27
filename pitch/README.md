# Mindspace pitch deck · Figma

Seven slides, 1920 x 1080, built as native Figma layers. Every element is a real
frame, text layer, rectangle or arc, so you can edit anything after it lands.

## Build the file (about 30 seconds, once)

1. Open the **Figma desktop app** and create a new design file. Name it `Mindspace pitch`.
2. Menu bar: **Plugins → Development → Import plugin from manifest…**
3. Choose `pitch/figma-plugin/manifest.json` from this repo.
4. **Plugins → Development → Mindspace Pitch Deck.**

The seven slides appear left to right with speaker notes on the canvas under each
one. From there it is an ordinary Figma file: share it, present it with **Present**,
or export to PDF with **File → Export frames to PDF**.

Run the plugin again and you get a second copy of the deck. Delete the first if you
do not want both.

## Fonts

The plugin asks for the real brand faces first and falls back if they are missing:

| Role | First choice | Falls back to |
|---|---|---|
| Wordmark | Boldonse | Hanken Grotesk ExtraBold, Inter Bold |
| Headlines | Hanken Grotesk Bold | Inter Bold |
| Body | Hanken Grotesk | Inter |
| Prose and quotes | Newsreader | Lora, Georgia |
| Labels and counts | Geist Mono | IBM Plex Mono, Roboto Mono |

All of the first choices are on Google Fonts, so Figma should already have them.
Nothing breaks if one is unavailable, the type just shifts to the next in line.

## What is on each slide

| Frame | Slide |
|---|---|
| `1 · Hook` | Moon, folder arcs, "Imagine you could Cmd + F your brain." |
| `2 · The problem` | Collected, not connected. Scattered arcs on the right. |
| `3 · The belief` | Use AI to preserve human intelligence. |
| `4 · The foundation` | Current product. Capture, organize, summarize. |
| `5 · The experience` | Mobile prototype concept. Three phone screens. |
| `6 · One use case` | Illustrative exchange. Retrieved vs interpretation. |
| `7 · Team and close` | Team, closing line, demo QR placeholder. |
| `A1 · Market and model` | Why now, bottom up sizing, how it makes money. |
| `A2 · Where we sit` | The answer to "how is this different", as a matrix. |
| `A3 · Next twelve months` | Three phases, each proving one thing. |

The three appendix slides are **not part of the two minutes**. They exist so that
when a judge asks about market, competitors or the plan, you flip to a prepared
answer instead of improvising. Their notes are labelled "if asked" rather than
"speaker notes".

Every number on them is a **dashed blank**. That is deliberate. Fill them in from
LinkedIn Talent Insights or BLS occupational data, in your own hand, before you
pitch. A number invented on stage is the one a judge will chase.

Slide copy and speaker notes also live in `SLIDES.md` if you want to rewrite them
outside Figma.

## Before you present

- Slide 7 has a dashed **demo link or QR placeholder**. Replace it.
- Slides 5 and 6 are labelled as concept and illustrative. Keep those labels.
- Speaker notes total 252 words, which runs about two minutes.

## Editing the generator

`code.template.js` is the readable source. `code.js` is the same file with the moon
and grain images inlined as base64, which is what Figma actually runs. After editing
the template:

```bash
cd pitch/figma-plugin && python3 build.py
```

## Preview

Rough renders of each slide are in `preview/`. They are approximations made
outside Figma, so type and spacing shift slightly in the real file.
