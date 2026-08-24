# Noted — brand implementation brief

For Claude Code, working in the existing Noted repo. This is a **change spec
against code that already exists**, not a greenfield build. Do not rewrite
screens. Do not restructure components. Every task below is additive or a
targeted substitution.

Work the tasks **in order** and stop at each checkpoint. Task 1 and Task 2
produce most of the visible improvement; if you only do two, do those.

---

## The idea, in one paragraph

Noted is a **different surface that sits on top of the user's existing glass UI
windows.** Everything behind it — the OS, the browser, other apps — is glass:
cool, translucent, blurred. Noted is the one thing on screen that is *not*
glass: opaque, matte, warm, pressed. That contrast is the entire identity.

The current build fails because it is glass sitting on glass, so nothing reads
as an object. Every task below either makes Noted more material or gives the
screen the contrast it currently lacks.

Three elevations, and only three:
- **emboss** — a control raised out of the material
- **deboss** — content seated into the material
- **lift** — the whole Noted panel, resting on the desktop *(new)*

---

## Task 0 — Recon. Do this first, change nothing.

Report back before editing:

1. The path of the existing design-token file, and its full contents.
2. Where the app shell / root layout component lives.
3. The current logo or wordmark component, and every place it is referenced.
4. Every distinct colour literal in the codebase that is **not** a token
   reference. List file and line.
5. Every distinct `font-family` in use. There should be three: Geist,
   Geist Mono, Instrument Serif. Flag any fourth.
6. Whether a highlight/annotation component already exists for note text.

Do not proceed until you have reported this. Several tasks below depend on
matching existing names rather than inventing new ones.

---

## Task 1 — Land the brand token layer

Copy `tokens.brand.css` into the same directory as the existing token file and
import it **after** it. Copy `assets/` into the project's static asset
directory and fix the `--grain-url` path to match.

If the project uses Tailwind or a JS token object rather than CSS custom
properties, port the *values* but **keep them as CSS custom properties**. The
shadow values are compound and multi-layered; inlining them as arbitrary
utility values makes them impossible to change globally, and they are the thing
most likely to need tuning.

**Acceptance:** `--graphite`, `--pigment`, `--pigment-wash`, `--lift`,
`--fold-size`, `--grain-url` all resolve in devtools on a running page.

---

## Task 2 — Grain on every matte surface

Add the `nt-grain` class (or port its `::after`) to the app shell, the sidebar,
and any solid `--surface` panel.

- Surfaces only. **Never over a glass/backdrop-filter element** — it fights the
  blur and produces mud.
- `mix-blend-mode: multiply` at `0.055`. If it reads as noise, you have the
  opacity too high; do not raise it.
- The host needs `position: relative` and its own `border-radius` for
  `inherit` to work.

**Acceptance:** at 100% zoom the surface has visible tooth. Screenshot, then
toggle the `::after` off and screenshot again — the difference should be
obvious side by side but invisible as "an effect."

---

## Task 3 — Lift and fold on the app shell

This is the "matte on glass" move.

1. **Lift.** Apply `box-shadow: var(--lift)` to the outermost Noted panel.
   Exactly one lifted element per screen. Nothing inside Noted gets `--lift`.
2. **Fold.** On that same panel:
   ```css
   position: relative;
   clip-path: polygon(
     0 0,
     calc(100% - var(--fold-size)) 0,
     100% var(--fold-size),
     100% 100%, 0 100%
   );
   ```
   Then render `<span class="nt-fold" aria-hidden="true" />` as its first child.
3. **Clear the corner.** The fold consumes the top-right
   `--fold-size` square. Move any control currently there. Verify nothing is
   clipped or unreachable, including at 900px where `--fold-size` drops to 44px.

Note: `clip-path` on a scroll container can clip overflow in ways
`overflow: hidden` doesn't. If content disappears, apply the clip to a wrapper
and keep scrolling on the child.

**Acceptance:** the panel has a turned top-right corner matching
`assets/mark-flat.svg`, casts a soft outer shadow, and no interactive element
is inside the fold at any breakpoint.

---

## Task 4 — Graphite floating controls

The action bar, toolbars, and any floating menu become `.nt-pill`.

**I am reversing earlier guidance here.** A previous brief said to pull the dark
action pill back into the cream system. That was wrong — the palette has no dark
value, and these controls are the only real contrast on the screen. Keep them
dark, but as a **token**, applied consistently, never a one-off literal.

- `--graphite` is for controls that float *above* the material. Never a surface,
  never a background, never a hover fill on a panel.
- Primary action uses `.nt-pill--primary` (pigment). **One per screen.**
- Graphite pills are neither embossed nor debossed. They sit above the material
  entirely — that's why they don't break the grammar.
- Delete any remaining hard-coded near-black or off-system accent (the salmon
  asterisk next to "Organized" is one).

**Acceptance:** no colour literal outside the token file. Exactly one primary
pill per screen. Every dark control reads as floating, not inset.

