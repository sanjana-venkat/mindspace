# Handoff prompt — aurora visual pass (for Codex, if Claude runs out of session)

Paste everything below into Codex, working in `/Users/abishek_programming/Desktop/notefy`
on branch **`aurora-noted`** (branched from `feature/noted-canvas`).

---

You are continuing a visual pass on **Noted**, a native macOS SwiftUI/AppKit app
(NOT Electron — the source brief is written in CSS terms and must be translated).
The brief is `~/Downloads/noted-visual-pass-brief.md`. Read it first.

## Context you need

- Branch: `aurora-noted`, off `feature/noted-canvas`. Build with
  `swift build 2>&1 | tail -30` (Package.swift at repo root). There is a
  `scripts/` dir with a bundling script for `Noted.app`.
- Everything visual lives in `Sources/NotefyApp/Views/CanvasWorkspaceView.swift`
  (~2400 lines) plus `Sources/NotefyApp/GlassGround.swift` and `Ground.swift`.
- **The "left panel" in the brief** = `CaptureReadingView.rawNoteColumn`
  (`CanvasWorkspaceView.swift`), the 1/3-width column shown in Raw + panel
  layout. It holds the note title, the `BrushStroke()` underline, `NoteSlug`
  ("12 CAPTURES · UNFILED"), and the note TextEditor.
- **The Raw/Organized segmented control** = `ReaderTabBar` + `InkPillShape` /
  `InkTabShape`. The brief says do not touch these. Don't.
- **Folders** are currently drawn only as text rows in `CanvasFolderOverlay`
  and as the toolbar breadcrumb subtitle in `CanvasToolbar`.
- Palette/type tokens: `CanvasPalette` and `CanvasTypography` enums, near the
  bottom of `CanvasWorkspaceView.swift`.

## Critical translation notes (do not re-derive these)

1. **The frost is an `NSVisualEffectView` installed BELOW the SwiftUI hosting
   view** (`GlassGround.swift`, `WindowConfiguringView.configure()`). So you
   *cannot* put the aurora "behind the frost" the way the CSS does. The
   translation used is: draw the aurora fields in SwiftUI with `.screen`
   blending, then lay a **panel-only frost veil** (`GlassTokens.paper` tint +
   `FrostGrain`) *on top* of them. That veil is what the brief calls "the frost
   sits on top and does the mixing".
2. Because the veil is thin (0.13 alpha), field opacity must be tuned **well
   below** the brief's `.55` to hit the 8–14% saturation target. The brief
   itself says "if the panel looks colourful, reduce field opacity; the frost
   should always win."
3. **`assets/folder-*.svg` do not exist** anywhere in this repo or on disk. The
   four stocks are drawn natively in SwiftUI instead — which is the correct
   source form for a Swift app.
4. **There is no serif bundled** (fonts are Boldonse, Hanken Grotesk, Geist
   Mono, Caveat). The brief's "app's serif" for folder faces is fulfilled with
   `Font.system(design: .serif)` (New York), roman line 1 / italic line 2.
5. Drift loops must be **seamless**, not autoreversing. Use a single animatable
   `phase` 0→1 driving `cos(2πφ)` for x, `sin(4πφ)` for y (a Lissajous
   figure-eight — start state equals end state) and `sin(2πφ)` for scale, in an
   `Animatable` `ViewModifier`, animated `.linear(duration:).repeatForever(autoreverses: false)`.
   `@Environment(\.accessibilityReduceMotion)` freezes phase.

## Work items (check off what is already done in the diff)

- [ ] §5 tokens added to `CanvasPalette` (aurora pink/green/violet, dot,
      dot-star, four stocks, folder lift, `--ease` as `CanvasPalette.ease`).
- [ ] `Sources/NotefyApp/Views/AuroraPanel.swift` — four drifting fields,
      panel frost veil, dot field (24pt spacing, 1pt dots, 7–8 hand-placed
      1.6pt "stars" at .35, horizontal mask fading to nothing at the panel's
      right edge). Attached as `.background(...)` on `rawNoteColumn`, on the
      same padded box the trailing hairline `.overlay` already uses so the two
      align exactly.
- [ ] `Sources/NotefyApp/Views/PaperFolders.swift` — `FolderStock` (tag /
      envelope / receipt / card) with a **launch-stable** hash from the folder
      UUID bytes (NOT `Hasher`, which is per-process seeded), and
      `PaperFolderView` drawing all four at 300×380 proportions, radius 12
      continuous, scaled by a `width` parameter.
- [ ] Folder objects used in `CanvasFolderOverlay` rows and the `CanvasToolbar`
      breadcrumb (thumbnail chips — no layout/behaviour change).
- [ ] §4 card + plate corrections: card fill `#F7F4EE` @96%, border
      `rgba(27,33,64,.08)`; selected keeps cobalt 1.5px and no shadow; the dot
      field at half strength (`.06`) inside the Organized plate masked to its
      left 30%.

## Hard constraints from the brief

- Aurora is **panel-only**. Never tint the right side of the window.
- No shadow anywhere except under a folder on hover
  (`0 12px 32px rgba(30,28,25,.10)`, 4px lift). Cards and chrome get none.
- No gradient/glow/colour on the ink pill, the selected border, or any control.
- Do not touch `ReaderTabBar`, `InkPillShape`, `InkTabShape`, or the splatter
  motion.
- The four stocks are the only saturated colour besides cobalt; never on
  buttons, chips, or chrome.
- Panel text stays ink; if a field drops contrast under 7:1 behind the title,
  lower that field's opacity — never change the text colour.

## Acceptance

Build, run `Noted.app`, screenshot Raw view over a busy desktop and a plain
wallpaper. In both: left panel visibly but quietly tinted, main area neutral,
each of the four stocks recognisable at thumbnail size, nothing moving except
the sky behind the panel.
