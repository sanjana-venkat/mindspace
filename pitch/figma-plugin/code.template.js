// Mindspace pitch deck  ·  Open Human
// Builds 7 slide frames (1920x1080) as native, editable Figma layers.
// Run once: Plugins > Development > Mindspace Pitch Deck.

const ASSETS = "__ASSETS__";

/* ------------------------------------------------------------------ tokens */
const C = {
  night:  '#0A0D18',   // page top
  night2: '#0E1720',   // page foot
  panel:  '#121A27',
  panel2: '#18222F',
  line:   '#28313F',
  pearl:  '#F7F5F2',
  ink2:   '#C6CEDA',
  ink3:   '#8790A0',
  lav:    '#9270E0',
  lavSoft:'#B9A3F0',
  teal:   '#38B0BA',
  tealSoft:'#7EC4BE',
  amber:  '#D09E4A',
  green:  '#34B07C',
  blue:   '#488ADC'
};
const TINTS = [C.green, C.lav, C.amber, C.blue, C.teal];

// Folder shares. Deliberately lopsided: a real mind is not evenly divided.
const SHARES = [30, 14, 11, 9, 8, 7, 6, 5, 4, 3, 2, 1];

const W = 1920, H = 1080, M = 140, GAP = 180;
/// Where the first slide goes on a Design canvas: to the right of anything
/// already on the page, so building a deck never lands on top of existing work.
let BASE_X = 0;

/* ----------------------------------------------------------------- helpers */
function rgb(hex) {
  hex = hex.replace('#', '');
  return {
    r: parseInt(hex.slice(0, 2), 16) / 255,
    g: parseInt(hex.slice(2, 4), 16) / 255,
    b: parseInt(hex.slice(4, 6), 16) / 255
  };
}
function solid(hex, o) {
  const p = { type: 'SOLID', color: rgb(hex) };
  if (o !== undefined) p.opacity = o;
  return p;
}
function b64(str) {
  if (typeof figma.base64Decode === 'function') return figma.base64Decode(str);
  const tbl = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const clean = str.replace(/=+$/, '');
  const out = new Uint8Array((clean.length * 3) >> 2);
  let bits = 0, acc = 0, p = 0;
  for (let i = 0; i < clean.length; i++) {
    acc = (acc << 6) | tbl.indexOf(clean[i]);
    bits += 6;
    if (bits >= 8) { bits -= 8; out[p++] = (acc >> bits) & 0xff; }
  }
  return out;
}

const F = {};
async function pick(list) {
  for (const f of list) {
    try { await figma.loadFontAsync(f); return f; } catch (e) { /* next */ }
  }
  await figma.loadFontAsync({ family: 'Inter', style: 'Regular' });
  return { family: 'Inter', style: 'Regular' };
}

function T(parent, o) {
  const t = figma.createText();
  parent.appendChild(t);
  t.fontName = o.font || F.ui;
  t.characters = o.str;
  t.fontSize = o.size || 20;
  t.fills = [solid(o.color || C.pearl, o.opacity)];
  if (o.lh) t.lineHeight = { value: o.lh, unit: 'PIXELS' };
  if (o.ls !== undefined) t.letterSpacing = { value: o.ls, unit: 'PERCENT' };
  t.textAutoResize = o.w ? 'HEIGHT' : 'WIDTH_AND_HEIGHT';
  if (o.w) t.resize(o.w, t.height);
  if (o.align) t.textAlignHorizontal = o.align;
  t.x = o.x; t.y = o.y;
  t.name = o.name || (o.str.length > 28 ? o.str.slice(0, 28) + '...' : o.str);
  return t;
}

function R(parent, o) {
  const r = figma.createRectangle();
  parent.appendChild(r);
  r.resize(o.w, o.h);
  r.x = o.x; r.y = o.y;
  if (o.r !== undefined) r.cornerRadius = o.r;
  if (o.corners) {
    r.topLeftRadius = o.corners[0]; r.topRightRadius = o.corners[1];
    r.bottomRightRadius = o.corners[2]; r.bottomLeftRadius = o.corners[3];
  }
  r.fills = o.fill ? [solid(o.fill, o.fillOpacity)] : [];
  if (o.stroke) {
    r.strokes = [solid(o.stroke, o.strokeOpacity)];
    r.strokeWeight = o.strokeW || 1;
    r.strokeAlign = 'INSIDE';
  }
  if (o.dash) r.dashPattern = o.dash;
  if (o.opacity !== undefined) r.opacity = o.opacity;
  if (o.blend) r.blendMode = o.blend;
  if (o.effects) r.effects = o.effects;
  if (o.name) r.name = o.name;
  return r;
}

// Light, not shape. Big soft ellipse, screen blend, heavy blur.
function glow(parent, o) {
  const e = figma.createEllipse();
  parent.appendChild(e);
  const rx = o.rx, ry = o.ry || o.rx;
  e.resize(rx * 2, ry * 2);
  e.x = o.cx - rx; e.y = o.cy - ry;
  e.fills = [solid(o.hex)];
  e.opacity = o.opacity;
  e.blendMode = 'SCREEN';
  e.effects = [{ type: 'LAYER_BLUR', radius: Math.min(o.blur || 100, 100), visible: true }];
  e.name = 'aurora glow';
  return e;
}

// The recurring motif: folders as arcs around a centre.
function ring(parent, o) {
  const shares = o.shares || SHARES;
  const total = shares.reduce(function (s, x) { return s + x; }, 0);
  const gap = o.gapDeg === undefined ? 2.6 : o.gapDeg;
  const nodes = [];
  let a = o.startDeg === undefined ? -90 : o.startDeg;
  for (let i = 0; i < shares.length; i++) {
    const sweep = (shares[i] / total) * 360 - gap;
    const e = figma.createEllipse();
    parent.appendChild(e);
    e.resize(o.radius * 2, o.radius * 2);
    e.x = o.cx - o.radius; e.y = o.cy - o.radius;
    e.fills = [solid(o.color || TINTS[i % TINTS.length], o.segOpacity)];
    e.arcData = {
      startingAngle: a * Math.PI / 180,
      endingAngle: (a + sweep) * Math.PI / 180,
      innerRadius: (o.radius - o.thickness) / o.radius
    };
    e.name = 'folder arc ' + (i + 1);
    if (o.opacity !== undefined) e.opacity = o.opacity;
    nodes.push(e);
    a += sweep + gap;
  }
  return nodes;
}

let MOON_HASH = null, GRAIN_HASH = null;

// Figma Slides is a different editor: slides are SlideNodes in a grid, not
// frames you place on a canvas. Everything inside a slide is identical, so
// only the container differs.
const IS_SLIDES = figma.editorType === 'slides';
const MADE = [];

/// Properties that exist in one editor and not the other. Losing a corner
/// radius is not worth failing a build over.
function safe(fn) { try { fn(); } catch (e) { /* not available here */ } }

function moon(parent, o) {
  const r = figma.createRectangle();
  parent.appendChild(r);
  const w = o.size, h = o.size * (383 / 369);
  r.resize(w, h);
  r.x = o.cx - w / 2; r.y = o.cy - h / 2;
  r.fills = [{ type: 'IMAGE', scaleMode: 'FIT', imageHash: MOON_HASH }];
  r.name = 'moon';
  return r;
}

function grain(frame) {
  const r = figma.createRectangle();
  frame.appendChild(r);
  r.resize(frame.width, frame.height);
  r.x = 0; r.y = 0;
  r.fills = [{ type: 'IMAGE', scaleMode: 'TILE', scalingFactor: 0.5, imageHash: GRAIN_HASH }];
  r.opacity = 0.05;
  r.blendMode = 'SCREEN';
  r.name = 'grain';
  r.locked = true;
  return r;
}

// Pill label. Text is measured first, then the capsule is drawn behind it.
function chip(parent, o) {
  const t = T(parent, {
    x: 0, y: 0, str: o.str, font: o.font || F.mono,
    size: o.size || 13, color: o.color || C.teal, ls: o.ls === undefined ? 10 : o.ls
  });
  const padX = o.padX === undefined ? 16 : o.padX;
  const padY = o.padY === undefined ? 9 : o.padY;
  const rw = Math.round(t.width) + padX * 2, rh = Math.round(t.height) + padY * 2;
  const r = R(parent, {
    x: o.x, y: o.y, w: rw, h: rh, r: o.radius === undefined ? rh / 2 : o.radius,
    fill: o.fill, fillOpacity: o.fillOpacity,
    stroke: o.stroke === undefined ? (o.color || C.teal) : o.stroke,
    strokeOpacity: o.strokeOpacity === undefined ? 0.45 : o.strokeOpacity,
    name: 'chip'
  });
  parent.insertChild(parent.children.indexOf(t), r);
  t.x = o.x + padX; t.y = o.y + padY;
  return { w: rw, h: rh };
}

function eyebrow(parent, x, y, str, color) {
  return T(parent, {
    x: x, y: y, str: str, font: F.mono, size: 14,
    color: color || C.teal, ls: 16
  });
}

function hairline(parent, x, y, w, color, opacity) {
  return R(parent, {
    x: x, y: y, w: w, h: 1, fill: color || C.line,
    fillOpacity: opacity === undefined ? 1 : opacity, name: 'rule'
  });
}

