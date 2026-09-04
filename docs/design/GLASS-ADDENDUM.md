# Noted — addendum: ink on frosted glass

This replaces the "cream paper" surface from CLAUDE-CODE-PROMPT.md. Everything typographic from that brief stays. Only the surface changes: Noted becomes a frosted pane laid over the desktop, and the fragments are things collected from what's underneath.

## 1. Window (Electron / macOS first)

```ts
new BrowserWindow({
  transparent: true,
  backgroundColor: '#00000000',
  vibrancy: 'under-window',          // try 'sidebar' if under-window is too dark on dark wallpapers
  visualEffectState: 'active',       // keep blur when window is inactive
  titleBarStyle: 'hiddenInset',
  frame: false,
})
// Windows: backgroundMaterial: 'acrylic' (fallback 'mica'), same CSS applies.
```

Use OS vibrancy for the blur. Do **not** add `backdrop-filter` to the window root or to every plate — one window-level blur is cheap; per-plate blur is not.

## 2. Surface tokens (override tokens.css)

```css
:root {
  --paper:        rgba(244, 240, 232, 0.62);   /* window tint over vibrancy — cream survives as a tint */
  --paper-plate:  rgba(248, 245, 239, 0.74);   /* plates: second pane, slightly more opaque */
  --plate-edge:   rgba(255, 255, 255, 0.55);   /* 1px top highlight = glass edge */
  --plate-inner:  rgba(255, 255, 255, 0.22);   /* inset 1px, optional */
  --ink:          #1C1B19;                     /* unchanged and 100% opaque, always */
  --ink-12:       rgba(28,27,25,.14);          /* hairlines slightly stronger on glass */
}
html { background: var(--paper); }
.plate {
  background: var(--paper-plate);
  border: 1px solid var(--ink-12);
  box-shadow: inset 0 1px 0 var(--plate-edge);   /* the ONE allowed shadow: an inset edge, not a drop */
}
```

Remove `paper-grain.svg`. Grain is a paper property. Replace with `assets/glass-sheen.svg` at 4% as a fixed overlay (a single diagonal soft highlight — reads as a pane catching light).

## 3. Legibility rules (non-negotiable)

- All ink is opaque. Meta text uses `--ink-55` *on top of the plate tint*, which is fine; never put text directly on the window tint outside a plate except the wordmark, title, breadcrumb and chrome.
- Worst case is a black wallpaper. Test with a solid `#000` desktop: the window tint must still yield ≥ 4.5:1 for body text and the title. If it doesn't, raise `--paper` alpha to 0.70; don't darken the ink.
- Test with a busy photo wallpaper: if plate text shimmers, raise `--paper-plate` alpha to 0.80. The plates may be more opaque than the window; that is the intended two-pane depth.
- Screenshot images inside capture plates keep their hairline frame; no transparency on images.

## 4. What glass changes elsewhere

- The ink blob and its splatter: unchanged. Opaque ink sitting on glass is the whole metaphor.
- Selected plate: hairline turns `--accent`; additionally raise its `--paper-plate` alpha to 0.86 (the pane "lifts" by getting more solid, not by shadow).
- Hover: hairline `--ink-12` → `--ink-30`, as before. No blur changes, no scale.
- Chrome icons stay 1px stroke `--ink-70`, sitting directly on the window tint.
- Inactive window: keep `visualEffectState: 'active'` so the pane doesn't go grey and flat.

## 5. Acceptance

- [ ] Window shows the desktop/apps behind it, blurred, with a warm tint — not grey macOS vibrancy.
- [ ] No `backdrop-filter` in the CSS.
- [ ] Only shadow in the DOM is the inset top edge on plates.
- [ ] Body text passes 4.5:1 against a black desktop and a white desktop.
- [ ] Splatter unchanged.