---

## Task 5 — Pigment annotation

User annotations render as `.nt-mark` — a translucent cobalt wash on the matte
surface. Three strengths only: `--light`, default, `--deep`.

If a highlight component already exists (Task 0.6), change its styling; do not
add a parallel one.

This effect works *because* the surface beneath is opaque and matte. It is
impossible on glass. If you find yourself applying it over a
`backdrop-filter` element, the hierarchy is wrong, not the token.

**Do not** introduce a second highlight hue. One pigment, three dilutions. If a
multi-colour highlighter is requested later it needs a design decision, not an
implementation guess — raise it instead of picking colours.

**Acceptance:** highlighted text remains ≥4.5:1 against `--ink` at all three
strengths. Check `--deep` specifically.

---

## Task 6 — The mark

Replace the current logo with the asset set:

| Asset | Use | Never |
|---|---|---|
| `mark-flat.svg` | All UI, header, nav, ≥20px | — |
| `mark-favicon.svg` | Favicon, ≤16px, tab icons | Above 20px |
| `mark-flat-mono.svg` | 1-bit, stamps, print, single-path contexts | — |
| `mark-pigment.svg` | Active / selected state | Default state |
| `mark-material.svg` | App icon, splash, marketing | **Below 64px** |

`mark-flat.svg` uses `currentColor` for the body and `--mark-knockout` for the
crease — set `--mark-knockout` to whatever the mark sits on so it works on any
ground. On graphite, set it to `var(--graphite)` and the body to
`var(--on-graphite)`.

Wordmark: "Noted" in **Instrument Serif**, tracked `-0.02em`, mark at cap-height,
14px gap. No fourth typeface.

**Acceptance:** render the favicon at 16px and screenshot it. If the crease
reads as a smudge rather than a fold, report it rather than shipping — that is
the known failure mode of this mark and it needs a design fix, not a code
workaround.

---

## Task 7 — Ghost context layer

Behind the note body, a low-opacity serif text layer at `--ghost-opacity`
(0.055), `--ghost-size` (27px), two columns. This is what gives the reference
screens depth without spending colour, and its absence is why the current build
feels empty.

Requirements: `aria-hidden="true"`, `user-select: none`,
`pointer-events: none`, behind content in z-order. Content can be adjacent
note text or the note's own overflow — it is texture, not information, so it
must never be the only place something appears.

**Acceptance:** invisible to a screen reader, unselectable, and does not reduce
body-copy contrast below 4.5:1.

---

## Task 8 — Verification

Run all of these and report results. Do not mark the work done until each
passes.

- [ ] **Shadow directionality.** Every emboss/deboss has a visible light side
      *and* dark side, offset at 135°. A soft symmetrical halo means it was
      replaced with a generic shadow — fix it. This is the single most common
      regression and it flattens the entire design.
- [ ] **Nesting depth.** No more than two nested rounded containers anywhere.
      Source blocks and annotations inside a capture are typography, not boxes.
- [ ] **Typeface count.** Exactly three.
- [ ] **Colour literals.** Zero outside the token file.
- [ ] **Contrast.** Body copy ≥4.5:1. `--ink-faint` (#9B958F) is ~2.7:1 — it is
      only valid on uppercase mono labels, never body text.
- [ ] **Nothing fades.** No masks, no gradient overlays cutting off content.
      Scroll containers clear floating bars with padding, not opacity.
- [ ] **Favicon at 16px.** Screenshot it.
- [ ] **Fold at 900px.** Nothing clipped or unreachable.
- [ ] **Grain not on glass.** Grep for any element with both grain and
      `backdrop-filter`.
- [ ] **One lift, one primary pill** per screen.

---

## Anti-patterns — these broke the last build

1. **Substituting a generic shadow** for `--emboss` / `--deboss`. The palette
   has ~3% value separation between canvas and surface, so shadows carry 100%
   of the depth. There is no fallback. Never replace a compound directional
   shadow with `0 Npx Npx rgba(0,0,0,.05)`.
2. **Softening shadow opacity "to be subtle."** They are already subtle.
3. **A third container level.** Panel → row. That's it.
4. **A fourth typeface.** Including for annotations. Especially for annotations.
5. **Grain over glass.**
6. **A second accent hue.** Cobalt, three dilutions.
7. **Raising `--grain-opacity`** to make the texture "visible." If you can see
   it as texture, it's too strong.

---

## Open — needs a design decision, don't guess

- **Dark mode.** Kaolin has no dark equivalent. Fired stoneware or a dark slip
  is the honest answer, not an inverted cream. If dark mode is in scope, stop
  and ask.
- **Mobile sidebar.** The source Figma frame is desktop-only (1440×900) and
  specifies no mobile treatment.
- **Kami.** The companion is the same material with one cobalt brushstroke, and
  deliberately has **no face, no eyes, no limbs**. If a face gets added the
  material story collapses. Don't add one; raise it.