/// A number we do not have yet, drawn so it cannot be mistaken for one we do.
function blank(parent, o) {
  R(parent, {
    x: o.x, y: o.y, w: o.w, h: o.h, r: 10,
    fill: C.panel, fillOpacity: 0.6, stroke: C.ink3, strokeOpacity: 0.8,
    strokeW: 1.5, dash: [8, 7], name: 'BLANK ' + (o.hint || '')
  });
  T(parent, {
    x: o.x, y: o.y + o.h / 2 - 9, w: o.w, align: 'CENTER',
    str: o.hint, font: F.mono, size: 12, color: C.ink3, ls: 8
  });
}

function slide(i, name) {
  let f;
  if (IS_SLIDES) {
    f = figma.createSlide();
    safe(function () { f.name = name; });
    if (Math.round(f.width) !== W || Math.round(f.height) !== H) {
      throw new Error(
        'This deck\u2019s slides are ' + Math.round(f.width) + ' by ' + Math.round(f.height) +
        '. The layout is drawn for 1920 by 1080. Set the deck size to 1920x1080 in ' +
        'the right hand panel, delete the slides this made, and run it again.'
      );
    }
  } else {
    f = figma.createFrame();
    figma.currentPage.appendChild(f);
    f.name = name;
    f.resize(W, H);
    f.x = BASE_X + i * (W + GAP); f.y = 0;
    safe(function () { f.clipsContent = true; });
  }
  MADE[i] = f;
  f.fills = [{
    type: 'GRADIENT_LINEAR',
    gradientTransform: [[0, 1, 0], [-1, 0, 1]],
    gradientStops: [
      { position: 0, color: Object.assign({}, rgb(C.night), { a: 1 }) },
      { position: 1, color: Object.assign({}, rgb(C.night2), { a: 1 }) }
    ]
  }];
  return f;
}

function notes(i, words, str) {
  if (IS_SLIDES) {
    // Slides has a real speaker notes field. If this build of Figma does not
    // expose it, the notes are still in SLIDES.md rather than lost.
    safe(function () { MADE[i].speakerNotes = str; });
    return;
  }
  const head = T(figma.currentPage, {
    x: BASE_X + i * (W + GAP), y: H + 70, str: 'SPEAKER NOTES  ·  ' + words + ' WORDS',
    font: F.mono, size: 16, color: '#7A8494', ls: 12
  });
  const body = T(figma.currentPage, {
    x: BASE_X + i * (W + GAP), y: H + 108, w: 1400, str: str,
    font: F.ui, size: 26, lh: 38, color: '#2A3342'
  });
  head.name = 'notes label'; body.name = 'speaker notes';
}

/// Appendix slides are not part of the two minutes, so they are labelled for
/// what they are: answers held in reserve.
function asideNotes(i, str) {
  if (IS_SLIDES) {
    safe(function () { MADE[i].speakerNotes = 'IF ASKED. ' + str; });
    return;
  }
  const head = T(figma.currentPage, {
    x: BASE_X + i * (W + GAP), y: H + 70, str: 'IF ASKED',
    font: F.mono, size: 16, color: '#7A8494', ls: 12
  });
  const body = T(figma.currentPage, {
    x: BASE_X + i * (W + GAP), y: H + 108, w: 1400, str: str,
    font: F.ui, size: 26, lh: 38, color: '#2A3342'
  });
  head.name = 'notes label'; body.name = 'if asked';
}

/* ------------------------------------------------------------------ slides */

function slide1() {
  const f = slide(0, '1 · Hook');
  const cx = 1370, cy = 540;

  glow(f, { cx: cx - 40, cy: cy - 30, rx: 420, hex: C.lav, opacity: 0.30, blur: 100 });
  glow(f, { cx: cx + 130, cy: cy + 160, rx: 300, hex: C.teal, opacity: 0.22, blur: 100 });
  glow(f, { cx: cx, cy: cy, rx: 190, hex: '#FFF3E4', opacity: 0.16, blur: 100 });

  ring(f, { cx: cx, cy: cy, radius: 306, thickness: 15, segOpacity: 0.92 });
  ring(f, { cx: cx, cy: cy, radius: 336, thickness: 2, segOpacity: 0.18, gapDeg: 2.6 });
  moon(f, { cx: cx, cy: cy, size: 286 });

  let y = 286;
  eyebrow(f, M, y, 'OPEN HUMAN');
  y += 54;
  T(f, { x: M, y: y, str: 'Mindspace', font: F.display, size: 74, color: C.pearl, ls: -1 });
  y += 148;
  const hero = T(f, {
    x: M, y: y, w: 800, str: 'Imagine you could\nCmd + F your brain.',
    font: F.serif, size: 66, lh: 82, color: C.pearl
  });
  y += hero.height + 40;
  T(f, { x: M, y: y, w: 700, str: 'A personal digital twin, grounded in what you capture, think and learn.', font: F.ui, size: 25, lh: 38, color: C.ink2 });

  hairline(f, M, 900, 220, C.teal, 0.5);
  T(f, { x: M, y: 924, str: 'OPEN HUMAN  ·  MINDSPACE', font: F.mono, size: 13, color: C.ink3, ls: 14 });

  grain(f);
  notes(0, 35, 'Everything you have ever saved is sitting somewhere on your devices. None of it is searchable the way your own thinking is. Mindspace is a personal digital twin. Imagine you could Command F your brain.');
}

function slide2() {
  const f = slide(1, '2 · The problem');

  glow(f, { cx: 1560, cy: 560, rx: 380, hex: C.lav, opacity: 0.13, blur: 100 });

  // Scattered, unjoined arcs. Collected, not connected.
  const scatter = [6, 3, 9, 2, 5, 4, 8, 3, 2, 6, 3, 4];
  ring(f, { cx: 1560, cy: 560, radius: 300, thickness: 12, shares: scatter, gapDeg: 12, segOpacity: 0.5, startDeg: -70 });
  ring(f, { cx: 1560, cy: 560, radius: 218, thickness: 8, shares: [4, 2, 7, 3, 5, 2, 6, 3], gapDeg: 18, segOpacity: 0.3, startDeg: 30 });
  ring(f, { cx: 1560, cy: 560, radius: 130, thickness: 5, shares: [3, 6, 2, 5], gapDeg: 26, segOpacity: 0.2, startDeg: 110 });

  let y = 196;
  eyebrow(f, M, y, 'THE PROBLEM', C.ink3);
  y += 58;
  const head = T(f, {
    x: M, y: y, w: 1140, str: 'We collect everything.\nWe return to almost none of it.',
    font: F.h, size: 56, lh: 70, color: C.pearl, ls: -1.5
  });
  y += head.height + 46;

  const kinds = ['LECTURE SLIDES', 'READINGS', 'VOICE NOTES', 'HALF FORMED THOUGHTS'];
  let cx2 = M;
  for (let i = 0; i < kinds.length; i++) {
    const s = chip(f, {
      x: cx2, y: y, str: kinds[i], size: 12, color: C.ink2,
      stroke: C.line, strokeOpacity: 1, fill: C.panel, fillOpacity: 0.5
    });
    cx2 += s.w + 14;
  }
  y += 88;

  const qs = [
    'What did I save?',
    'Why did it matter?',
    'How does it connect to what I am thinking about now?'
  ];
  for (let i = 0; i < qs.length; i++) {
    R(f, { x: M, y: y + 6, w: 3, h: 34, r: 2, fill: C.teal, fillOpacity: 0.7, name: 'rule' });
    T(f, { x: M + 26, y: y, w: 900, str: qs[i], font: F.serifIt, size: 32, lh: 46, color: C.pearl, opacity: 0.94 });
    y += 66;
  }

  y += 40;
  T(f, { x: M, y: y, w: 860, str: 'The gap is not storage. It is return.', font: F.ui, size: 21, color: C.ink3 });

  grain(f);
  notes(1, 38, 'We screenshot, we take notes, we record voice memos, then it sits there. The gap is not storage, it is return. What did I save, why did it matter, how does it connect to what I am working on now?');
}

function slide3() {
  const f = slide(2, '3 · The belief');

  glow(f, { cx: 1700, cy: 540, rx: 440, hex: C.lav, opacity: 0.16, blur: 100 });
  glow(f, { cx: 1820, cy: 760, rx: 300, hex: C.teal, opacity: 0.12, blur: 100 });
  ring(f, { cx: 1780, cy: 540, radius: 430, thickness: 12, segOpacity: 0.5, opacity: 0.55 });
  ring(f, { cx: 1780, cy: 540, radius: 330, thickness: 3, segOpacity: 0.25, opacity: 0.5, startDeg: 40 });

  let y = 196;
  eyebrow(f, M, y, 'THE BELIEF');
  y += 62;
  const q = T(f, {
    x: M, y: y, w: 1020, str: 'Use AI to preserve\nhuman intelligence.',
    font: F.serif, size: 68, lh: 84, color: C.pearl
  });
  y += q.height + 44;

  const body = T(f, {
    x: M, y: y, w: 880,
    str: 'Storing what we read is easy. Keeping the thinking around it is not. Your questions, your objections and your interpretations deserve to be preserved beside the things you saved.',
    font: F.ui, size: 24, lh: 38, color: C.ink2
  });
  y += body.height + 46;

  T(f, { x: M, y: y, str: 'A TWIN YOU CAN', font: F.mono, size: 12, color: C.ink3, ls: 14 });
  y += 34;
  const verbs = ['brainstorm with', 'debate', 'learn from', 'reflect against'];
  let vx = M;
  for (let i = 0; i < verbs.length; i++) {
    const s = chip(f, {
      x: vx, y: y, str: verbs[i], font: F.uiMed, size: 17, ls: 0,
      color: C.tealSoft, stroke: C.teal, strokeOpacity: 0.4,
      fill: C.teal, fillOpacity: 0.09, padX: 20, padY: 11
    });
    vx += s.w + 12;
  }
  y += 96;

  hairline(f, M, y, 760, C.line, 1);
  T(f, {
    x: M, y: y + 22, w: 820,
    str: 'A digital twin here is an evolving reflection of the knowledge and thoughts you choose to share. It is not a copy of you.',
    font: F.mono, size: 13, lh: 22, color: C.ink3
  });

  grain(f);
  notes(2, 35, 'Open Human exists to preserve human intelligence. Not only what you read, but what you thought about it. Your twin is an evolving reflection of the knowledge you choose to share. Something to think with.');
}

