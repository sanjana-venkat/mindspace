# Build prompt — Open Human "Mind" (Android prototype)

Paste into Google AI Studio. Written for a hackathon demo: one device, mock data, no backend.

---

Build an Android app in Kotlin with Jetpack Compose called **Mind**, by Open Human.

## What it is

A digital twin of your own memory — "Cmd+F for your brain." It holds everything a person has
seen, said and saved, and lets them get it back by talking to it: brainstorm, debate,
introspect, recall. This prototype is the retrieval half: a single character you talk to, and
the memory it is holding, arranged around it.

Use mock data throughout — no sign-in, no server. If a Gemini API key is available via
`GenerativeModel`, use `gemini-2.0-flash` for chat answers and summaries; otherwise fall back
to canned responses so the demo never stalls.

## Screens

### 1. Home — the moon

Full-bleed dark screen. Centred: a **luminous moon character** (supply as a drawable; a soft
cream sphere with a simple face, peach blush, cool violet rim light). It floats — never still.

Around it, at a radius of 140dp, a **ring gauge**: one arc segment per folder, each segment's
sweep proportional to how much of the memory that folder holds, separated by 4dp gaps. Think
a pie chart unrolled into a ring around the character. Each segment carries its folder's
colour, at 85% opacity, 10dp thick, rounded caps. Under the moon, quiet mono text: total
item count and "12 folders".

Behind everything, a slow **aurora**: four vertical sine-warped ribbons, heavily blurred,
drifting on independent phases.

Interactions:
- **Tap the moon** → listening state (screen 2).
- **Tap a ring segment** → that folder's bottom sheet (screen 3). The segment brightens and
  thickens to 14dp on press.
- **Search field** pinned to the bottom: a frosted capsule, "Ask your mind anything…". Typing
  and submitting goes to screen 4 with the query as the first message.

### 2. Listening

The moon scales up 1.15×, the aurora brightens, and a ring of audio-reactive bars pulses
around it in place of the folder gauge. Live partial transcript appears under the moon in
serif, greyed, replacing itself as it grows.

On silence, or on tapping the moon again, it resolves: the transcript commits and the app
routes to screen 4 with that utterance as the question. Mock the speech recognition with
Android's `SpeechRecognizer`, or fake it on a timer if permission is refused.

### 3. Folder sheet

A bottom sheet, rounded 28dp, frosted dark, that rises to 60% height. Header: folder name in
display type, item count in mono, and the folder's colour as a 3dp rule. Below, a list of
**topics** — each a row with a serif title, a one-line grey excerpt, and a mono timestamp.
Pull further up to expand to full height. Tapping a topic opens screen 4 for that topic.

### 4. Topic — summary and chat

Scrolling page. At the top, an **AI summary** of the topic in serif: two or three paragraphs,
with the sources it drew on listed underneath as small tinted chips (a screenshot, a voice
note, a meeting). Then the chat: alternating bubbles, the person's in a solid capsule aligned
right, the twin's as plain serif text aligned left with no bubble — it is the voice of the
memory, not a chat partner.

Pinned to the bottom, a chat bar with a mic button. Answers stream in. When an answer draws on
a stored item, show that item as a tappable chip under the answer ("from your screenshot,
14 Sep") that expands to a preview card.

## Design system

Dark by default. Use exactly these values.

**Colour**
```
ground     #0B0E0C      surface   #141A17      surface2  #1A211D
ink        #FFFFFF      ink2      #C9CFD8      ink3      #8B929C
line       #2A2F37      accent    #34D399      accentSoft #11291F
warning    #EBB34C      danger    #E25454
```
Folder tints, in order: `#34B07C` green, `#9270E0` violet, `#D09E4A` amber, `#488ADC` blue,
`#38B0BA` teal. Assign by stable hash of the folder name so a folder keeps its colour.

**Aurora** ribbons, bottom to top:
`#5C5CCC → #D954A3 → #F08FC2 → #54D68F → #54BDBD → #B8E07A`, blurred 38dp, over a night
`#0B0E1B → #0E1920`, with a vignette at black 34% / 12% / 22%. Draw with Compose `Canvas` and
a `RenderEffect` blur; each ribbon is a closed path between two offset sine curves, drifting
at a different slow speed.

**Type**
- Display: a heavy geometric face (Boldonse if available, else Archivo Black) at 0.78× size.
- UI: Hanken Grotesk, semibold by default.
- Prose: a serif — every summary, every answer, every note a person wrote.
- Mono: Geist Mono or JetBrains Mono, 9–11sp, uppercase, letter-spacing 0.06em, for labels,
  counts and timestamps.

The pairing carries meaning: **serif for what a person said, mono for what the machine
counted.** Never swap them.

**Material** Frosted panels: a translucent surface over the live aurora, a 5% white overlay,
a 28% white hairline. Over everything, a tiled noise grain at 12–20% opacity in `screen`
blend — without it the surfaces look like flat plastic.

**Shape** Panels 30dp, cards 26dp, sheets 28dp, tiles 16–18dp, every control a capsule.

## The moon's motion — get this exactly right

It is the product's character. Drive from a single time source, not from state changes:

```kotlin
val t = withInfiniteAnimationFrameMillis { it / 1000f }
bob    = sin(t * 1.15f) * 5.5f      // dp, vertical
sway   = sin(t * 0.63f + 1.1f) * 3f // dp, horizontal
tilt   = sin(t * 0.78f) * 2.4f      // degrees
breath = 1f + sin(t * 1.15f) * 0.018f
```

Under it, a contact shadow ellipse 46×9dp, blur 6dp, that **tightens and lightens as the moon
rises**: `alpha = 0.16 - bob * 0.008`, `width = 46 - bob * 0.9`. This is what makes it read as
hovering rather than sliding.

While listening, the moon tips back 9° and lifts 6dp — looking up at you.

Springs everywhere else: `spring(dampingRatio = 0.78f, stiffness = Spring.StiffnessMediumLow)`
for sheets and the ring, `0.82f` for cards arriving. Nothing bounces harder than that.
Transitions between screens are opacity and slight scale — never a slide.

## Mock data

Twelve folders with believable names (Research, Interviews, Ideas, Papers, Meetings, Recipes,
Trip planning…), each with 3–12 topics, each topic with a two-paragraph summary, 2–5 source
items of mixed kinds (screenshot, voice note, meeting, clipped text), and timestamps spread
over the last three months. Sizes should be visibly uneven so the ring gauge looks real.

## What the demo has to do, in order

1. Open on the floating moon inside its folder ring, aurora alive behind it.
2. Tap the moon, speak "what did I save about pricing?", watch the transcript appear.
3. Land on an answer in serif with a source chip; tap the chip, see the item.
4. Back out, tap a coloured segment, see that folder's topics rise in a sheet.
5. Open a topic, read the summary, ask a follow-up in the chat bar, get an answer.

Every screen must survive a cold start with no network. Build it so a single person can walk
through all five steps in ninety seconds without touching a keyboard except to type one query.
