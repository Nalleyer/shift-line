// gen_cover.js — generates a crisp 630x500 pixel-art itch.io cover image for SHIFTLINE.
// Uses the exact palette, bitmap glyphs, and 16x16 unit masks from the game.
// Run: node tools/gen_cover.js
'use strict';
const fs = require('fs');
const path = require('path');
const { encodePNG, Canvas } = require('./encode');

const ROOT = path.resolve(__dirname, '..');
const OUT_DIR = path.join(ROOT, 'itch');
const OUT_PATH = path.join(OUT_DIR, 'cover.png');

// Exact SHIFTLINE palette (src/ui/theme.lua)
const C = {
  ink:    [11, 14, 20],
  shade:  [18, 26, 35],
  panel:  [24, 35, 45],
  line:   [44, 64, 83],
  dim:    [90, 113, 134],
  paper:  [201, 214, 226],
  white:  [242, 247, 252],
  red:    [255, 77, 71],
  red_dk: [142, 34, 38],
  amber:  [255, 196, 83],
  green:  [91, 224, 142],
  blue:   [89, 168, 255],
};

// 5x7 bitmap font glyphs (matching tools/gen_assets.js)
const FONT = {
  A: ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  B: ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
  C: ['.####', '#....', '#....', '#....', '#....', '#....', '.####'],
  D: ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
  E: ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
  F: ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
  G: ['.####', '#....', '#....', '#..##', '#...#', '#...#', '.####'],
  H: ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  I: ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '#####'],
  L: ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
  M: ['#...#', '##.##', '#.#.#', '#...#', '#...#', '#...#', '#...#'],
  N: ['#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#', '#...#'],
  O: ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  R: ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
  S: ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
  T: ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
  0: ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
  2: ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
  6: ['..##.', '.#...', '#....', '####.', '#...#', '#...#', '.###.'],
  ' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
  '.': ['.....', '.....', '.....', '.....', '.....', '..##.', '..##.'],
  '<': ['...#.', '..#..', '.#...', '#....', '.#...', '..#..', '...#.'],
  '>': ['.#...', '..#..', '...#.', '....#', '...#.', '..#..', '.#...'],
  '-': ['.....', '.....', '.....', '.###.', '.....', '.....', '.....'],
};

// Exact 16x16 unit masks (tools/gen_assets.js)
const SPRITES = {
  S: [
    '.............#..',
    '....###.....##..',
    '...#####....##..',
    '..#######...##..',
    '..###..##...##..',
    '...#####....##..',
    '...#####....##..',
    '..###.###.######',
    '..###########...',
    '.###.#####.##...',
    '.##..####.......',
    '.#...#####......',
    '....###.###.....',
    '...###...##.....',
    '...###...###....',
    '................',
  ],
  G: [
    '....###.........',
    '...#####........',
    '..#######.......',
    '..##...##.......',
    '...#####.######.',
    '...#####.#######',
    '..#####.########',
    '..###.####...###',
    '..###.####.#.###',
    '..###.####.#.###',
    '...###.###...###',
    '...###..#######.',
    '...###...#####..',
    '..####....###...',
    '..####.....#....',
    '................',
  ],
  M: [
    '.............#..',
    '.....##.....###.',
    '....####.....#..',
    '...######....#..',
    '...##...#....#..',
    '...######....#..',
    '....####.....#..',
    '...###########..',
    '..####.####..#..',
    '..##.....##..#..',
    '...###.###...#..',
    '....##.##....#..',
    '...#######...#..',
    '...########..#..',
    '..#########..#..',
    '................',
  ],
  g: [
    '................',
    '................',
    '................',
    '.#............#.',
    '.###..####..###.',
    '..############..',
    '...###.##.###...',
    '...##########...',
    '....##.##.##....',
    '..##########....',
    '.###.######.##..',
    '.##..######..##.',
    '.....##..###....',
    '....###...##....',
    '...####...###...',
    '................',
  ],
  r: [
    '...#.........#..',
    '.###.........##.',
    '..####.....###..',
    '...##########...',
    '...#########....',
    '...##.#######...',
    '....####..###...',
    '...#####.###...#',
    '..##.###########',
    '.###..####.####.',
    '..#...####..###.',
    '.....######..#..',
    '....###..##.....',
    '...###...##.....',
    '...###...###....',
    '................',
  ],
  b: [
    '.....######.....',
    '....########....',
    '...##########...',
    '...##......##...',
    '...##########...',
    '..############..',
    '.####.####.####.',
    '#####.####.#####',
    '#####.#..#.#####',
    '#####.####.#####',
    '.###..####..###.',
    '.....######.....',
    '...####..####...',
    '..#####..#####..',
    '..#####..#####..',
    '................',
  ],
};

