# Noted — visual restyle brief: ink, but premium editorial

You are restyling the existing Noted app. This is a **surgical retheme**, not a rebuild. Do not touch product logic, layout components' data flow, or the ink-splatter motion on the Raw/Organized segmented control (that animation stays exactly as it is — it is the one ornate thing on the page and everything else must get quieter to frame it).

Read `tokens.css` and the `assets/` folder before writing code. Use the tokens; do not invent new hex values.

## 1. Why it doesn't feel premium yet (diagnosis — read this, it drives every rule below)

The current UI has the right ingredients (cream paper, ink accent, a Didone display face) but assembles them the way a template does, so it reads as "AI editorial" rather than "magazine":

1. **Hierarchy is carried by decoration, not by type.** Every card opens with a tracked-out ALL-CAPS mono eyebrow (`VOICE · 11:47 PM`), and every section has one (`NOTE`, `COMPUTER AUDIO`, `ADD A NOTE`). Real editorial pages carry hierarchy through size, weight and position; caps are reserved for a running head or a folio, and used once.
2. **The SaaS card kit.** Content is chopped into identical rounded boxes with the same radius, the same soft shadow, and large dead space inside fixed-height cards. Magazines do not box content; they place it on a grid and separate it with space and hairline rules.
3. **The display face is doing fashion, not editorial.** A Black-weight Bodoni at ~120px for the word "Testing" is the loudest thing on the screen and competes with the ink blob. Premium editorial display is high-contrast but *light*, set smaller, with tight tracking.
4. **Body copy is a wide, large grotesque** at ~20px with an 80+ character measure. It reads like an accessibility reader, not a typeset page.
5. **Chrome is generic app chrome**: pill-shaped toolbars with grey icons, a zoom stepper, grid/list toggles in a capsule. These belong to any Electron app.
6. **The middle-dot meta string and the mono URL footer** are the two most common tells of generated UI. Keep mono *only* where the content is literally machine data (a URL, a file path).

## 2. Direction

**"Ink on a magazine page."** Reference points — study them for structure, not to copy:
- *The Gentlewoman*, *Kinfolk*, *Apartamento*, *Cereal* — generous margins, light-weight serif display, italic serif captions, asymmetric grids, one image allowed to dominate a spread.
- *Monocle* and *FT Weekend* — hairline rules that encode structure, small running heads, folios, tabular numerals, restraint with colour (one ink, one accent).
- *NYT Magazine* / *Bloomberg Businessweek* digital — editorial conventions translated to screen: standfirst/dek under a headline, drop rules, captions, pull quotes, no cards.

The product thesis still holds: Noted is the one opaque, matte, tangible sheet of paper on a screen full of glass. Make that sheet feel *typeset*.

Spend all boldness on two things: the existing ink-blob control, and one light Didone headline. Everything else is quiet.

## 3. Type system

Replace the current stack. Three roles, three faces, each clearly distinct:

| Role | Face | Fallback (free) | Rules |
|---|---|---|---|
| Display | Editorial New (Pangram Pangram), Regular / Ultralight | Fraunces (opsz 144, wght 300–400, SOFT 0) or Instrument Serif | Note titles, the "noted" wordmark. 44–64px, tracking −0.02em, line-height 1.0. **Never Black/Bold.** |
| Text | Tiempos Text or Newsreader | Newsreader (Google) | All note and fragment content, standfirst, captions (italic). 15–16px, line-height 1.55, measure **58–66ch max**. |
| Meta | Text face, italic or small size — *not* mono, *not* caps | — | Timestamps, fragment kind, footers. 12–13px italic, ink at 55%. Sentence case. |
| Data | JetBrains Mono / Geist Mono | — | **Only** URLs, file paths, region names. 11px, tracking 0, ink at 45%. |

Numerals: enable `font-variant-numeric: tabular-nums` on timestamps. Enable `font-feature-settings: "kern", "liga"` globally. Hanging punctuation on the text column if supported.