function slide4() {
  const f = slide(3, '4 · The foundation');
  glow(f, { cx: 960, cy: 980, rx: 620, ry: 260, hex: C.teal, opacity: 0.10, blur: 100 });

  let y = 180;
  chip(f, { x: M, y: y, str: 'CURRENT PRODUCT', size: 12, color: C.green, stroke: C.green, strokeOpacity: 0.5, fill: C.green, fillOpacity: 0.1 });
  y += 74;
  T(f, { x: M, y: y, str: 'First, capture and organize.', font: F.h, size: 58, color: C.pearl, ls: -1.5 });
  y += 90;
  T(f, { x: M, y: y, w: 900, str: 'Mindspace runs on macOS today.', font: F.ui, size: 22, color: C.ink2 });

  const panelY = 430, pw = 490, ph = 420;
  const xs = [M, M + pw + 85, M + (pw + 85) * 2];
  const titles = ['Capture', 'Organize', 'Summarize'];
  const nums = ['01', '02', '03'];

  for (let i = 0; i < 3; i++) {
    const p = R(f, {
      x: xs[i], y: panelY, w: pw, h: ph, r: 24,
      fill: C.panel, fillOpacity: 0.85, stroke: C.line, name: 'panel ' + titles[i]
    });
    p.effects = [{ type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a: 0.32 }, offset: { x: 0, y: 14 }, radius: 34, spread: 0, visible: true, blendMode: 'NORMAL' }];
    T(f, { x: xs[i] + 32, y: panelY + 30, str: nums[i], font: F.mono, size: 12, color: C.teal, ls: 14 });
    T(f, { x: xs[i] + 32, y: panelY + 58, str: titles[i], font: F.h, size: 30, color: C.pearl });
    hairline(f, xs[i] + 32, panelY + 112, pw - 64, C.line, 1);
  }

  // 01 capture
  const sources = ['slides and screens', 'lectures and seminars', 'spoken thoughts', 'readings and links'];
  for (let i = 0; i < sources.length; i++) {
    const ry = panelY + 146 + i * 52;
    R(f, { x: xs[0] + 32, y: ry + 8, w: 9, h: 9, r: 5, fill: TINTS[i % TINTS.length], name: 'dot' });
    T(f, { x: xs[0] + 54, y: ry, str: sources[i], font: F.ui, size: 20, color: C.ink2 });
  }

  // 02 organize
  const folders = [['Cognitive Psych', '24'], ['Research Methods', '18'], ['Readings', '31'], ['Half ideas', '7']];
  for (let i = 0; i < folders.length; i++) {
    const ry = panelY + 140 + i * 56;
    R(f, { x: xs[1] + 32, y: ry, w: pw - 64, h: 44, r: 12, fill: C.panel2, stroke: C.line, name: 'folder row' });
    R(f, { x: xs[1] + 46, y: ry + 17, w: 10, h: 10, r: 5, fill: TINTS[i % TINTS.length], name: 'tint' });
    T(f, { x: xs[1] + 68, y: ry + 11, str: folders[i][0], font: F.uiMed, size: 18, color: C.pearl });
    T(f, { x: xs[1] + 32, y: ry + 14, w: pw - 82, align: 'RIGHT', str: folders[i][1], font: F.mono, size: 14, color: C.ink3 });
  }

  // 03 summarize
  T(f, { x: xs[2] + 32, y: panelY + 140, str: 'AI SUMMARY', font: F.mono, size: 11, color: C.teal, ls: 14 });
  for (let i = 0; i < 3; i++) {
    R(f, { x: xs[2] + 32, y: panelY + 170 + i * 20, w: (pw - 64) * [1, 0.94, 0.62][i], h: 8, r: 4, fill: C.ink2, fillOpacity: 0.3, name: 'summary line' });
  }
  hairline(f, xs[2] + 32, panelY + 250, pw - 64, C.line, 1);
  T(f, { x: xs[2] + 32, y: panelY + 272, str: 'YOUR NOTES', font: F.mono, size: 11, color: C.lavSoft, ls: 14 });
  for (let i = 0; i < 2; i++) {
    R(f, { x: xs[2] + 32, y: panelY + 302 + i * 20, w: (pw - 64) * [0.88, 0.5][i], h: 8, r: 4, fill: C.pearl, fillOpacity: 0.55, name: 'note line' });
  }
  T(f, { x: xs[2] + 32, y: panelY + 356, w: pw - 64, str: 'Your words sit beside the summary, never replaced by it.', font: F.ui, size: 15, lh: 22, color: C.ink3 });
  T(f, { x: xs[0] + 32, y: panelY + 356, w: pw - 64, str: 'A keyboard shortcut, or the moon sitting on your desktop.', font: F.ui, size: 15, lh: 22, color: C.ink3 });
  T(f, { x: xs[1] + 32, y: panelY + 356, w: pw - 64, str: 'Drag between folders. Search looks inside the captures.', font: F.ui, size: 15, lh: 22, color: C.ink3 });

  // connectors
  for (let i = 0; i < 2; i++) {
    const ax = xs[i] + pw + 30;
    hairline(f, ax, panelY + ph / 2, 25, C.ink3, 0.5);
  }

  T(f, { x: M, y: 908, w: 1300, str: 'Illustration of the current product, not a screenshot. Summaries use your own Gemini API key.', font: F.mono, size: 13, color: C.ink3, lh: 20 });

  grain(f);
  notes(3, 34, 'Today Mindspace runs on Mac. It captures screens, audio and thoughts, files them into folders, and with your own Gemini key writes a summary that sits beside your own notes. That part is shipping.');
}

function phoneShell(f, x, y, w, h) {
  const s = R(f, { x: x, y: y, w: w, h: h, r: 42, fill: '#0B121C', stroke: C.line, name: 'phone' });
  s.effects = [{ type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a: 0.45 }, offset: { x: 0, y: 20 }, radius: 44, spread: 0, visible: true, blendMode: 'NORMAL' }];
  R(f, { x: x + w / 2 - 34, y: y + 14, w: 68, h: 5, r: 3, fill: C.pearl, fillOpacity: 0.16, name: 'notch' });
  return s;
}

