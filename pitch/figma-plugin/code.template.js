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

function slide(i, name) {
  const f = figma.createFrame();
  figma.currentPage.appendChild(f);
  f.name = name;
  f.resize(W, H);
  f.x = i * (W + GAP); f.y = 0;
  f.clipsContent = true;
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
  const head = T(figma.currentPage, {
    x: i * (W + GAP), y: H + 70, str: 'SPEAKER NOTES  ·  ' + words + ' WORDS',
    font: F.mono, size: 16, color: '#7A8494', ls: 12
  });
  const body = T(figma.currentPage, {
    x: i * (W + GAP), y: H + 108, w: 1400, str: str,
    font: F.ui, size: 26, lh: 38, color: '#2A3342'
  });
  head.name = 'notes label'; body.name = 'speaker notes';
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

  const kinds = ['SCREENSHOTS', 'VOICE NOTES', 'DOCUMENTS', 'HALF FORMED THOUGHTS'];
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
  const sources = ['screen and windows', 'meeting and system audio', 'spoken thoughts', 'files and links'];
  for (let i = 0; i < sources.length; i++) {
    const ry = panelY + 146 + i * 52;
    R(f, { x: xs[0] + 32, y: ry + 8, w: 9, h: 9, r: 5, fill: TINTS[i % TINTS.length], name: 'dot' });
    T(f, { x: xs[0] + 54, y: ry, str: sources[i], font: F.ui, size: 20, color: C.ink2 });
  }

  // 02 organize
  const folders = [['Product design', '18'], ['Interviews', '11'], ['Reading', '24'], ['Half ideas', '7']];
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
  T(f, { x: x + 48, y: sy + 38, str: 'Product design', font: F.h, size: 23, color: C.pearl });
  T(f, { x: x + 28, y: sy + 76, str: '18 SAVED  ·  6 TOPICS', font: F.mono, size: 11, color: C.ink3, ls: 12 });
  hairline(f, x + 28, sy + 108, pw - 56, C.line, 1);

  const topics = [['Voice capture that feels natural', '4'], ['Onboarding without a tour', '3'], ['Colour and contrast notes', '5'], ['Pricing page teardown', '2'], ['Motion that explains', '4']];
  for (let i = 0; i < topics.length; i++) {
    const ty = sy + 126 + i * 56;
    if (i === 0) R(f, { x: x + 16, y: ty - 8, w: pw - 32, h: 46, r: 12, fill: C.lav, fillOpacity: 0.12, name: 'selected' });
    T(f, { x: x + 28, y: ty, w: pw - 90, str: topics[i][0], font: F.uiMed, size: 16, color: i === 0 ? C.pearl : C.ink2 });
    T(f, { x: x, y: ty + 2, w: pw - 28, align: 'RIGHT', str: topics[i][1], font: F.mono, size: 13, color: C.ink3 });
  }

  /* --- C: topic summary -------------------------------------------- */
  x = xs[2];
  phoneShell(f, x, py, pw, ph);
  T(f, { x: x + 28, y: py + 42, str: 'Product design', font: F.mono, size: 12, color: C.ink3, ls: 10 });
  T(f, { x: x + 28, y: py + 76, w: pw - 56, str: 'Voice capture that feels natural', font: F.serif, size: 25, lh: 33, color: C.pearl });
  T(f, { x: x + 28, y: py + 156, str: 'AI SUMMARY', font: F.mono, size: 11, color: C.tealSoft, ls: 14 });
  T(f, { x: x + 28, y: py + 182, w: pw - 56, str: 'Across four saves you keep circling one idea: the recorder should disappear and the words should appear.', font: F.serif, size: 16, lh: 26, color: C.ink2 });

  T(f, { x: x + 28, y: py + 292, str: 'FROM', font: F.mono, size: 10, color: C.ink3, ls: 14 });
  const srcs = ['screenshot 14 Sep', 'voice note', 'meeting 9 Sep'];
  let sx = x + 28, srow = 0;
  for (let i = 0; i < srcs.length; i++) {
    const s = chip(f, { x: sx, y: py + 316 + srow * 34, str: srcs[i], font: F.mono, size: 11, ls: 2, color: C.tealSoft, stroke: C.teal, strokeOpacity: 0.4, fill: C.teal, fillOpacity: 0.1, padX: 10, padY: 6 });
    sx += s.w + 8;
    if (i === 1) { sx = x + 28; srow = 1; }
  }

  hairline(f, x + 28, py + 400, pw - 56, C.line, 1);
  T(f, { x: x + 28, y: py + 422, str: 'YOUR NOTES', font: F.mono, size: 11, color: C.lavSoft, ls: 14 });
  T(f, { x: x + 28, y: py + 448, w: pw - 56, str: '"Recording feels like a performance. What if it just listened?"', font: F.serifIt, size: 16, lh: 26, color: C.pearl });

  const follow = ['what changed since?', 'argue against this'];
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
  const u1 = T(f, { x: M + colW - 620 + 24, y: y + 22, w: 572, str: 'What was that idea I saved about making recordings feel more natural?', font: F.ui, size: 21, lh: 31, color: C.pearl });
  const u1h = u1.height + 44;
  const u1r = R(f, { x: M + colW - 620, y: y, w: 620, h: u1h, r: 22, fill: C.panel2, stroke: C.line, name: 'you' });
  f.insertChild(f.children.indexOf(u1), u1r);
  T(f, { x: M + colW - 620, y: y - 26, w: 620, align: 'RIGHT', str: 'YOU', font: F.mono, size: 11, color: C.ink3, ls: 14 });
  y += u1h + 34;

  // 2 · what came back, with its source attached
  const rBody = T(f, { x: M + 30, y: y + 52, w: 820, str: '"Recording feels like a performance. What if it just listened, and showed the words as they came?"', font: F.serifIt, size: 24, lh: 36, color: C.pearl });
  const rh = rBody.height + 86;
  const rCard = R(f, { x: M, y: y, w: 880, h: rh, r: 20, fill: C.teal, fillOpacity: 0.07, stroke: C.teal, strokeOpacity: 0.35, name: 'retrieved' });
  f.insertChild(f.children.indexOf(rBody), rCard);
  const rRule = R(f, { x: M, y: y, w: 3, h: rh, r: 2, fill: C.teal, name: 'source rule' });
  f.insertChild(f.children.indexOf(rBody), rRule);
  T(f, { x: M + 30, y: y + 22, str: 'RETRIEVED FROM YOUR NOTES  ·  14 SEP', font: F.mono, size: 11, color: C.tealSoft, ls: 14 });
  y += rh + 30;

  // 3 · the interpretation
  T(f, { x: M + 30, y: y, str: 'MINDSPACE', font: F.mono, size: 11, color: C.lavSoft, ls: 14 });
  const a1 = T(f, { x: M + 30, y: y + 26, w: 860, str: 'You wanted the ceremony gone. No start button, a live transcript, the recorder out of the way.', font: F.serif, size: 23, lh: 34, color: C.ink2 });
  R(f, { x: M, y: y, w: 3, h: a1.height + 30, r: 2, fill: C.lav, fillOpacity: 0.7, name: 'ai rule' });
  y += a1.height + 60;

  // 4 · the turn
  const u2 = T(f, { x: M + colW - 620 + 24, y: y + 22, w: 572, str: 'Challenge that. What am I missing?', font: F.ui, size: 21, lh: 31, color: C.pearl });
  const u2h = u2.height + 44;
  const u2r = R(f, { x: M + colW - 620, y: y, w: 620, h: u2h, r: 22, fill: C.panel2, stroke: C.line, name: 'you' });
  f.insertChild(f.children.indexOf(u2), u2r);
  y += u2h + 30;

  T(f, { x: M + 30, y: y, str: 'MINDSPACE', font: F.mono, size: 11, color: C.lavSoft, ls: 14 });
  const a2 = T(f, { x: M + 30, y: y + 26, w: 860, str: 'Always listening raises a trust question, and a live transcript invites editing while you speak. Your note assumed both were free.', font: F.serif, size: 23, lh: 34, color: C.ink2 });
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

    const builders = [slide1, slide2, slide3, slide4, slide5, slide6, slide7];
    for (let i = 0; i < builders.length; i++) {
      step = 'building slide ' + (i + 1);
      builders[i]();
    }

    step = 'framing the view';
    const frames = figma.currentPage.children.filter(function (n) { return n.type === 'FRAME'; });
    figma.viewport.scrollAndZoomIntoView(frames);
    figma.closePlugin('Mindspace deck built. 7 slides, speaker notes under each.');
  } catch (e) {
    report(step, e);
  }
}

main();
