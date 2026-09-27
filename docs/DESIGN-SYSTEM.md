# Mindspace design system

Every value here is taken from the shipping macOS app, not approximated. Hex values are the
sRGB equivalents of the source's 0–255 and 0–1 components.

## Palette

Two modes. The app pins setup to dark and lets the workspace follow the system.

| Token | Light | Dark | Used for |
|---|---|---|---|
| `ground` | `#E9EAE7` | `#0B0E0C` | The page itself |
| `surface` | `#FFFFFF` | `#141A17` | Cards, sheets |
| `surface2` | `#EEF0EC` | `#1A211D` | Fields, chips, wells |
| `ink` | `#101410` | `#FFFFFF` | Primary text |
| `ink2` | `#59635A` | `#C9CFD8` | Secondary text |
| `ink3` | `#8B948B` | `#8B929C` | Labels, captions |
| `line` | `#D6DBD3` | `#2A2F37` | Hairlines, borders |
| `accent` | `#0E6D55` | `#34D399` | Affirmatives, live state |
| `accentSoft` | `#DCEFE7` | `#11291F` | Accent backgrounds |
| `solid` / `onSolid` | `#101410` on `#E9EAE7` | `#FFFFFF` on `#0E1013` | Primary buttons |
| `warning` | `#B07618` | `#EBB34C` | Stale, out of date |
| `danger` | `#B03034` | `#E25454` | Destructive only |
| `deep` | `#253340` | `#121A20` | Deep washes |

**Folder tints** — five, assigned by stable hash so a folder keeps its colour forever:

| | Light | Dark |
|---|---|---|
| green | `#76AF92` | `#34B07C` |
| violet | `#B096C4` | `#9270E0` |
| amber | `#DEC58C` | `#D09E4A` |
| blue | `#7298BA` | `#488ADC` |
| teal | `#7EC4BE` | `#38B0BA` |

## Typography

| Role | Face | Notes |
|---|---|---|
| Display | Boldonse Regular | Rendered at **0.78×** the nominal size — it runs large |
| Title | Hanken Grotesk, bold | |
| UI | Hanken Grotesk | Default semibold; regular and medium for secondary |
| Prose | System serif | Every thought, note and write-up. The app's voice |
| Mono | Geist Mono | Labels, timestamps, counts. Usually 9–11pt, tracking 0.6–1.4, uppercase |

The pairing is the point: **serif for what a person wrote, mono for what the machine counted.**

## Materials

- **Frosted glass** over the live background for every panel: system ultra-thin material, a
  5% white overlay, a 28% white hairline.
- **Grain** on everything: a 220px tiled noise texture, `screen` blend in dark at 20%,
  `multiply` in light at 20%; 12% over panels. Without it the surfaces read as flat plastic.
- **Light mode is snow**, not grey: a near-white vertical gradient `#F5F7F9 → #FDFDFD` with a
  soft white drift at the foot. No colour cast — an earlier green wash tinted the whole UI.

## Shape and depth

| Element | Radius | Shadow |
|---|---|---|
| Onboarding panel | 30 | black 20%, radius 36, y 14 |
| Card / recording panel | 26 | black 20–34%, radius 26, y 12 |
| Toast, confirm, prompt | 22 | black 30–34%, radius 30–40, y 14–18 |
| Note tile, field well | 16–18 | black 12–20%, radius 18–30 |
| Controls | Capsule | black 13–22%, radius 10–24 |

## The moon

The character. A soft luminous sphere with a face, four poses (idle, holding a folder,
catching, pleased-with-notepad), drawn as PNGs with transparent surrounds and a warm peach
blush. Body is cream-white; the rim carries a cool violet-blue.

**It is never still.** Three out-of-phase sines, driven from wall-clock time:

```
bob    = sin(t · 1.15) · 5.5pt      vertical
sway   = sin(t · 0.63 + 1.1) · 3pt  horizontal
tilt   = sin(t · 0.78) · 2.4°       rotation
breath = 1 + sin(t · 1.15) · 0.018  scale
```

The contact shadow underneath — an ellipse 46×9, blur 6 — **tightens and lightens as it
rises** (`opacity 0.16 − bob · 0.008`, `width 46 − bob · 0.9`). That is what sells the hover;
without it the moon reads as a sticker sliding around.

**Held still while dragged.** All four terms go to zero, scale to 1.04. A figure drifting on
its own sine under a pointer that is also moving it reads as broken.

**Hover tips it back** −9° and lifts it 6pt, as though looking up at what just appeared.

## The ring

Actions fan out of the moon on an arc when hovered.

- Radius **74pt**, icons in **32pt** circles of frosted glass with a hairline.
- Default arc **168° → 12°** (over the moon). Against the right edge of the screen it swings
  to a vertical arc on the left (118° → 242°), against the left edge to the right (62° → −62°),
  against the top it hangs below (192° → 348°).
- Labels sit **98pt** out, on the icon's own side, black capsules with mono 9.5 uppercase,
  tracking 1.
- Two-step for compound actions: capture → *full window* / *partial shot*; audio → *your
  audio* / *system audio*.
- Leaving gets a **650ms grace period** before the ring folds, so crossing the gap between the
  moon and an icon is not a cliff.

## The aurora

Four vertical ribbons, each a sine-warped band, drawn in one canvas and blurred **38pt** (46 on
light) so they read as light rather than shapes. Colours, bottom to top:

`#5C5CCC violet → #D954A3 magenta → #F08FC2 pink → #54D68F green → #54BDBD teal → #B8E07A lime`

over a night of `#0B0E1B` deepening to `#0E1920`, with a vignette at `black 34% / 12% / 22%`.
Ribbons drift on independent slow phases; nothing loops visibly.

**Capture flourish** — when something is caught, three ribbons bloom along the top of the
screen and two along the foot, `plusLighter`, blur 34, over ~1.15s with a fast-in slow-out
envelope (in over the first 22%, out over the remaining 78%). Green-teal for a capture,
blue-violet and longer for a recording starting.

## Motion

| Gesture | Spring |
|---|---|
| Panels, sheets, ring | `response 0.34, damping 0.78` |
| Cards arriving | `response 0.44, damping 0.82` |
| Folder focus | `response 0.45, damping 0.86` |
| Small state changes | `smooth 0.16–0.3s` |

Nothing eases linearly, nothing bounces past 0.86 damping. Transitions between steps are
**opacity only** — the landscape behind does the travelling.

## Voice

Labels are lowercase sentences, not Title Case Commands. "Everything you want to remember."
"What were you thinking when you saved this?" Destructive actions say what goes and what
stays. Errors say what happened and offer the fix as a button.