function slide5() {
  const f = slide(4, '5 · The experience');

  glow(f, { cx: 480, cy: 620, rx: 340, hex: C.lav, opacity: 0.17, blur: 100 });
  glow(f, { cx: 1480, cy: 660, rx: 340, hex: C.teal, opacity: 0.13, blur: 100 });

  chip(f, { x: M, y: 150, str: 'MOBILE PROTOTYPE CONCEPT', size: 12, color: C.lavSoft, stroke: C.lav, strokeOpacity: 0.5, fill: C.lav, fillOpacity: 0.12 });
  T(f, { x: M, y: 214, str: 'Then, talk to what you know.', font: F.h, size: 58, color: C.pearl, ls: -1.5 });

  const pw = 360, ph = 700, py = 300;
  const xs = [300, 780, 1260];

  /* --- A: moon home ------------------------------------------------ */
  let x = xs[0];
  phoneShell(f, x, py, pw, ph);
  const acx = x + pw / 2, acy = py + 300;
  glow(f, { cx: acx, cy: acy, rx: 150, hex: C.lav, opacity: 0.34, blur: 100 });
  glow(f, { cx: acx, cy: acy + 40, rx: 110, hex: C.teal, opacity: 0.22, blur: 100 });
  T(f, { x: x + 28, y: py + 44, str: '9:41', font: F.mono, size: 12, color: C.ink3 });
  T(f, { x: x, y: py + 44, w: pw - 28, align: 'RIGHT', str: '12 FOLDERS', font: F.mono, size: 12, color: C.ink3, ls: 12 });
  ring(f, { cx: acx, cy: acy, radius: 128, thickness: 9, segOpacity: 0.95 });
  moon(f, { cx: acx, cy: acy, size: 124 });
  T(f, { x: x, y: py + 470, w: pw, align: 'CENTER', str: 'TAP THE MOON AND TALK', font: F.mono, size: 12, color: C.tealSoft, ls: 14 });
  T(f, { x: x + 40, y: py + 510, w: pw - 80, align: 'CENTER', str: 'Each arc is a folder, sized by how much of your mind lives in it.', font: F.ui, size: 14, lh: 21, color: C.ink3 });
  R(f, { x: x + 30, y: py + ph - 92, w: pw - 60, h: 52, r: 26, fill: C.panel2, stroke: C.line, name: 'ask bar' });
  T(f, { x: x + 52, y: py + ph - 76, str: 'ask your mindspace', font: F.ui, size: 16, color: C.ink3 });
  R(f, { x: x + pw - 74, y: py + ph - 80, w: 28, h: 28, r: 14, fill: C.teal, name: 'mic' });

  /* --- B: folder sheet --------------------------------------------- */
  x = xs[1];
  phoneShell(f, x, py, pw, ph);
  const bcx = x + pw / 2;
  glow(f, { cx: bcx, cy: py + 150, rx: 110, hex: C.lav, opacity: 0.16, blur: 100 });
  ring(f, { cx: bcx, cy: py + 150, radius: 74, thickness: 6, segOpacity: 0.5, opacity: 0.55 });
  moon(f, { cx: bcx, cy: py + 150, size: 68 }).opacity = 0.55;

  const sy = py + 290;
  R(f, { x: x, y: sy, w: pw, h: ph - (sy - py), corners: [28, 28, 42, 42], fill: C.panel, name: 'bottom sheet' });
  R(f, { x: bcx - 22, y: sy + 14, w: 44, h: 4, r: 2, fill: C.ink3, fillOpacity: 0.6, name: 'handle' });
  R(f, { x: x + 28, y: sy + 46, w: 11, h: 11, r: 6, fill: C.lav, name: 'tint' });
  T(f, { x: x + 48, y: sy + 38, str: 'Cognitive Psych', font: F.h, size: 23, color: C.pearl });
  T(f, { x: x + 28, y: sy + 76, str: '18 SAVED  ·  6 TOPICS', font: F.mono, size: 11, color: C.ink3, ls: 12 });
  hairline(f, x + 28, sy + 108, pw - 56, C.line, 1);

  const topics = [['Correlation is not causation', '4'], ['Memory and encoding', '6'], ['Research methods', '5'], ['Seminar 9, the bits I missed', '2'], ['Exam 2, likely themes', '3']];
  for (let i = 0; i < topics.length; i++) {
    const ty = sy + 126 + i * 56;
    if (i === 0) R(f, { x: x + 16, y: ty - 8, w: pw - 32, h: 46, r: 12, fill: C.lav, fillOpacity: 0.12, name: 'selected' });
    T(f, { x: x + 28, y: ty, w: pw - 90, str: topics[i][0], font: F.uiMed, size: 16, color: i === 0 ? C.pearl : C.ink2 });
    T(f, { x: x, y: ty + 2, w: pw - 28, align: 'RIGHT', str: topics[i][1], font: F.mono, size: 13, color: C.ink3 });
  }

  /* --- C: topic summary -------------------------------------------- */
  x = xs[2];
  phoneShell(f, x, py, pw, ph);
  T(f, { x: x + 28, y: py + 42, str: 'Cognitive Psych', font: F.mono, size: 12, color: C.ink3, ls: 10 });
  T(f, { x: x + 28, y: py + 76, w: pw - 56, str: 'Correlation is not causation', font: F.serif, size: 25, lh: 33, color: C.pearl });
  T(f, { x: x + 28, y: py + 156, str: 'AI SUMMARY', font: F.mono, size: 11, color: C.tealSoft, ls: 14 });
  T(f, { x: x + 28, y: py + 182, w: pw - 56, str: 'You saved this four times: twice from slides, twice in your own words. The second time you got it right.', font: F.serif, size: 16, lh: 26, color: C.ink2 });

  T(f, { x: x + 28, y: py + 292, str: 'FROM', font: F.mono, size: 10, color: C.ink3, ls: 14 });
  const srcs = ['lecture 9 slides', 'your voice note', 'seminar 14 Sep'];
  let sx = x + 28, srow = 0;
  for (let i = 0; i < srcs.length; i++) {
    const s = chip(f, { x: sx, y: py + 316 + srow * 34, str: srcs[i], font: F.mono, size: 11, ls: 2, color: C.tealSoft, stroke: C.teal, strokeOpacity: 0.4, fill: C.teal, fillOpacity: 0.1, padX: 10, padY: 6 });
    sx += s.w + 8;
    if (i === 1) { sx = x + 28; srow = 1; }
  }

  hairline(f, x + 28, py + 400, pw - 56, C.line, 1);
  T(f, { x: x + 28, y: py + 422, str: 'YOUR NOTES', font: F.mono, size: 11, color: C.lavSoft, ls: 14 });
  T(f, { x: x + 28, y: py + 448, w: pw - 56, str: '"So a correlation can be strong and still tell you nothing about cause."', font: F.serifIt, size: 16, lh: 26, color: C.pearl });

  const follow = ['quiz me on this', 'where am I still shaky?'];
  let fy = py + 520;
  for (let i = 0; i < follow.length; i++) {
    chip(f, { x: x + 28, y: fy, str: follow[i], font: F.ui, size: 14, ls: 0, color: C.ink2, stroke: C.line, strokeOpacity: 1, fill: C.panel2, padX: 14, padY: 9 });
    fy += 44;
  }
  R(f, { x: x + 24, y: py + ph - 86, w: pw - 48, h: 50, r: 25, fill: C.panel2, stroke: C.line, name: 'chat bar' });
  T(f, { x: x + 46, y: py + ph - 71, str: 'ask a follow up', font: F.ui, size: 15, color: C.ink3 });
  R(f, { x: x + pw - 66, y: py + ph - 77, w: 32, h: 32, r: 16, fill: C.lav, name: 'send' });

  const caps = ['Home. Folders as arcs, voice at the centre.', 'Tap an arc for its topics.', 'Tap a topic for summary, sources, chat.'];
  for (let i = 0; i < 3; i++) {
    T(f, { x: xs[i], y: py + ph + 20, w: pw, align: 'CENTER', str: caps[i], font: F.ui, size: 14, lh: 20, color: C.ink3 });
  }

  grain(f);
  notes(4, 43, 'This is what we are prototyping. Folders become arcs around the moon, sized by how much of your mind lives in each. Tap the moon and talk. Tap an arc for topics. Tap a topic for a summary, your notes, and a chat bar.');
}

function slide6() {
  const f = slide(5, '6 · One use case');
  glow(f, { cx: 1500, cy: 300, rx: 360, hex: C.lav, opacity: 0.12, blur: 100 });
  ring(f, { cx: 1880, cy: 170, radius: 280, thickness: 10, segOpacity: 0.45, opacity: 0.5 });

  chip(f, { x: M, y: 150, str: 'ILLUSTRATIVE SCENARIO', size: 12, color: C.amber, stroke: C.amber, strokeOpacity: 0.5, fill: C.amber, fillOpacity: 0.1 });
  T(f, { x: M, y: 212, str: 'From recall to thinking.', font: F.h, size: 54, color: C.pearl, ls: -1.5 });

  let y = 330;
  const colW = 1180;

  // 1 · the ask
  const u1 = T(f, { x: M + colW - 620 + 24, y: y + 22, w: 572, str: 'What did I save about correlation and causation?', font: F.ui, size: 21, lh: 31, color: C.pearl });
  const u1h = u1.height + 44;
  const u1r = R(f, { x: M + colW - 620, y: y, w: 620, h: u1h, r: 22, fill: C.panel2, stroke: C.line, name: 'you' });
  f.insertChild(f.children.indexOf(u1), u1r);
  T(f, { x: M + colW - 620, y: y - 26, w: 620, align: 'RIGHT', str: 'YOU', font: F.mono, size: 11, color: C.ink3, ls: 14 });
  y += u1h + 34;

  // 2 · what came back, with its source attached
  const rBody = T(f, { x: M + 30, y: y + 52, w: 820, str: '"Correlational studies measure how two variables relate, without controlling either one. That is not the same as cause."', font: F.serifIt, size: 24, lh: 36, color: C.pearl });
  const rh = rBody.height + 86;
  const rCard = R(f, { x: M, y: y, w: 880, h: rh, r: 20, fill: C.teal, fillOpacity: 0.07, stroke: C.teal, strokeOpacity: 0.35, name: 'retrieved' });
  f.insertChild(f.children.indexOf(rBody), rCard);
  const rRule = R(f, { x: M, y: y, w: 3, h: rh, r: 2, fill: C.teal, name: 'source rule' });
  f.insertChild(f.children.indexOf(rBody), rRule);
  T(f, { x: M + 30, y: y + 22, str: 'RETRIEVED FROM YOUR NOTES  ·  SEMINAR, 14 SEP', font: F.mono, size: 11, color: C.tealSoft, ls: 14 });
  y += rh + 30;

  // 3 · the interpretation
  T(f, { x: M + 30, y: y, str: 'MINDSPACE', font: F.mono, size: 11, color: C.lavSoft, ls: 14 });
  const a1 = T(f, { x: M + 30, y: y + 26, w: 860, str: 'You wrote this after the seminar, in your own words. The lecture slide you saved an hour earlier says it less clearly.', font: F.serif, size: 23, lh: 34, color: C.ink2 });
  R(f, { x: M, y: y, w: 3, h: a1.height + 30, r: 2, fill: C.lav, fillOpacity: 0.7, name: 'ai rule' });
  y += a1.height + 60;

  // 4 · the turn
  const u2 = T(f, { x: M + colW - 620 + 24, y: y + 22, w: 572, str: 'Quiz me on it.', font: F.ui, size: 21, lh: 31, color: C.pearl });
  const u2h = u2.height + 44;
  const u2r = R(f, { x: M + colW - 620, y: y, w: 620, h: u2h, r: 22, fill: C.panel2, stroke: C.line, name: 'you' });
  f.insertChild(f.children.indexOf(u2), u2r);
  y += u2h + 30;

  T(f, { x: M + 30, y: y, str: 'MINDSPACE', font: F.mono, size: 11, color: C.lavSoft, ls: 14 });
  const a2 = T(f, { x: M + 30, y: y + 26, w: 860, str: 'Find me an example from your own readings where a correlation was reported as a cause. I will wait.', font: F.serif, size: 23, lh: 34, color: C.ink2 });
  R(f, { x: M, y: y, w: 3, h: a2.height + 30, r: 2, fill: C.lav, fillOpacity: 0.7, name: 'ai rule' });

  // legend
  const lx = 1420, ly = 700;
  T(f, { x: lx, y: ly, str: 'HOW TO READ THIS', font: F.mono, size: 11, color: C.ink3, ls: 14 });
  R(f, { x: lx, y: ly + 34, w: 14, h: 14, r: 4, fill: C.teal, name: 'key' });
  T(f, { x: lx + 26, y: ly + 30, w: 340, str: 'Retrieved from your own saved material', font: F.ui, size: 16, lh: 24, color: C.ink2 });
  R(f, { x: lx, y: ly + 76, w: 14, h: 14, r: 4, fill: C.lav, name: 'key' });
  T(f, { x: lx + 26, y: ly + 72, w: 340, str: 'Mindspace interpretation, grounded in it', font: F.ui, size: 16, lh: 24, color: C.ink2 });
  T(f, { x: lx, y: ly + 140, w: 360, str: 'An illustrative scenario, not a recorded result.', font: F.mono, size: 12, lh: 20, color: C.ink3 });

  grain(f);
  notes(5, 38, 'Here is the shift. First you ask for something you half remember, and it comes back with the original note attached, so you can see where the answer came from. Then you ask it to argue with you.');
}

