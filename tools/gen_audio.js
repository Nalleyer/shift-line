// gen_audio.js — synthesises SFX and music tracks for SHIFTLINE.
//   assets/sfx/*.wav    short chiptune SFX
//   assets/music/*.wav  looping chiptune themes
// Run: node tools/gen_audio.js
'use strict';
const fs = require('fs');
const path = require('path');
const { encodeWAV, SAMPLE_RATE: SR } = require('./encode');

const ROOT = path.resolve(__dirname, '..');
const A = (p) => path.join(ROOT, p);

/* ================================================================== */
/* primitives                                                          */
/* ================================================================== */
const TAU = Math.PI * 2;

function makeBuffer(dur) {
  return new Float32Array(Math.ceil(dur * SR));
}

// deterministic white noise
let noiseSeed = 0x1234567;
function rnd() {
  noiseSeed = (noiseSeed * 1664525 + 1013904223) >>> 0;
  return noiseSeed / 4294967296 * 2 - 1;
}

function osc(wave, phase, duty) {
  const p = phase - Math.floor(phase);
  switch (wave) {
    case 'square':
      return p < (duty === undefined ? 0.5 : duty) ? 1 : -1;
    case 'tri':
      return p < 0.5 ? 4 * p - 1 : 3 - 4 * p;
    case 'saw':
      return 2 * p - 1;
    case 'sine':
      return Math.sin(p * TAU);
    default:
      return 0;
  }
}

// classic ADSR. t/dur in seconds.
function adsr(t, dur, a, d, s, r) {
  if (t < 0 || t > dur) return 0;
  if (t < a) return t / a;
  if (t < a + d) return 1 - (1 - s) * ((t - a) / d);
  const rel = dur - r;
  if (t < rel) return s;
  return s * (1 - (t - rel) / Math.max(r, 1e-4));
}

/**
 * addNote — renders one note into buf.
 * freq -> freq2 is an exponential pitch sweep over the note.
 */
function addNote(buf, opt) {
  const {
    at = 0,
    dur = 0.1,
    freq = 440,
    freq2 = null,
    wave = 'square',
    vol = 0.2,
    duty = 0.5,
    a = 0.004,
    d = 0.02,
    s = 0.9,
    r = 0.03,
    vib = 0, // vibrato depth in semitones
    vibRate = 6,
    noise = 0, // 0..1 blend of white noise (for percussion / grit)
  } = opt;

  const start = Math.floor(at * SR);
  const len = Math.floor(dur * SR);
  const end = Math.min(buf.length, start + len);
  let phase = 0;
  for (let i = start; i < end; i++) {
    const t = (i - start) / SR;
    const u = (i - start) / len;
    let f = freq2 ? freq * Math.pow(freq2 / freq, u) : freq;
    if (vib) f *= Math.pow(2, (Math.sin(t * TAU * vibRate) * vib) / 12);
    phase += f / SR;
    let v = osc(wave, phase, duty);
    if (noise) v = v * (1 - noise) + rnd() * noise;
    buf[i] += v * vol * adsr(t, dur, a, d, s, r);
  }
}

// pitch helpers
const midi = (n) => 440 * Math.pow(2, (n - 69) / 12);
const NOTE = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };

function n(name) {
  // e.g. "A4", "C#5", "Bb3"
  const m = /^([A-G])([#b]?)(-?\d)$/.exec(name);
  if (!m) throw new Error('bad note ' + name);
  let v = NOTE[m[1]];
  if (m[2] === '#') v += 1;
  if (m[2] === 'b') v -= 1;
  return midi(v + (parseInt(m[3], 10) + 1) * 12);
}

// one-pole DC blocker (~17 Hz) so asymmetric square waves do not push the mix off-centre
function dcBlock(buf, R = 0.995) {
  let x1 = 0;
  let y1 = 0;
  for (let i = 0; i < buf.length; i++) {
    const x = buf[i];
    const y = x - x1 + R * y1;
    x1 = x;
    y1 = y;
    buf[i] = y;
  }
  return buf;
}

/**
 * Trim/loop a music buffer to an exact musical length and fade the seam so
 * the loop point does not click.
 */
function finishMusic(b, loopSamples, opts = {}) {
  const out = new Float32Array(loopSamples);
  out.set(b.subarray(0, Math.min(b.length, loopSamples)));
  const f = Math.max(1, Math.floor(0.006 * SR));
  for (let i = 0; i < f; i++) {
    const g = i / f;
    out[i] *= g;
    out[loopSamples - 1 - i] *= g;
  }
  return master(out, { peak: 0.62, drive: 0.9, ...opts });
}

function master(buf, { peak = 0.85, crush = true, drive = 1.0 } = {}) {
  dcBlock(buf);
  let max = 0;
  for (let i = 0; i < buf.length; i++) {
    let v = Math.tanh(buf[i] * drive);
    buf[i] = v;
    const av = Math.abs(v);
    if (av > max) max = av;
  }
  const g = max > 0 ? peak / max : 0;
  for (let i = 0; i < buf.length; i++) {
    let v = buf[i] * g;
    if (crush) v = Math.round(v * 254) / 254; // 8-bit grit
    buf[i] = v;
  }
  return buf;
}

function writeSFX(name, buf) {
  fs.writeFileSync(A(`assets/sfx/${name}.wav`), encodeWAV(buf));
  let peak = 0;
  for (let i = 0; i < buf.length; i++) peak = Math.max(peak, Math.abs(buf[i]));
  console.log(`  sfx/${name}.wav  ${(buf.length / SR).toFixed(2)}s peak=${peak.toFixed(2)}`);
}

/* ================================================================== */
/* SFX                                                                 */
/* ================================================================== */
function sfxUiMove() {
  const b = makeBuffer(0.05);
  addNote(b, { freq: 1180, freq2: 880, dur: 0.045, wave: 'square', vol: 0.22, duty: 0.25, d: 0.01, s: 0.4, r: 0.02 });
  return master(b, { peak: 0.5 });
}

function sfxUiSelect() {
  const b = makeBuffer(0.16);
  addNote(b, { at: 0.0, freq: n('E5'), dur: 0.05, wave: 'square', vol: 0.2, duty: 0.3, r: 0.02 });
  addNote(b, { at: 0.05, freq: n('B5'), dur: 0.09, wave: 'square', vol: 0.2, duty: 0.3, r: 0.05 });
  return master(b, { peak: 0.6 });
}

function sfxUiDeny() {
  const b = makeBuffer(0.18);
  addNote(b, { freq: 190, freq2: 120, dur: 0.16, wave: 'square', vol: 0.24, duty: 0.5, r: 0.06, vib: 1.2, vibRate: 30 });
  return master(b, { peak: 0.55 });
}

function sfxShift() {
  const b = makeBuffer(0.09);
  addNote(b, { freq: 4200, freq2: 2400, dur: 0.012, wave: 'square', vol: 0.16, duty: 0.5, r: 0.01, noise: 0.7 });
  addNote(b, { at: 0.005, freq: 1500, freq2: 620, dur: 0.055, wave: 'square', vol: 0.22, duty: 0.35, d: 0.01, s: 0.35, r: 0.03 });
  return master(b, { peak: 0.65 });
}

function sfxFight() {
  const b = makeBuffer(0.5);
  addNote(b, { at: 0.0, freq: n('A3'), dur: 0.09, wave: 'square', vol: 0.2, duty: 0.25, r: 0.02 });
  addNote(b, { at: 0.08, freq: n('C#4'), dur: 0.09, wave: 'square', vol: 0.2, duty: 0.25, r: 0.02 });
  addNote(b, { at: 0.16, freq: n('E4'), dur: 0.2, wave: 'square', vol: 0.22, duty: 0.25, r: 0.1 });
  addNote(b, { at: 0.16, freq: n('A2'), dur: 0.3, wave: 'tri', vol: 0.25, r: 0.15 });
  addNote(b, { at: 0.0, freq: 200, freq2: 3000, dur: 0.3, wave: 'saw', vol: 0.05, noise: 0.9, a: 0.15, r: 0.1 });
  return master(b, { peak: 0.7 });
}

function sfxHit() {
  const b = makeBuffer(0.12);
  addNote(b, { freq: 260, freq2: 90, dur: 0.09, wave: 'square', vol: 0.28, duty: 0.5, d: 0.05, s: 0.3, r: 0.02, noise: 0.25 });
  addNote(b, { at: 0.0, freq: 6000, freq2: 1500, dur: 0.03, wave: 'saw', vol: 0.12, noise: 0.9, r: 0.02 });
  return master(b, { peak: 0.75 });
}

function sfxHitBig() {
  const b = makeBuffer(0.3);
  addNote(b, { freq: 210, freq2: 55, dur: 0.24, wave: 'square', vol: 0.3, duty: 0.5, d: 0.1, s: 0.2, r: 0.06, noise: 0.2 });
  addNote(b, { at: 0.0, freq: 8000, freq2: 900, dur: 0.06, wave: 'saw', vol: 0.14, noise: 0.95, r: 0.03 });
  addNote(b, { at: 0.01, freq: 70, freq2: 40, dur: 0.24, wave: 'sine', vol: 0.35, r: 0.1 });
  return master(b, { peak: 0.85 });
}

function sfxHeal() {
  const b = makeBuffer(0.32);
  addNote(b, { at: 0.0, freq: n('E5'), dur: 0.1, wave: 'tri', vol: 0.24, a: 0.01, d: 0.04, s: 0.5, r: 0.05 });
  addNote(b, { at: 0.07, freq: n('A5'), dur: 0.18, wave: 'tri', vol: 0.24, a: 0.01, d: 0.06, s: 0.4, r: 0.1 });
  addNote(b, { at: 0.0, freq: n('E4'), dur: 0.22, wave: 'sine', vol: 0.1, a: 0.03, r: 0.12 });
  return master(b, { peak: 0.6 });
}

function sfxDeath() {
  const b = makeBuffer(0.5);
  addNote(b, { freq: 470, freq2: 55, dur: 0.42, wave: 'square', vol: 0.24, duty: 0.4, d: 0.12, s: 0.45, r: 0.12, vib: 0.8, vibRate: 12 });
  addNote(b, { at: 0.02, freq: 2000, freq2: 200, dur: 0.3, wave: 'saw', vol: 0.07, noise: 0.6, r: 0.2 });
  return master(b, { peak: 0.7 });
}

function sfxBreak() {
  const b = makeBuffer(0.55);
  addNote(b, { freq: 150, freq2: 34, dur: 0.42, wave: 'saw', vol: 0.3, d: 0.12, s: 0.35, r: 0.15 });
  addNote(b, { at: 0.0, freq: 9000, freq2: 300, dur: 0.25, wave: 'saw', vol: 0.16, noise: 0.95, r: 0.1 });
  addNote(b, { at: 0.0, freq: 90, freq2: 32, dur: 0.5, wave: 'sine', vol: 0.4, r: 0.2 });
  addNote(b, { at: 0.12, freq: 320, freq2: 90, dur: 0.2, wave: 'square', vol: 0.1, duty: 0.1, r: 0.1 });
  return master(b, { peak: 0.95 });
}

function sfxCoreHit() {
  const b = makeBuffer(0.4);
  addNote(b, { freq: 110, freq2: 38, dur: 0.34, wave: 'sine', vol: 0.5, r: 0.14 });
  addNote(b, { freq: 1400, freq2: 700, dur: 0.05, wave: 'square', vol: 0.12, duty: 0.15, r: 0.03 });
  addNote(b, { at: 0.02, freq: 300, freq2: 60, dur: 0.3, wave: 'saw', vol: 0.12, noise: 0.35, r: 0.15 });
  return master(b, { peak: 0.9 });
}

function sfxWaveStart() {
  const b = makeBuffer(0.7);
  addNote(b, { at: 0.0, freq: n('A4'), dur: 0.12, wave: 'square', vol: 0.2, duty: 0.4, r: 0.03 });
  addNote(b, { at: 0.13, freq: n('E5'), dur: 0.12, wave: 'square', vol: 0.2, duty: 0.4, r: 0.03 });
  addNote(b, { at: 0.26, freq: n('A5'), dur: 0.3, wave: 'square', vol: 0.22, duty: 0.4, r: 0.15 });
  addNote(b, { at: 0.26, freq: n('A4'), dur: 0.35, wave: 'tri', vol: 0.2, r: 0.2 });
  return master(b, { peak: 0.75 });
}

function sfxWin() {
  const b = makeBuffer(1.1);
  const seq = [
    ['A4', 0.0],
    ['C5', 0.11],
    ['E5', 0.22],
    ['A5', 0.33],
  ];
  seq.forEach(([note, at]) => {
    addNote(b, { at, freq: n(note), dur: 0.14, wave: 'square', vol: 0.18, duty: 0.35, d: 0.03, s: 0.7, r: 0.05 });
  });
  ['A5', 'C6', 'E5'].forEach((note) => {
    addNote(b, { at: 0.48, freq: n(note), dur: 0.5, wave: 'tri', vol: 0.13, a: 0.01, d: 0.1, s: 0.5, r: 0.25 });
  });
  addNote(b, { at: 0.48, freq: n('A3'), dur: 0.55, wave: 'tri', vol: 0.2, a: 0.01, r: 0.3 });
  return master(b, { peak: 0.8 });
}

function sfxLose() {
  const b = makeBuffer(1.4);
  const seq = [
    ['A4', 0.0],
    ['G4', 0.22],
    ['F4', 0.44],
    ['E4', 0.66],
  ];
  seq.forEach(([note, at]) => {
    addNote(b, { at, freq: n(note), dur: 0.26, wave: 'square', vol: 0.17, duty: 0.45, d: 0.08, s: 0.5, r: 0.1 });
    addNote(b, { at, freq: n(note) / 2, dur: 0.3, wave: 'tri', vol: 0.16, r: 0.12 });
  });
  addNote(b, { at: 0.9, freq: n('A3'), dur: 0.45, wave: 'tri', vol: 0.2, r: 0.3 });
  addNote(b, { at: 0.9, freq: n('E3'), dur: 0.45, wave: 'tri', vol: 0.14, r: 0.3 });
  return master(b, { peak: 0.75 });
}

function sfxTick() {
  const b = makeBuffer(0.04);
  addNote(b, { freq: 2400, freq2: 1200, dur: 0.02, wave: 'square', vol: 0.1, duty: 0.2, r: 0.01 });
  return master(b, { peak: 0.35 });
}

function sfxNode() {
  const b = makeBuffer(0.8);
  addNote(b, { at: 0.0, freq: n('C5'), dur: 0.5, wave: 'tri', vol: 0.18, a: 0.02, d: 0.15, s: 0.4, r: 0.25 });
  addNote(b, { at: 0.06, freq: n('E5'), dur: 0.5, wave: 'tri', vol: 0.16, a: 0.02, d: 0.15, s: 0.4, r: 0.25 });
  addNote(b, { at: 0.12, freq: n('G5'), dur: 0.5, wave: 'tri', vol: 0.14, a: 0.02, d: 0.15, s: 0.4, r: 0.25 });
  return master(b, { peak: 0.55 });
}

/* ================================================================== */
/* MUSIC                                                               */
/* ================================================================== */
const CHORD = {
  Am: ['A', 'C', 'E'],
  F: ['F', 'A', 'C'],
  C: ['C', 'E', 'G'],
  G: ['G', 'B', 'D'],
  Dm: ['D', 'F', 'A'],
  Em: ['E', 'G', 'B'],
  E: ['E', 'G#', 'B'],
};

function chordNotes(name, oct) {
  return CHORD[name].map((root) => {
    const idx = 'C D EF G A B'.indexOf(root[0]);
    // root letter -> semitone
    const base = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 }[root[0]];
    const midiNote = (oct + 1) * 12 + base;
    return midi(midiNote);
  });
}

function kick(b, at, vol = 0.5) {
  const dur = 0.14;
  const start = Math.floor(at * SR);
  const len = Math.floor(dur * SR);
  let phase = 0;
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    const u = i / len;
    const f = 150 * Math.pow(0.28, u);
    phase += f / SR;
    const env = Math.exp(-u * 7);
    b[start + i] += Math.sin(phase * TAU) * vol * env;
  }
}