// Logical 315x250 scaled 2x -> 630x500 crisp pixel art
const LW = 315;
const LH = 250;
const SCALE = 2;
const cv = new Canvas(LW * SCALE, LH * SCALE);

function rect(x, y, w, h, rgb, a = 1) {
  const px0 = Math.round(x * SCALE);
  const py0 = Math.round(y * SCALE);
  const pw = Math.round(w * SCALE);
  const ph = Math.round(h * SCALE);
  if (a >= 1) {
    cv.rect(px0, py0, pw, ph, rgb, 255);
  } else {
    for (let j = 0; j < ph; j++) {
      for (let i = 0; i < pw; i++) {
        cv.blend(px0 + i, py0 + j, rgb, a);
      }
    }
  }
}

function frame(x, y, w, h, rgb, a = 1) {
  rect(x, y, w, 1, rgb, a);
  rect(x, y + h - 1, w, 1, rgb, a);
  rect(x, y, 1, h, rgb, a);
  rect(x + w - 1, y, 1, h, rgb, a);
}

function drawText(str, cx, y, scale, rgb, a = 1, align = 'center') {
  const step = 6 * scale;
  const totalW = str.length * step - scale;
  let x0 = align === 'center' ? Math.round(cx - totalW / 2) : align === 'right' ? Math.round(cx - totalW) : Math.round(cx);
  for (let idx = 0; idx < str.length; idx++) {
    const g = FONT[str[idx]];
    if (g) {
      for (let row = 0; row < g.length; row++) {
        for (let col = 0; col < g[row].length; col++) {
          if (g[row][col] === '#') {
            rect(x0 + idx * step + col * scale, y + row * scale, scale, scale, rgb, a);
          }
        }
      }
    }
  }
}

function drawSprite(key, cx, cy, scale, rgb, a = 1) {
  const rows = SPRITES[key];
  const w = rows[0].length * scale;
  const h = rows.length * scale;
  const x0 = Math.round(cx - w / 2);
  const y0 = Math.round(cy - h / 2);
  for (let row = 0; row < rows.length; row++) {
    for (let col = 0; col < rows[row].length; col++) {
      if (rows[row][col] === '#') {
        rect(x0 + col * scale, y0 + row * scale, scale, scale, rgb, a);
      }
    }
  }
}

// 1. Background + tactical grid
rect(0, 0, LW, LH, C.ink);
for (let x = 15; x < LW; x += 24) rect(x, 0, 1, LH, C.shade, 0.7);
for (let y = 14; y < LH; y += 24) rect(0, y, LW, 1, C.shade, 0.7);

// Subtle atmospheric battle arena panel in the middle
rect(16, 94, LW - 32, 118, C.shade, 0.72);
frame(16, 94, LW - 32, 118, C.line, 0.75);

// Outer border + amber corner brackets (matching app icon)
frame(6, 6, LW - 12, LH - 12, C.line, 0.9);
const bLen = 12;
rect(6, 6, bLen, 2, C.amber); rect(6, 6, 2, bLen, C.amber);
rect(LW - 6 - bLen, 6, bLen, 2, C.amber); rect(LW - 8, 6, 2, bLen, C.amber);
rect(6, LH - 8, bLen, 2, C.amber); rect(6, LH - 6 - bLen, 2, bLen, C.amber);
rect(LW - 6 - bLen, LH - 8, bLen, 2, C.amber); rect(LW - 8, LH - 6 - bLen, 2, bLen, C.amber);

// 2. Hero Title: SHIFTLINE + sliding notch bar
drawText('SHIFTLINE', LW / 2 + 2, 24, 5, C.red_dk);
drawText('SHIFTLINE', LW / 2, 22, 5, C.white);

// Iconic horizontal shift bar with red notch
const barW = 266;
const barX = Math.round((LW - barW) / 2);
rect(barX, 65, barW, 2, C.amber, 0.88);
rect(barX + 120, 63, 26, 6, C.ink);
rect(barX + 122, 64, 22, 4, C.red);

// Subtitle
drawText('SHIFT THE LINE . HOLD THE CORE', LW / 2, 76, 1, C.paper, 0.85);