function slide7() {
  const f = slide(6, '7 · Team and close');

  glow(f, { cx: 1520, cy: 360, rx: 380, hex: C.lav, opacity: 0.20, blur: 100 });
  glow(f, { cx: 1620, cy: 510, rx: 260, hex: C.teal, opacity: 0.14, blur: 100 });
  ring(f, { cx: 1560, cy: 372, radius: 244, thickness: 11, segOpacity: 0.85 });
  moon(f, { cx: 1560, cy: 372, size: 190 });

  let y = 196;
  eyebrow(f, M, y, 'THE TEAM');
  y += 64;

  const team = [
    ['Sanjana Venkat', 'Growth Designer at Jefit', 'Previously Senior Product Designer at JPMorgan Chase. Psychology, product design, conversational AI and rapid prototyping.'],
    ['Abishek Sridhar', 'ML Engineer at Google DeepMind', 'Machine learning engineering, systems and evaluation.']
  ];
  for (let i = 0; i < team.length; i++) {
    T(f, { x: M, y: y, str: team[i][0], font: F.h, size: 38, color: C.pearl, ls: -1 });
    T(f, { x: M, y: y + 52, str: team[i][1], font: F.uiMed, size: 21, color: C.tealSoft });
    const d = T(f, { x: M, y: y + 88, w: 700, str: team[i][2], font: F.ui, size: 17, lh: 27, color: C.ink3 });
    y += 88 + d.height + 54;
  }
  T(f, { x: M, y: y - 16, str: 'Affiliations are listed as team credentials only.', font: F.mono, size: 12, color: C.ink3 });

  // close
  T(f, {
    x: 1080, y: 700, w: 720,
    str: 'Your knowledge.\nYour perspective.\nA mindspace to grow both.',
    font: F.serif, size: 44, lh: 60, color: C.pearl
  });

  // demo placeholder, clearly marked
  R(f, { x: M, y: 828, w: 190, h: 190, r: 18, fill: C.panel, stroke: C.ink3, strokeOpacity: 0.7, strokeW: 2, dash: [10, 8], name: 'PLACEHOLDER demo QR' });
  T(f, { x: M, y: 898, w: 190, align: 'CENTER', str: 'DEMO LINK\nOR QR', font: F.mono, size: 13, lh: 22, color: C.ink3, ls: 10 });
  T(f, { x: M + 214, y: 890, w: 300, str: 'Placeholder. Drop in the demo link or QR before the pitch.', font: F.ui, size: 16, lh: 24, color: C.ink3 });

  hairline(f, 1080, 940, 720, C.teal, 0.5);
  T(f, { x: 1080, y: 962, str: 'OPEN HUMAN  ·  MINDSPACE', font: F.mono, size: 14, color: C.ink2, ls: 16 });

  grain(f);
  notes(6, 29, 'Sanjana designs growth at Jefit, previously JPMorgan Chase, with a psychology background. Abishek is a machine learning engineer at DeepMind. Your knowledge, your perspective, a mindspace to grow both.');
}

/* ---------------------------------------------------------------- appendix */

function slideA1() {
  const f = slide(7, 'A1 · Market and model');
  glow(f, { cx: 1700, cy: 880, rx: 420, hex: C.teal, opacity: 0.10, blur: 100 });
  ring(f, { cx: 1990, cy: 120, radius: 290, thickness: 10, segOpacity: 0.4, opacity: 0.4 });

  eyebrow(f, M, 180, 'APPENDIX  ·  A1', C.ink3);
  T(f, { x: M, y: 226, str: 'Market and model', font: F.h, size: 54, color: C.pearl, ls: -1.5 });

  // why now
  T(f, { x: M, y: 350, str: 'WHY NOW', font: F.mono, size: 12, color: C.teal, ls: 14 });
  const now = [
    ['On-device speech became free and private.', 'Parakeet runs locally. No API call, no upload, no per-minute cost.'],
    ['Long context made a whole folder readable at once.', 'Asking "what was I circling here" stopped being expensive.']
  ];
  let y = 386;
  for (let i = 0; i < now.length; i++) {
    R(f, { x: M, y: y + 6, w: 3, h: 26, r: 2, fill: C.teal, fillOpacity: 0.7, name: 'rule' });
    T(f, { x: M + 24, y: y, w: 700, str: now[i][0], font: F.uiMed, size: 22, lh: 30, color: C.pearl });
    const d = T(f, { x: M + 24, y: y + 36, w: 700, str: now[i][1], font: F.ui, size: 17, lh: 26, color: C.ink3 });
    y += 36 + d.height + 34;
  }

  // privacy, stated only as far as the product actually goes today
  T(f, { x: M, y: 566, str: 'PRIVACY, AS BUILT', font: F.mono, size: 12, color: C.lavSoft, ls: 14 });
  const priv = [
    ['Speech never leaves the laptop.', 'Parakeet runs on-device. No API call at all.'],
    ['Summaries can stay local too.', 'Through a local model, today. Going further is what we want to fund.']
  ];
  let py2 = 602;
  for (let i = 0; i < priv.length; i++) {
    R(f, { x: M, y: py2 + 6, w: 3, h: 24, r: 2, fill: C.lav, fillOpacity: 0.7, name: 'rule' });
    T(f, { x: M + 24, y: py2, w: 700, str: priv[i][0], font: F.uiMed, size: 20, lh: 28, color: C.pearl });
    const d = T(f, { x: M + 24, y: py2 + 32, w: 700, str: priv[i][1], font: F.ui, size: 16, lh: 24, color: C.ink3 });
    py2 += 32 + d.height + 26;
  }

  // sizing, bottom up, with the numbers left out on purpose
  const sx = 1010;
  T(f, { x: sx, y: 350, str: 'SIZING, BOTTOM UP', font: F.mono, size: 12, color: C.amber, ls: 14 });
  const rows = [
    ['Students enrolled at one university', 'HEADCOUNT'],
    ['What a student will actually pay', 'PRICE A MONTH'],
    ['One campus, serviceable', 'PRODUCT OF THE TWO']
  ];
  for (let i = 0; i < rows.length; i++) {
    const ry = 390 + i * 74;
    T(f, { x: sx, y: ry + 16, w: 460, str: rows[i][0], font: F.ui, size: 19, color: C.ink2 });
    blank(f, { x: sx + 480, y: ry, w: 290, h: 52, hint: rows[i][1] });
  }
  T(f, {
    x: sx, y: 626, w: 770,
    str: 'Enrolment is public. Take it from the university\u2019s own factbook, or IPEDS, or HESA. Do not say a number out loud that you have not checked yourself.',
    font: F.mono, size: 12.5, lh: 21, color: C.ink3
  });

  // the model
  hairline(f, M, 760, W - M * 2, C.line, 1);
  T(f, { x: M, y: 786, str: 'THE MODEL', font: F.mono, size: 12, color: C.lavSoft, ls: 14 });
  const model = [
    ['Free to start', 'Capture and organize on the machine. This is how it reaches a cohort.'],
    ['Tiers by memory', 'You pay as your mindspace grows. More to hold, further back to recall.'],
    ['A private tier', 'Everything through a local model, for material that cannot leave the laptop.'],
    ['Opt in, and later', 'Consented simulation for research and evaluation, with a share paid back.']
  ];
  for (let i = 0; i < model.length; i++) {
    const mx = M + i * 412;
    const accent = i === 3 ? C.ink3 : C.pearl;
    T(f, { x: mx, y: 822, str: model[i][0], font: F.uiMed, size: 20, color: accent });
    T(f, { x: mx, y: 852, w: 370, str: model[i][1], font: F.ui, size: 15.5, lh: 23, color: C.ink3 });
  }
  T(f, {
    x: M, y: 956, w: 1640,
    str: 'Students do not pay and institutions are slow, so adoption comes first and revenue second. The fourth column is an option we are exploring, not a plan: nothing about a person is sold, simulated or otherwise, unless they opted in and were paid for it.',
    font: F.mono, size: 12, lh: 20, color: C.ink3
  });

  grain(f);
  asideNotes(7, 'Lead with tiers by memory. Privacy is not a promise here, it is already built: speech runs on-device and summaries can too. If anyone asks about the fourth column, say it is opt in, paid, and not how the company works today, then go back to subscriptions. Do not let it become the headline.');
}