function snare(b, at, vol = 0.28) {
  const dur = 0.11;
  const start = Math.floor(at * SR);
  const len = Math.floor(dur * SR);
  let phase = 0;
  for (let i = 0; i < len; i++) {
    const u = i / len;
    phase += 220 / SR;
    const env = Math.exp(-u * 9);
    b[start + i] += (rnd() * 0.85 + Math.sin(phase * TAU) * 0.25) * vol * env;
  }
}

function hat(b, at, vol = 0.1, open = false) {
  const dur = open ? 0.08 : 0.032;
  const start = Math.floor(at * SR);
  const len = Math.floor(dur * SR);
  let hp = 0;
  let prev = 0;
  for (let i = 0; i < len; i++) {
    const u = i / len;
    const w = rnd();
    hp = w - prev + 0.6 * hp; // crude high-pass
    prev = w;
    b[start + i] += hp * vol * Math.exp(-u * 12);
  }
}

function battleTheme() {
  const beat = 60 / 122;
  const bars = 16;
  const b = makeBuffer(bars * 4 * beat + 0.2);
  const roots = ['A2', 'A2', 'F2', 'G2', 'A2', 'C3', 'D2', 'E2',
    'F2', 'G2', 'A2', 'E2', 'D2', 'F2', 'E2', 'E2'];
  // Two-bar hook, answer, higher development and a deliberate turnaround.
  // Entries are [pitch, beat within the bar, duration in beats].
  const phrases = [
    [['A4',0,0.65],['C5',0.75,0.5],['E5',1.5,0.9],['D5',3,0.65]],
    [['C5',0,0.7],['A4',1,1.25],['G4',2.75,0.5]],
    [['A4',0.5,0.6],['C5',1.25,0.6],['F5',2,1.2]],
    [['E5',0,0.6],['D5',1,0.6],['B4',2,1.3]],
    [['A4',0,0.65],['C5',0.75,0.5],['E5',1.5,0.9],['G5',3,0.65]],
    [['E5',0,0.65],['D5',1,0.55],['C5',2,1.2]],
    [['D5',0.5,0.6],['F5',1.25,0.6],['A5',2,1.1]],
    [['G#5',0,0.55],['E5',1,0.65],['B4',2.5,0.7]],
    [['C5',0,0.65],['F5',1,1],['E5',2.5,0.65]],
    [['D5',0.5,0.6],['G5',1.5,0.8],['B5',2.75,0.5]],
    [['A5',0,1.2],['G5',1.5,0.55],['E5',2.5,0.8]],
    [['G#5',0.5,0.55],['B5',1.25,0.65],['E5',2.5,0.7]],
    [['F5',0,0.7],['E5',1,0.6],['D5',2,1.1]],
    [['C5',0.5,0.6],['A4',1.5,0.65],['F4',2.5,0.7]],
    [['G#4',0,0.65],['B4',1,0.6],['E5',2,1]],
    [['D5',0,0.6],['B4',1,0.6],['G#4',2,0.65],['E4',3,0.55]],
  ];
  for (let bar = 0; bar < bars; bar++) {
    const t = bar * 4 * beat;
    const root = n(roots[bar]);
    // Short offbeat bass accents leave space between attacks.
    for (const [pos, ratio, len] of [[0,1,0.65],[1.5,1,0.45],[2.5,1.5,0.5],[3.25,1,0.45]]) {
      addNote(b, { at: t + pos * beat, dur: len * beat, freq: root * ratio,
        wave: 'tri', vol: 0.24, a: 0.004, d: 0.06, s: 0.65, r: 0.06 });
    }
    kick(b, t, 0.27);
    if (bar % 2 === 1) kick(b, t + 2.5 * beat, 0.17);
    snare(b, t + 2 * beat, 0.12);
    for (const pos of [1, 3]) hat(b, t + pos * beat, 0.035);
    for (const [note, pos, len] of phrases[bar]) {
      addNote(b, { at: t + pos * beat, dur: len * beat, freq: n(note),
        wave: 'square', duty: 0.25, vol: 0.105, a: 0.012, d: 0.09,
        s: 0.55, r: 0.08 });
    }
  }
  return finishMusic(b, Math.round(bars * 4 * beat * SR));
}