// 3. Tactical 5-column clash showcase
const cols = [61, 109, 157, 205, 253];
const enemyY = 124;
const frontY = 152;
const allyY = 182;

// Column lane slots
cols.forEach((cx, i) => {
  const isHero = i === 2;
  rect(cx - 18, 102, 36, 44, C.panel, isHero ? 0.65 : 0.35);
  frame(cx - 18, 102, 36, 44, isHero ? C.red : C.line, isHero ? 0.6 : 0.35);

  rect(cx - 18, 160, 36, 44, C.panel, isHero ? 0.85 : 0.4);
  frame(cx - 18, 160, 36, 44, isHero ? C.amber : C.line, isHero ? 0.95 : 0.4);
});

// Frontline divider
for (let x = 26; x < LW - 26; x += 6) {
  rect(x, frontY, 3, 1, C.red, 0.55);
}

// Alignment sightlines on active ally columns (1, 2, 3)
[1, 2, 3].forEach((ci) => {
  const cx = cols[ci];
  rect(cx, 144, 1, 18, C.amber, ci === 2 ? 0.95 : 0.45);
});
// Clash spark at center column
rect(cols[2] - 4, frontY - 1, 9, 3, C.amber);
rect(cols[2] - 1, frontY - 4, 3, 9, C.amber);
rect(cols[2] - 1, frontY - 1, 3, 3, C.white);

// Enemies (top row)
const enemies = [
  { col: 0, key: 'g', colr: C.red },
  { col: 1, key: 'r', colr: C.red },
  { col: 2, key: 'b', colr: C.red },
  { col: 4, key: 'r', colr: C.red },
];
enemies.forEach((e) => {
  const cx = cols[e.col];
  rect(cx - 11, enemyY + 15, 22, 3, C.ink, 0.7);
  drawSprite(e.key, cx + 1, enemyY + 1, 2, C.red_dk, 0.9);
  drawSprite(e.key, cx, enemyY, 2, e.colr);
});

// Allies (bottom row) — shifted right into formation!
const allies = [
  { col: 1, key: 'G', colr: C.blue },
  { col: 2, key: 'S', colr: C.white },
  { col: 3, key: 'M', colr: C.green },
];
allies.forEach((a) => {
  const cx = cols[a.col];
  rect(cx - 11, allyY + 15, 22, 3, C.ink, 0.75);
  drawSprite(a.key, cx + 1, allyY + 1, 2, C.red_dk, 0.85);
  drawSprite(a.key, cx, allyY, 2, a.colr);
});

// Bold amber SHIFT chevrons on left & right of ally row
const chevL = ['..#', '.#.', '#..', '.#.', '..#'];
const chevR = ['#..', '.#.', '..#', '.#.', '#..'];
function drawMask(rows, x0, y0, scale, rgb, a) {
  for (let r = 0; r < rows.length; r++)
    for (let c = 0; c < rows[r].length; c++)
      if (rows[r][c] === '#') rect(x0 + c * scale, y0 + r * scale, scale, scale, rgb, a);
}
drawMask(chevL, 26, allyY - 6, 2, C.amber, 0.35);
drawMask(chevL, 33, allyY - 6, 2, C.amber, 0.95);
drawMask(chevR, LW - 39, allyY - 6, 2, C.amber, 0.95);
drawMask(chevR, LW - 32, allyY - 6, 2, C.amber, 0.35);

// 4. Bottom tactical control strip
const stripY = 221;
// Left keycap [A]
rect(82, stripY, 22, 15, C.panel);
frame(82, stripY, 22, 15, C.amber);
drawText('A', 93, stripY + 4, 1, C.white);

// Center label << SHIFT >>
drawText('<< SHIFT >>', LW / 2, stripY + 4, 1, C.amber);

// Right keycap [D]
rect(LW - 104, stripY, 22, 15, C.panel);
frame(LW - 104, stripY, 22, 15, C.amber);
drawText('D', LW - 93, stripY + 4, 1, C.white);

// Subtle CRT scanlines across the final 630x500 canvas
for (let y = 1; y < LH * SCALE; y += 2) {
  for (let x = 0; x < LW * SCALE; x++) {
    cv.blend(x, y, [0, 0, 0], 0.08);
  }
}

fs.mkdirSync(OUT_DIR, { recursive: true });
fs.writeFileSync(OUT_PATH, encodePNG(cv));
console.log(`cover: ${cv.w}x${cv.h} -> ${path.relative(ROOT, OUT_PATH)}`);