Concrete replacements:
- `VOICE · 11:47 PM` → italic meta, `Voice, 11:47 pm`, with the small ink glyph from `assets/fragment-glyphs.svg` before it. No middle dots anywhere.
- `NOTE` eyebrow above the title → delete. The title's size is the hierarchy.
- `COMPUTER AUDIO` / `SCREEN REGION` footers → italic meta caption below the content, sentence case, e.g. *Computer audio*. URLs stay mono.
- `ADD A NOTE` → an italic placeholder line in the text face: *Add a note…* — no caps.
- Title "Testing" → Display Regular, 56px in reader view, 44px in grid view.

## 4. Surface and structure (kill the card kit)

- **Fragments are plates on a page, not cards.** Remove all box shadows. Border: 1px hairline at `--ink-12`. Radius: `--radius-plate` (6px, continuous/superellipse if available). Background: same as page paper, or `--paper-plate` (a 2% lift), never white.
- **Plates size to content.** No fixed heights, no dead space. In grid view use a CSS columns / masonry layout (3 columns ≥1280px, 2 at ≥900px, 1 below) so a short text fragment does not become a tall empty box.
- **Rules encode structure.** A hairline rule separates the fragment header from body, and body from footer, *inside* the plate — but only when both sides have content. A heavier 1.5px rule (`--ink`) sits under the note title in reader view, like a drop rule under a headline.
- **Padding scale**: plate padding 24px; internal rhythm on a 4px grid; gutters 24px; page margins 48px (min 32px).
- **Images (captures) bleed** to the plate's full inner width and sit at the top, with the user's annotation as an italic caption beneath. Frame the image with the same hairline, no radius on the image itself.
- **Reader (split) view**: left column is a typeset text column — max-width 62ch, title, a hairline drop rule, then body. Right column becomes fragments-as-marginalia: same plates, narrower, with the column divider a single hairline at `--ink-12`.
- Selected/active plate: hairline switches to `--accent` at 1.5px. Nothing else changes; no glow, no lift.

## 5. Chrome

- Wordmark "noted": Display face, Regular, 28px, ink. Not bold.
- Top-left "Unfiled / Testing" breadcrumb pill → remove the pill; render as `Unfiled` in meta italic, then the title in text face at 15px, with a caret. It sits on the page, no container.
- Zoom stepper and grid/list toggles → keep function, drop the capsule containers. Icons become 1px-stroke line icons at `--ink-70`, 14px, with 32px hit targets. Active toggle: filled ink circle 6px beneath it (a printer's mark), not a filled button.
- Settings gear → same treatment.

## 6. Colour

Use only what's in `tokens.css`. Ink is `#1C1B19` — warm print black, never `#000` or `#111`. Paper stays the existing cream. The accent stays the existing cobalt/indigo used by the ink blob; it appears in ≤10% of visual weight: the blob, the active-plate hairline, links. No other tints, gradients or washes.

Apply `assets/paper-grain.svg` as a fixed, 3% opacity overlay on the app root (`mix-blend-mode: multiply`). It's the one texture; do not add others.

## 7. Motion

- Keep the segmented-control ink splatter untouched.
- Remove hover lifts/scales/shadow changes on plates. Hover = hairline goes from `--ink-12` to `--ink-30`, 120ms.
- Fragment enter: the existing FLIP transitions stay; entrance is a 160ms opacity fade only.
- `prefers-reduced-motion`: splatter becomes an instant state change.

## 8. Do / Don't

Do: sentence case; italic for meta; hairlines; whitespace as separator; content-sized plates; two type sizes per plate maximum (meta, body).
Don't: ALL-CAPS labels; letter-spaced mono eyebrows; middle-dot separators; box shadows; radius > 8px on anything except the ink blob; bold display; numbered markers; gradients; new colours; new icons with fills.

## 9. Acceptance checklist (screenshot each and compare)

- [ ] Zero ALL-CAPS strings on screen except the segmented control's `Raw / Organized` (which is part of the protected component).
- [ ] Zero `·` characters in meta.
- [ ] No box-shadow anywhere in the DOM (`getComputedStyle` audit).
- [ ] Grid view: no plate has more than 32px of empty vertical space below its content.
- [ ] Body text measure ≤ 66ch in both views.
- [ ] Title "Testing" is Regular weight, ≤ 64px.
- [ ] Mono appears only on URL/path strings.
- [ ] Ink-splatter animation frame-by-frame identical to before.

Work in this order: tokens → type → plates → chrome → motion audit. Commit after each step with a screenshot in the PR description.