function shopTheme() {
  const beat = 60 / 92;
  const bars = 16;
  const b = makeBuffer(bars * 4 * beat + 0.2);
  const chords = [
    ['C3','E4','G4'], ['A2','C4','E4'], ['F2','A3','C4'], ['G2','B3','D4'],
    ['C3','E4','G4'], ['E3','G4','B4'], ['F2','A3','C4'], ['G2','B3','D4'],
    ['A2','C4','E4'], ['E3','G4','B4'], ['F2','A3','C4'], ['C3','E4','G4'],
    ['D3','F4','A4'], ['G2','B3','D4'], ['C3','E4','G4'], ['G2','B3','D4'],
  ];
  const melody = [
    [['E5',0,0.7],['G5',1.25,0.55],['A5',2,0.7]],
    [['G5',0.25,0.6],['E5',1.5,0.7],['C5',2.75,0.6]],
    [['A4',0,0.65],['C5',1.25,0.55],['F5',2,0.9]],
    [['D5',0.25,0.65],['B4',1.5,0.65],['G4',2.75,0.6]],
    [['E5',0,0.7],['G5',1.25,0.55],['C6',2,0.8]],
    [['B5',0.25,0.6],['G5',1.5,0.7],['E5',2.75,0.6]],
    [['F5',0,0.65],['A5',1.25,0.55],['C6',2,0.8]],
    [['B5',0.25,0.6],['G5',1.5,0.65],['D5',2.75,0.6]],
    [['C5',0,0.7],['E5',1.25,0.55],['A5',2,0.8]],
    [['B5',0.25,0.6],['G5',1.5,0.65],['E5',2.75,0.6]],
    [['A5',0,0.7],['F5',1.25,0.55],['C5',2,0.8]],
    [['G5',0.25,0.6],['E5',1.5,0.65],['C5',2.75,0.6]],
    [['F5',0,0.7],['A5',1.25,0.55],['D6',2,0.8]],
    [['B5',0.25,0.6],['G5',1.5,0.65],['D5',2.75,0.6]],
    [['E5',0,0.7],['G5',1.25,0.55],['C6',2,0.8]],
    [['B5',0.25,0.6],['D5',1.5,0.65],['G4',2.75,0.6]],
  ];
  for (let bar = 0; bar < bars; bar++) {
    const t = bar * 4 * beat;
    const [root, third, fifth] = chords[bar];
    for (const pos of [0, 2.25]) addNote(b, { at: t + pos * beat,
      dur: 1.1 * beat, freq: n(root), wave: 'tri', vol: 0.15,
      a: 0.02, d: 0.15, s: 0.5, r: 0.18 });
    for (const note of [third, fifth]) addNote(b, { at: t, dur: 3.7 * beat,
      freq: n(note), wave: 'sine', vol: 0.045, a: 0.15, d: 0.2, s: 0.65, r: 0.4 });
    for (const [note, pos, len] of melody[bar]) {
      addNote(b, { at: t + pos * beat, dur: len * beat, freq: n(note),
        wave: 'tri', vol: 0.13, a: 0.005, d: 0.12, s: 0.28, r: 0.15 });
      addNote(b, { at: t + pos * beat, dur: Math.min(len * beat, 0.18),
        freq: n(note) * 2, wave: 'sine', vol: 0.035, a: 0.003, d: 0.06, s: 0.15, r: 0.07 });
    }
  }
  return finishMusic(b, Math.round(bars * 4 * beat * SR));
}