function slideA2() {
  const f = slide(8, 'A2 · Where we sit');
  glow(f, { cx: 1560, cy: 420, rx: 380, hex: C.lav, opacity: 0.13, blur: 100 });

  eyebrow(f, M, 180, 'APPENDIX  ·  A2', C.ink3);
  T(f, { x: M, y: 226, str: 'Where we sit', font: F.h, size: 54, color: C.pearl, ls: -1.5 });

  T(f, { x: M, y: 372, str: 'THE ANSWER TO "ISN\u2019T THIS NOTEBOOKLM"', font: F.mono, size: 12, color: C.teal, ls: 14 });
  T(f, {
    x: M, y: 408, w: 700,
    str: '"That answers from documents you were handed. This answers from what you saved and what you thought, and then asks the question back."',
    font: F.serifIt, size: 26, lh: 39, color: C.pearl
  });
  T(f, {
    x: M, y: 628, w: 680,
    str: 'A tool that does the thinking produces a student who cannot. The retrieval is the point, not the summary. Every other tool here either hands you an answer or hands you back a file.',
    font: F.ui, size: 18, lh: 28, color: C.ink2
  });
  T(f, {
    x: M, y: 880, w: 680,
    str: 'Categories, not a claim about where any particular product is heading.',
    font: F.mono, size: 12, lh: 20, color: C.ink3
  });

  // the matrix
  const cx = 1320, cy = 600, half = 300;
  hairline(f, cx - half, cy, half * 2, C.line, 1);
  R(f, { x: cx, y: cy - half, w: 1, h: half * 2, fill: C.line, name: 'rule' });

  T(f, { x: cx - half, y: cy - half - 46, w: half * 2, align: 'CENTER', str: 'YOUR OWN WORDS', font: F.mono, size: 11, color: C.ink3, ls: 12 });
  T(f, { x: cx - half, y: cy + half + 26, w: half * 2, align: 'CENTER', str: 'MATERIAL YOU WERE GIVEN', font: F.mono, size: 11, color: C.ink3, ls: 12 });
  T(f, { x: cx - half - 250, y: cy - 10, w: 230, align: 'RIGHT', str: 'THINKS FOR YOU', font: F.mono, size: 11, color: C.ink3, ls: 12 });
  T(f, { x: cx + half + 18, y: cy - 10, w: 250, str: 'MAKES YOU THINK', font: F.mono, size: 11, color: C.ink3, ls: 12 });

  const plots = [
    [-235, 195, 'general AI chat', 'ChatGPT, Gemini', false],
    [-170, 75, 'source chat', 'NotebookLM', false],
    [-235, -150, 'note apps', 'Notion, Obsidian', false],
    [150, 165, 'drill tools', 'Quizlet, Anki', false],
    [165, -180, 'Mindspace', 'your material, your recall', true]
  ];
  for (let i = 0; i < plots.length; i++) {
    const px = cx + plots[i][0], py = cy + plots[i][1], me = plots[i][4];
    if (me) glow(f, { cx: px, cy: py, rx: 92, hex: C.teal, opacity: 0.4, blur: 60 });
    R(f, { x: px - (me ? 8 : 5), y: py - (me ? 8 : 5), w: me ? 16 : 10, h: me ? 16 : 10, r: 8, fill: me ? C.teal : C.ink3, name: 'point' });
    T(f, { x: px + 18, y: py - 19, str: plots[i][2], font: me ? F.h : F.uiMed, size: me ? 21 : 17, color: me ? C.pearl : C.ink2 });
    T(f, { x: px + 18, y: py + (me ? 8 : 4), str: plots[i][3], font: F.mono, size: 11.5, color: C.ink3, ls: 4 });
  }

  grain(f);
  asideNotes(8, 'Say the quote and stop talking. If they push on learning science, retrieval practice and the testing effect are the ground you are standing on. Check the Roediger and Karpicke paper yourself before you cite it by name.');
}

function slideA3() {
  const f = slide(9, 'A3 · Next twelve months');
  glow(f, { cx: 960, cy: 1000, rx: 700, ry: 260, hex: C.lav, opacity: 0.11, blur: 100 });

  eyebrow(f, M, 180, 'APPENDIX  ·  A3', C.ink3);
  T(f, { x: M, y: 226, str: 'The next twelve months', font: F.h, size: 54, color: C.pearl, ls: -1.5 });
  T(f, { x: M, y: 306, w: 1100, str: 'Students adopt it, departments pay for it. Each phase proves one thing, and if it does not, we have learned that cheaply.', font: F.ui, size: 20, color: C.ink2 });

  const py = 400, pw = 490, ph = 380;
  const xs = [M, M + pw + 85, M + (pw + 85) * 2];
  const phases = [
    ['NOW', 'One course', 'Get it into a single cohort for a whole semester, free.', 'That it survives a real term, not a demo.', 'STUDENTS IN THE PILOT'],
    ['NEXT', 'Revision week', 'The twin, at the moment it matters most. Ask, and be asked back.', 'That they come back when the exam is close.', 'RETURN RATE, REVISION WEEK'],
    ['THEN', 'The department', 'Teachers keep their own, and students choose what to hand in.', 'That someone with a budget wants it too.', 'DEPARTMENTS IN TALKS']
  ];

  for (let i = 0; i < 3; i++) {
    const p = R(f, { x: xs[i], y: py, w: pw, h: ph, r: 24, fill: C.panel, fillOpacity: 0.85, stroke: C.line, name: 'phase ' + phases[i][1] });
    p.effects = [{ type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a: 0.3 }, offset: { x: 0, y: 12 }, radius: 30, spread: 0, visible: true, blendMode: 'NORMAL' }];
    T(f, { x: xs[i] + 32, y: py + 28, str: phases[i][0], font: F.mono, size: 12, color: [C.green, C.teal, C.lavSoft][i], ls: 14 });
    T(f, { x: xs[i] + 32, y: py + 56, str: phases[i][1], font: F.h, size: 28, color: C.pearl });
    hairline(f, xs[i] + 32, py + 106, pw - 64, C.line, 1);
    T(f, { x: xs[i] + 32, y: py + 128, w: pw - 64, str: phases[i][2], font: F.ui, size: 17, lh: 26, color: C.ink2 });
    T(f, { x: xs[i] + 32, y: py + 216, str: 'IT PROVES', font: F.mono, size: 10.5, color: C.ink3, ls: 14 });
    T(f, { x: xs[i] + 32, y: py + 238, w: pw - 64, str: phases[i][3], font: F.serif, size: 17, lh: 25, color: C.pearl });
    blank(f, { x: xs[i] + 32, y: py + 306, w: pw - 64, h: 46, hint: phases[i][4] });
  }

  hairline(f, M, 850, W - M * 2, C.line, 1);
  T(f, { x: M, y: 878, str: 'WHAT WE ARE LOOKING FOR', font: F.mono, size: 12, color: C.amber, ls: 14 });
  blank(f, { x: M, y: 908, w: 1000, h: 56, hint: 'THE ASK. USERS, ADVICE, MONEY. SAY WHICH' });
  T(f, { x: M + 1030, y: 918, w: 610, str: 'Decide this before you walk on. An ask left vague is the one thing judges remember.', font: F.mono, size: 12, lh: 20, color: C.ink3 });

  grain(f);
  asideNotes(9, 'One cohort, then revision week, then a department with a budget. The blanks are deliberate: fill them once, in your own hand, rather than inventing a number on stage.');
}


/* ------------------------------------------------------------ vision deck */
// The long-term direction, kept apart from the pitch: everything here is
// where OpenHuman is going, not what Mindspace does today, and it says so.

function visionHeader(f, eyebrowText, title, color) {
  eyebrow(f, M, 150, eyebrowText, color || C.teal);
  return T(f, { x: M, y: 192, w: 1400, str: title, font: F.h, size: 56, lh: 66, color: C.pearl, ls: -1.5 });
}

function columnCards(f, y, cols, h) {
  const n = cols.length, gap = 40;
  const w = (W - M * 2 - gap * (n - 1)) / n;
  for (let i = 0; i < n; i++) {
    const x = M + i * (w + gap);
    const c = cols[i];
    R(f, { x: x, y: y, w: w, h: h, r: 22, fill: C.panel, fillOpacity: 0.85, stroke: C.line, name: 'card ' + c[1] });
    T(f, { x: x + 32, y: y + 30, str: c[0], font: F.mono, size: 12, color: c[3] || C.teal, ls: 14 });
    T(f, { x: x + 32, y: y + 60, w: w - 64, str: c[1], font: F.h, size: 28, lh: 34, color: C.pearl });
    T(f, { x: x + 32, y: y + 116, w: w - 64, str: c[2], font: F.ui, size: 18, lh: 28, color: C.ink2 });
  }
}

function vision1() {
  const f = slide(0, 'V1 · Help me remember');
  const cx = 1460, cy = 540;
  glow(f, { cx: cx, cy: cy, rx: 380, hex: C.lav, opacity: 0.22, blur: 100 });
  glow(f, { cx: cx + 120, cy: cy + 140, rx: 260, hex: C.teal, opacity: 0.16, blur: 100 });
  ring(f, { cx: cx, cy: cy, radius: 250, thickness: 12, segOpacity: 0.9 });
  moon(f, { cx: cx, cy: cy, size: 230 });

  eyebrow(f, M, 286, 'OPEN HUMAN  ·  WHERE THIS IS GOING');
  const t = T(f, { x: M, y: 330, w: 900, str: 'Help me remember.', font: F.serif, size: 84, lh: 96, color: C.pearl });
  T(f, { x: M, y: 330 + t.height + 36, w: 760,
         str: 'Most AI memory tries to make machines remember more. We want to make sure people don’t remember less.',
         font: F.ui, size: 26, lh: 40, color: C.ink2 });
  hairline(f, M, 900, 220, C.teal, 0.5);
  T(f, { x: M, y: 924, str: 'A VISION, NOT A FEATURE LIST', font: F.mono, size: 13, color: C.ink3, ls: 14 });
  grain(f);
  notes(0, 52, 'Mindspace started as a way to Cmd + F your brain. Where we are going is harder and more human. If AI can remember everything for us, it should also know when to hand us the answer, and when to help us find it ourselves. That is the company we want to build.');
}