// "Axle under siege": a separate 16-bar E-minor boss score at 156 BPM.
// Phrygian F, a tritone alarm and a B-major turnaround keep the cadence urgent.
function bossTheme() {
  const beat=60/156, bars=16;
  const b=makeBuffer(bars*4*beat+0.3);
  const roots=['E2','E2','F2','B1','E2','C2','D2','B1',
    'C2','D2','E2','F2','A1','C2','B1','B1'];
  const harmony=[['E4','B4'],['E4','G4'],['F4','C5'],['D#4','A4'],
    ['E4','B4'],['E4','G4'],['F#4','A4'],['D#4','F#4'],
    ['E4','G4'],['F#4','A4'],['G4','B4'],['F4','C5'],
    ['C4','E4'],['E4','G4'],['D#4','F#4'],['D#4','A4']];
  const melody=[
    [['E5',0,.4],['B4',.5,.35],['E5',1,.55],['G5',2,.65],['F5',3,.4],['E5',3.5,.35]],
    [['B5',0,.7],['G5',1,.4],['E5',1.5,.55],['F5',2.5,.35],['E5',3,.6]],
    [['F5',0,.55],['A5',.75,.5],['C6',1.5,.7],['B5',2.5,.45],['A5',3.25,.4]],
    [['F#5',0,.6],['D#5',1,.4],['B4',1.75,.45],['D#5',2.5,.45],['F#5',3.25,.4]],
    [['E5',0,.4],['G5',.5,.35],['B5',1,.55],['C6',2,.65],['B5',3,.4],['G5',3.5,.35]],
    [['E6',0,.7],['D6',1,.4],['C6',1.5,.55],['B5',2.5,.35],['G5',3,.6]],
    [['A5',0,.55],['D6',.75,.5],['C6',1.5,.7],['A5',2.5,.45],['F#5',3.25,.4]],
    [['B5',0,.6],['A5',1,.4],['F#5',1.75,.45],['D#5',2.5,.45],['B4',3.25,.4]],
    [['G5',0,.8],['E5',1,.4],['G5',1.5,.4],['C6',2.25,.7],['B5',3.25,.4]],
    [['A5',0,.8],['F#5',1,.4],['A5',1.5,.4],['D6',2.25,.7],['C6',3.25,.4]],
    [['B5',0,.8],['G5',1,.4],['E5',1.5,.4],['G5',2.25,.7],['Bb5',3.25,.4]],
    [['C6',0,.7],['A5',1,.4],['F5',1.5,.6],['E5',2.5,.35],['F5',3,.6]],
    [['A5',0,.6],['E5',.75,.4],['A5',1.5,.5],['C6',2.25,.5],['B5',3,.6]],
    [['G5',0,.6],['C6',.75,.4],['E6',1.5,.5],['D6',2.25,.5],['C6',3,.6]],
    [['B5',0,.45],['A5',.5,.4],['F#5',1,.45],['D#5',1.5,.4],['F#5',2,.45],['A5',2.5,.4],['B5',3,.65]],
    [['F5',0,.35],['F#5',.5,.35],['G5',1,.35],['G#5',1.5,.35],['A5',2,.35],['Bb5',2.5,.35],['B5',3,.8]],
  ];
  for(let bar=0;bar<bars;bar++) {
    const t=bar*4*beat, root=n(roots[bar]);
    for(let step=0;step<8;step++) {
      const ratio=step%4===3?1.5:step%2===1?2:1;
      addNote(b,{at:t+step*.5*beat,dur:.36*beat,freq:root*ratio,wave:'tri',vol:.2,a:.003,d:.04,s:.7,r:.025});
      addNote(b,{at:t+step*.5*beat,dur:.2*beat,freq:root*ratio,wave:'square',duty:.2,vol:.045,r:.02});
      hat(b,t+step*.5*beat,step%2===0?.035:.026,step===7&&bar%4===3);
    }
    for(const pos of [0,1.5,2,2.75]) kick(b,t+pos*beat,.28);
    for(const pos of [1,3]) snare(b,t+pos*beat,.18);
    if(bar%4===3) for(const pos of [3.25,3.5,3.75]) snare(b,t+pos*beat,.05+(pos-3)*.06);
    for(let step=0;step<16;step++) {
      const notes=harmony[bar], f=n(notes[[0,1,0,1,1,0,1,0][step%8]]);
      addNote(b,{at:t+step*.25*beat,dur:.16*beat,freq:f,wave:'square',duty:.125,vol:bar>=8?.028:.022,r:.018});
    }
    for(const note of harmony[bar]) addNote(b,{at:t,dur:3.8*beat,freq:n(note)/2,wave:'saw',vol:.017,a:.025,d:.1,s:.5,r:.08});
    for(const [note,pos,len] of melody[bar]) {
      addNote(b,{at:t+pos*beat,dur:len*beat,freq:n(note),wave:'square',duty:.25,vol:.105,a:.006,d:.05,s:.65,r:.035,vib:.1});
      addNote(b,{at:t+pos*beat,dur:len*beat,freq:n(note)/2,wave:'tri',vol:.045,a:.008,r:.04});
    }
    if(bar===3||bar===11) for(const pos of [0,2]) addNote(b,{at:t+pos*beat,dur:.3*beat,freq:n('Bb5'),wave:'square',vol:.035,duty:.125,r:.035});
  }
  return finishMusic(b,Math.round(bars*4*beat*SR),{peak:.65,drive:1.05});
}