function vision2() {
  const f = slide(1, 'V2 · Where we are');
  visionHeader(f, 'WHERE WE ARE  ·  SHIPPING TODAY', 'Today, Mindspace remembers for you.', C.green);
  columnCards(f, 380, [
    ['01  CAPTURE', 'Keep what you see and hear', 'Screens, highlighted text, voice and meetings, each with the thought you had about it.', C.green],
    ['02  ORGANIZE', 'Topics on a ring', 'Notes gather into topics around the moon, written up by AI beside your own words.', C.green],
    ['03  ASK', 'Answers with sources', 'Questions are answered only from what you saved, and every answer points to its capture.', C.green]
  ], 330);
  T(f, { x: M, y: 770, w: 1500, str: 'That is the foundation. It is also the trap.', font: F.serifIt, size: 34, color: C.pearl });
  grain(f);
  notes(1, 41, 'Today the product captures what you see and hear, keeps the thought you had about it, and answers questions only from what you saved, with the source attached. That is a real, shipping foundation. It is also the trap, and that is where the vision starts.');
}

function vision3() {
  const f = slide(2, 'V3 · The trap');
  visionHeader(f, 'THE PROBLEM WITH PERFECT RECALL', 'An answer every time is a memory never used.', C.amber);
  T(f, { x: M, y: 290, w: 1150, str: 'Every time a tool remembers for you, you skip the act that makes a memory stick. A perfect second brain can quietly weaken the first one.',
         font: F.ui, size: 24, lh: 38, color: C.ink2 });
  const cards = [
    ['Forgetting is not erasing.', 'What fades is usually still stored, and comes back faster the second time you learn it.', 'EBBINGHAUS'],
    ['Stored is not the same as reachable.', 'A memory can be held strongly and still be hard to reach. Reaching for it is what strengthens it.', 'BJORK']
  ];
  for (let i = 0; i < 2; i++) {
    const x = M + i * 840, y = 470;
    R(f, { x: x, y: y, w: 800, h: 300, r: 22, fill: C.amber, fillOpacity: 0.06, stroke: C.amber, strokeOpacity: 0.3, name: 'finding' });
    T(f, { x: x + 36, y: y + 34, str: cards[i][2], font: F.mono, size: 12, color: C.amber, ls: 14 });
    T(f, { x: x + 36, y: y + 66, w: 728, str: cards[i][0], font: F.serif, size: 36, lh: 46, color: C.pearl });
    T(f, { x: x + 36, y: y + 170, w: 728, str: cards[i][1], font: F.ui, size: 20, lh: 30, color: C.ink2 });
  }
  T(f, { x: M, y: 830, w: 1500, str: 'Established findings from memory research, named so anyone can look them up.', font: F.mono, size: 13, color: C.ink3 });
  grain(f);
  notes(2, 47, 'Here is the trap. Every time a tool answers for you, you skip the effort that makes memories stick. Memory research has known this for a century. Forgetting is not erasing, and a memory you can reach for gets stronger every time you do. Remembering for people can quietly make them worse at it.');
}

function vision4() {
  const f = slide(3, 'V4 · The recall dial');
  visionHeader(f, 'THE RECALL DIAL', 'You choose how much it remembers for you.');
  const stops = ['Just tell me', 'Recognize', 'Cue me', 'Guide me', 'Challenge me', 'Make me remember'];
  const y = 400, x0 = M + 60, x1 = W - M - 60;
  R(f, { x: x0, y: y, w: x1 - x0, h: 6, r: 3, fill: C.line, name: 'dial track' });
  const grad = R(f, { x: x0, y: y, w: x1 - x0, h: 6, r: 3, fill: C.teal, name: 'dial fill' });
  grad.fills = [{ type: 'GRADIENT_LINEAR', gradientTransform: [[1, 0, 0], [0, 1, 0]],
                  gradientStops: [{ position: 0, color: Object.assign({}, rgb(C.teal), { a: 1 }) },
                                  { position: 1, color: Object.assign({}, rgb(C.lav), { a: 1 }) }] }];
  for (let i = 0; i < stops.length; i++) {
    const sx = x0 + (x1 - x0) * i / (stops.length - 1);
    const lit = i === 2;
    R(f, { x: sx - (lit ? 13 : 9), y: y + 3 - (lit ? 13 : 9), w: lit ? 26 : 18, h: lit ? 26 : 18, r: 13,
           fill: lit ? C.pearl : C.panel2, stroke: lit ? C.pearl : C.ink3, strokeOpacity: 0.8, strokeW: 2, name: 'stop' });
    T(f, { x: sx - 110, y: y + 36, w: 220, align: 'CENTER', str: stops[i], font: lit ? F.uiMed : F.ui, size: 18, color: lit ? C.pearl : C.ink2 });
  }
  T(f, { x: x0 - 20, y: y - 52, str: 'REMEMBER FOR ME', font: F.mono, size: 12, color: C.tealSoft, ls: 14 });
  T(f, { x: x1 - 260, y: y - 52, w: 280, align: 'RIGHT', str: 'HELP ME REMEMBER', font: F.mono, size: 12, color: C.lavSoft, ls: 14 });

  const ex = [
    ['YOU', 'What was the psychologist behind the forgetting curve?', C.ink2],
    ['CUE ME', '“You read about him while researching the recall dial.”', C.tealSoft],
    ['GUIDE ME', '“His name starts with E.”', C.tealSoft],
    ['CHALLENGE ME', '“Ebb_____”', C.lavSoft],
    ['YOU', 'Ebbinghaus.', C.pearl]
  ];
  let ey = 560;
  for (let i = 0; i < ex.length; i++) {
    T(f, { x: M + 60, y: ey + 6, w: 200, str: ex[i][0], font: F.mono, size: 12, color: C.ink3, ls: 12 });
    T(f, { x: M + 280, y: ey, w: 1300, str: ex[i][1], font: i === 0 || i === 4 ? F.ui : F.serifIt, size: 24, lh: 32, color: ex[i][2] });
    ey += 62;
  }
  T(f, { x: M + 60, y: ey + 14, w: 1500, str: 'Each step gives a little more, only as much as you need. Illustrative exchange.', font: F.mono, size: 13, color: C.ink3 });
  grain(f);
  notes(3, 56, 'So we are building a dial. At one end it just tells you. At the other it makes you remember, and guides you there. In between it can let you recognize the answer, give you a cue, or challenge you. You choose how hard it should be, and it gives the smallest nudge that works.');
}

function vision5() {
  const f = slide(4, 'V5 · Why it works');
  visionHeader(f, 'WHY IT WORKS', 'Each step is grounded in how memory works.');
  const items = [
    ['Retrieval practice', 'Recalling something strengthens it more than reading it again.'],
    ['Desirable difficulty', 'Effort helps learning, as long as you can still succeed.'],
    ['Generation', 'An answer you produce sticks better than one you are handed.'],
    ['Context', 'Where you were when you learned something can bring it back.'],
    ['Spacing', 'Returning just before you would forget is the most efficient time.']
  ];
  const w = 300, gap = 30;
  for (let i = 0; i < items.length; i++) {
    const x = M + i * (w + gap);
    R(f, { x: x, y: 330, w: w, h: 360, r: 22, fill: C.panel, fillOpacity: 0.85, stroke: C.line, name: 'principle' });
    T(f, { x: x + 28, y: 360, str: String(i + 1).padStart(2, '0'), font: F.mono, size: 12, color: C.teal, ls: 14 });
    T(f, { x: x + 28, y: 392, w: w - 56, str: items[i][0], font: F.h, size: 26, lh: 32, color: C.pearl });
    T(f, { x: x + 28, y: 470, w: w - 56, str: items[i][1], font: F.ui, size: 18, lh: 28, color: C.ink2 });
  }
  T(f, { x: M, y: 760, w: 1500, str: 'Each is established on its own. How they combine for one person is what we want to learn.',
         font: F.serifIt, size: 30, lh: 40, color: C.pearl });
  grain(f);
  notes(4, 52, 'None of this is guesswork. Recalling strengthens memory more than rereading. Effort helps if you can still succeed. Answers you produce stick better. Context brings memories back. Spacing is the most efficient way to keep them. Each is well established. How they combine for one real person is the open question.');
}

function vision6() {
  const f = slide(5, 'V6 · Three layers');
  visionHeader(f, 'THREE LAYERS', 'Remember for me. Help me remember. Remember me.');
  columnCards(f, 340, [
    ['01  DIGITAL MEMORY', 'Remember for me', 'Your captures, plus the sources you choose to connect: your email, the newsletters you meant to read.', C.tealSoft],
    ['02  HUMAN MEMORY', 'Help me remember', 'The recall dial. It learns which cues work for you, and when to ask instead of answer.', C.lavSoft],
    ['03  YOUR SIGNATURE', 'Remember me', 'How you write, decide and think, kept on your machine and carried into the AI you already use.', C.amber]
  ], 380);
  grain(f);
  notes(5, 45, 'That gives us three layers. Remember for me is the archive, your captures and the sources you connect. Help me remember is the dial, learning what cues work for you. Remember me is your signature, how you think and speak, kept locally and carried wherever you use AI.');
}