function titleTheme() {
  const bpm = 84;
  const beat = 60 / bpm;
  const bars = 8;
  const total = bars * 4 * beat + 0.3;
  const b = makeBuffer(total);
  const prog = ['Am', 'F', 'C', 'G', 'Am', 'F', 'Dm', 'E'];

  for (let bar = 0; bar < bars; bar++) {
    const t0 = bar * 4 * beat;
    const ch = prog[bar];
    const tones = chordNotes(ch, 4);
    const root = tones[0] / 2;

    // slow bass pulse on 1 and 3
    for (const q of [0, 2]) {
      addNote(b, {
        at: t0 + q * beat,
        dur: beat * 1.6,
        freq: root,
        wave: 'tri',
        vol: 0.22,
        a: 0.01,
        d: 0.2,
        s: 0.6,
        r: 0.25,
      });
    }

    // sparse rolled arpeggio on eighths
    const pattern = [0, 2, 1, 2, 3, 2, 1, 0];
    for (let e = 0; e < 8; e++) {
      const idx = pattern[e];
      const tone = idx === 3 ? tones[0] * 4 : tones[idx % 3] * (idx === 2 ? 2 : 1);
      addNote(b, {
        at: t0 + e * beat * 0.5,
        dur: beat * 0.5,
        freq: tone,
        wave: 'tri',
        vol: 0.1,
        a: 0.008,
        d: 0.08,
        s: 0.35,
        r: 0.09,
      });
    }

    // soft pad on the chord root an octave up
    addNote(b, {
      at: t0,
      dur: beat * 3.9,
      freq: tones[1] * 2,
      wave: 'sine',
      vol: 0.05,
      a: 0.3,
      d: 0.4,
      s: 0.7,
      r: 0.6,
    });
  }

  // melody — two four-bar phrases, sparse, on the top voice
  const melody = [
    ['E5', 0, 3],
    ['D5', 3, 1],
    ['C5', 4, 2],
    ['A4', 6, 2],
    ['E5', 8, 3],
    ['G5', 11, 1],
    ['A5', 12, 4],
    ['G5', 16, 2],
    ['E5', 18, 2],
    ['D5', 20, 2],
    ['C5', 22, 2],
    ['E5', 24, 3],
    ['D5', 27, 1],
    ['B4', 28, 2],
    ['A4', 30, 2],
  ];
  for (const [note, atBeat, len] of melody) {
    addNote(b, {
      at: atBeat * beat,
      dur: len * beat,
      freq: n(note),
      wave: 'square',
      duty: 0.25,
      vol: 0.1,
      a: 0.02,
      d: 0.15,
      s: 0.55,
      r: 0.2,
      vib: 0.15,
      vibRate: 5,
    });
  }
  return finishMusic(b, Math.round(bars * 4 * beat * SR));
}

/* ================================================================== */
/* main                                                                */
/* ================================================================== */
if(process.argv.includes('--boss-only')) {
  const boss=bossTheme(); fs.writeFileSync(A('assets/music/boss.wav'),encodeWAV(boss));
  console.log(`music/boss.wav ${(boss.length/SR).toFixed(2)}s — 156 BPM, 16 bars`);
  process.exit(0);
}
console.log('SHIFTLINE asset forge — audio');
const sfx = {
  ui_move: sfxUiMove,
  ui_select: sfxUiSelect,
  ui_deny: sfxUiDeny,
  shift: sfxShift,
  fight: sfxFight,
  hit: sfxHit,
  hit_big: sfxHitBig,
  heal: sfxHeal,
  death: sfxDeath,
  break: sfxBreak,
  core_hit: sfxCoreHit,
  wave_start: sfxWaveStart,
  win: sfxWin,
  lose: sfxLose,
  tick: sfxTick,
  node: sfxNode,
};
for (const [name, fn] of Object.entries(sfx)) writeSFX(name, fn());

const musicBattle = battleTheme();
fs.writeFileSync(A('assets/music/battle.wav'), encodeWAV(musicBattle));
console.log(`  music/battle.wav ${(musicBattle.length / SR).toFixed(2)}s`);

const musicTitle = titleTheme();
fs.writeFileSync(A('assets/music/title.wav'), encodeWAV(musicTitle));
console.log(`  music/title.wav  ${(musicTitle.length / SR).toFixed(2)}s`);

const musicShop = shopTheme();
fs.writeFileSync(A('assets/music/shop.wav'), encodeWAV(musicShop));
console.log(`  music/shop.wav   ${(musicShop.length / SR).toFixed(2)}s`);

const musicBoss=bossTheme();
fs.writeFileSync(A('assets/music/boss.wav'),encodeWAV(musicBoss));
console.log(`  music/boss.wav   ${(musicBoss.length/SR).toFixed(2)}s`);