function vision7() {
  const f = slide(6, 'V7 · Your signature');
  visionHeader(f, 'YOUR SIGNATURE', 'Stop re-prompting AI to sound like you.');
  T(f, { x: M, y: 290, w: 1200,
         str: 'Connect Mindspace to Claude or ChatGPT and it brings your context and your voice with it. You stop correcting it, because it already knows how you speak and what you mean.',
         font: F.ui, size: 24, lh: 38, color: C.ink2 });
  const pts = [
    ['Yours', 'Built only from what you chose to keep and connect.'],
    ['Local', 'Lives on your machine. You decide what leaves it.'],
    ['Portable', 'Shared with the AI you use through MCP, an open protocol for giving models context.']
  ];
  for (let i = 0; i < 3; i++) {
    const y = 470 + i * 120;
    R(f, { x: M, y: y + 8, w: 4, h: 64, r: 2, fill: C.amber, fillOpacity: 0.8, name: 'rule' });
    T(f, { x: M + 30, y: y, str: pts[i][0], font: F.serif, size: 36, color: C.pearl });
    T(f, { x: M + 30, y: y + 48, w: 1200, str: pts[i][1], font: F.ui, size: 20, lh: 30, color: C.ink2 });
  }
  grain(f);
  notes(6, 44, 'The third layer is the one people feel first. Today you keep re-prompting AI to sound like you. Your signature fixes that. It is built from what you chose to keep, it stays on your machine, and it travels to the AI you already use through an open protocol.');
}

function vision8() {
  const f = slide(7, 'V8 · The research');
  glow(f, { cx: 1500, cy: 520, rx: 420, hex: C.lav, opacity: 0.14, blur: 100 });
  visionHeader(f, 'THE RESEARCH', 'A model of how one person remembers.');
  T(f, { x: M, y: 290, w: 1100,
         str: 'Every time someone uses the dial we can learn which cue unlocked a memory, how long it took, and how sure they were. Over years that becomes a model of one person’s memory, not just their data.',
         font: F.ui, size: 24, lh: 38, color: C.ink2 });
  const sig = ['Which cue worked', 'How long it took', 'How much help they asked for', 'How confident they were', 'How long since they last saw it', 'Whether they remembered it wrongly'];
  for (let i = 0; i < sig.length; i++) {
    const col = i % 2, row = Math.floor(i / 2);
    chip(f, { x: M + col * 440, y: 470 + row * 64, str: sig[i], font: F.ui, size: 18, ls: 0,
              color: C.lavSoft, stroke: C.lav, strokeOpacity: 0.35, fill: C.lav, fillOpacity: 0.08, padX: 20, padY: 11 });
  }
  T(f, { x: M, y: 720, w: 1500,
         str: '“How does one person’s memory behave across thousands of real experiences, over years?”',
         font: F.serifIt, size: 34, lh: 46, color: C.pearl });
  T(f, { x: M, y: 860, str: 'That model is the hard part to copy.', font: F.mono, size: 14, color: C.ink3, ls: 8 });
  grain(f);
  notes(7, 46, 'This is the research. Each time someone uses the dial we learn something about how their memory works: which cue helped, how long it took, how sure they were. Over years that becomes a model of one person’s memory. That is very hard to copy.');
}

function vision9() {
  const f = slide(8, 'V9 · Now, next, later');
  visionHeader(f, 'NOW  ·  NEXT  ·  LATER', 'One layer at a time.');
  columnCards(f, 340, [
    ['NOW', 'Remember for me', 'Capture, topics, and asking with sources. Shipping on macOS today.', C.green],
    ['NEXT', 'Help me remember', 'The recall dial, and connecting the sources you choose, starting with email.', C.tealSoft],
    ['LATER', 'Remember me', 'A personal memory model, and your signature carried into the AI you use.', C.lavSoft]
  ], 300);
  T(f, { x: M, y: 700, w: 1500, str: 'Each layer is useful on its own, and each one makes the next one possible.',
         font: F.serifIt, size: 30, lh: 40, color: C.pearl });
  grain(f);
  notes(8, 36, 'We build it one layer at a time. Remember for me is shipping now. Help me remember comes next, with the dial and connected sources. Remember me comes after. Each layer is useful alone, and each makes the next possible.');
}

function vision10() {
  const f = slide(9, 'V10 · The question');
  const cx = 1500, cy = 620;
  glow(f, { cx: cx, cy: cy, rx: 300, hex: C.lav, opacity: 0.2, blur: 100 });
  ring(f, { cx: cx, cy: cy, radius: 190, thickness: 10, segOpacity: 0.85 });
  moon(f, { cx: cx, cy: cy, size: 170 });
  eyebrow(f, M, 220, 'THE QUESTION WE ARE BUILDING AROUND');
  T(f, { x: M, y: 270, w: 1050,
         str: 'If AI can remember everything for us, how should it decide what to tell us, and what to help us remember ourselves?',
         font: F.serif, size: 54, lh: 70, color: C.pearl });
  hairline(f, M, 900, 220, C.teal, 0.5);
  T(f, { x: M, y: 924, str: 'OPEN HUMAN  ·  MINDSPACE', font: F.mono, size: 14, color: C.ink2, ls: 16 });
  grain(f);
  notes(9, 33, 'So this is the question we are building around. If AI can remember everything for us, how should it decide what to tell us, and what to help us remember ourselves? We think answering that well is a company.');
}

/* -------------------------------------------------------------------- main */

// Errors go into a window that stays open, because a toast disappears before
// you can read it and "it says error" is not something anyone can debug.
function report(step, err) {
  const msg = (err && err.message) ? err.message : String(err);
  const stack = (err && err.stack) ? String(err.stack).slice(0, 900) : '';
  figma.showUI(
    '<body style="font:13px -apple-system,sans-serif;padding:18px;color:#111">' +
    '<h3 style="margin:0 0 10px">Mindspace deck: build failed</h3>' +
    '<p style="margin:0 0 6px"><b>Step:</b> ' + step + '</p>' +
    '<p style="margin:0 0 12px"><b>Error:</b> ' + msg + '</p>' +
    '<pre style="background:#f3f3f3;padding:10px;border-radius:6px;white-space:pre-wrap;' +
    'font:11px ui-monospace,monospace;max-height:220px;overflow:auto">' + stack + '</pre>' +
    '<p style="color:#666;margin:12px 0 0">Copy this and send it back.</p></body>',
    { width: 460, height: 380 }
  );
}

async function main() {
  let step = 'loading fonts';
  try {
    F.display = await pick([{ family: 'Boldonse', style: 'Regular' }, { family: 'Hanken Grotesk', style: 'ExtraBold' }, { family: 'Inter', style: 'Bold' }]);
    F.h       = await pick([{ family: 'Hanken Grotesk', style: 'Bold' }, { family: 'Inter', style: 'Bold' }]);
    F.uiMed   = await pick([{ family: 'Hanken Grotesk', style: 'Medium' }, { family: 'Inter', style: 'Medium' }]);
    F.ui      = await pick([{ family: 'Hanken Grotesk', style: 'Regular' }, { family: 'Inter', style: 'Regular' }]);
    F.serif   = await pick([{ family: 'Newsreader', style: 'Regular' }, { family: 'Lora', style: 'Regular' }, { family: 'Georgia', style: 'Regular' }]);
    F.serifIt = await pick([{ family: 'Newsreader', style: 'Italic' }, { family: 'Lora', style: 'Italic' }, { family: 'Georgia', style: 'Italic' }]);
    F.mono    = await pick([{ family: 'Geist Mono', style: 'Regular' }, { family: 'IBM Plex Mono', style: 'Regular' }, { family: 'Roboto Mono', style: 'Regular' }]);

    step = 'decoding images';
    MOON_HASH = figma.createImage(b64(ASSETS.moon)).hash;
    GRAIN_HASH = figma.createImage(b64(ASSETS.grain)).hash;

    // Two decks, one per menu item. The vision deck is kept separate from
    // the pitch so nothing in it can be mistaken for what ships today.
    const isVision = figma.command === 'vision';
    if (!IS_SLIDES) {
      let right = 0;
      figma.currentPage.children.forEach(function (n) { right = Math.max(right, n.x + n.width); });
      BASE_X = figma.currentPage.children.length ? Math.ceil(right + 400) : 0;
    }
    const builders = isVision
      ? [vision1, vision2, vision3, vision4, vision5, vision6, vision7, vision8, vision9, vision10]
      : [slide1, slide2, slide3, slide4, slide5, slide6, slide7, slideA1, slideA2, slideA3];
    for (let i = 0; i < builders.length; i++) {
      step = 'building slide ' + (i + 1);
      builders[i]();
    }

    step = 'framing the view';
    if (!IS_SLIDES) {
      const frames = figma.currentPage.children.filter(function (n) { return n.type === 'FRAME'; });
      safe(function () { figma.viewport.scrollAndZoomIntoView(frames); });
    }
    const what = isVision ? 'Vision deck' : 'Mindspace deck';
    figma.closePlugin(
      IS_SLIDES
        ? what + ' built. ' + builders.length + ' slides, speaker notes on each.'
        : what + ' built. ' + builders.length + ' frames, speaker notes under each.'
    );
  } catch (e) {
    report(step, e);
  }
}

main();
