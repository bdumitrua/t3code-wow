import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { encodeFrame, decodeImage, renderCells, cellsToBytes, bytesToCells, MAX_PAYLOAD, parsePPM, parseBMP, parseQImage } from '../src/codec.js';
import { StripCapture } from '../src/capture.js';
import { deriveKeys, open } from '../src/strip-crypto.js';
import { luaAssignment } from '../src/luaser.js';
import { roundCorner } from './rounded-corner.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const lua = ['lua5.1', 'luajit', 'lua'].find((bin) => {
  try { execFileSync('which', [bin], { stdio: 'ignore' }); return true; } catch { return false; }
});

function luaCells(seq, payloadHex) {
  const script = `
    local ns = {}
    local chunk = assert(loadfile(${JSON.stringify(path.join(root, 'addon/T3Code/Core/Codec.lua'))}))
    chunk("T3Code", ns)
    local hex = ${JSON.stringify(payloadHex)}
    local s = hex:gsub("..", function(h) return string.char(tonumber(h, 16)) end)
    local cells = ns.Codec.Encode(${seq}, s)
    io.write(table.concat(cells, ","))
  `;
  return execFileSync(lua, ['-e', script]).toString().split(',').map(Number);
}

test('bytes <-> cells round trip', () => {
  const bytes = [0, 1, 2, 250, 255, 128, 77];
  assert.deepEqual(cellsToBytes(bytesToCells(bytes), bytes.length), bytes);
});

test('encode, render and decode', () => {
  const payload = 'B\x1fsess\x1fui\x1f1\x1f1\x1fo\x1f\x1f0\x1eC\x1f1\x1fsend\x1fthread-1\x1fhello ✓ 世界';
  const cells = encodeFrame(4242, payload);
  for (const cell of [2, 3, 4, 6]) {
    for (const [ox, oy] of [[0, 0], [1, 2], [5, 3]]) {
      const img = renderCells(cells, { cell, ox, oy, width: 160 * cell + 20, height: 60 * cell });
      const out = decodeImage(img);
      assert.ok(out && !out.error, `decode failed cell=${cell} ox=${ox} oy=${oy}: ${out?.error}`);
      assert.equal(out.seq, 4242);
      assert.equal(out.payload.toString('utf8'), payload);
    }
  }
});

test('no strip -> null; corrupted -> checksum error', () => {
  const blank = renderCells([], { width: 600, height: 100 });
  assert.equal(decodeImage(blank), null);
  const cells = encodeFrame(1, 'hello world');
  cells[40] = (cells[40] + 1) % 8;
  const out = decodeImage(renderCells(cells, { cell: 3 }));
  assert.equal(out.error, 'checksum mismatch');
});

test('decodes squares that drift off whole pixels', () => {
  // The game reports a slightly smaller screen than it draws, so 3px squares land ~3.0125px apart.
  const payload = 'H\x1f1\x1fsession\x1fui\x1f14\x1f1\x1f0\x1ftg\x1f\x1f0.2.0\x1f1200\x1f';
  const cells = encodeFrame(33, payload);
  const pitch = 3.0125;
  const width = 500;
  const height = 12;
  const data = Buffer.alloc(width * height * 3, 40);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const k = Math.floor(x / pitch) + Math.floor(y / pitch) * 160;
      if (Math.floor(x / pitch) >= 160 || k >= cells.length) continue;
      const i = (y * width + x) * 3;
      data[i] = cells[k] & 4 ? 255 : 0;
      data[i + 1] = cells[k] & 2 ? 255 : 0;
      data[i + 2] = cells[k] & 1 ? 255 : 0;
    }
  }
  const out = decodeImage({ width, height, data });
  assert.ok(out && !out.error, out?.error);
  assert.equal(out.payload.toString('utf8'), payload);
});

// A strip as the system draws it after scaling the game by a fraction: squares `pitch`
// pixels apart, `inset` in from the corner, each pixel averaging the cells under its
// four quarters, as scaling blurs them. `background` fills the rest.
function scaledStrip(cells, { pitch, inset, width = 672, height = 272, background = () => [60, 60, 60] }) {
  const data = Buffer.alloc(width * height * 3);
  const cellAt = (x, y) => {
    const col = Math.floor((x - inset) / pitch);
    const k = col + Math.floor((y - inset) / pitch) * 160;
    return x < inset || y < inset || col >= 160 || k >= cells.length ? -1 : cells[k];
  };
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 3;
      const bg = background(x, y);
      for (let c = 0; c < 3; c++) {
        let sum = 0;
        for (const [dx, dy] of [[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]]) {
          const v = cellAt(x + dx, y + dy);
          sum += v < 0 ? bg[c] : v & (4 >> c) ? 255 : 0;
        }
        data[i + c] = Math.round(sum / 4);
      }
    }
  }
  return { width, height, data };
}

test('decodes a strip the system scaled up by a fraction (Classic Era fullscreen on a Mac)', () => {
  // The game draws 2560x1600 on a 2880x1800 panel: 3px squares become 3.375px, and the
  // 9px inset becomes about 10.
  const payload = 'x'.repeat(400);
  const pitch = 3.375;
  const out = decodeImage(scaledStrip(encodeFrame(119, payload), { pitch, inset: 10 }), null, { searchY: 80 });
  assert.ok(out && !out.error, out?.error);
  assert.equal(out.payload.toString('utf8'), payload);
  assert.ok(Math.abs(out.geo.pitch - pitch) < 0.02, `pitch ${out.geo.pitch}`);
});

test('decodes strips scaled by other fractions, down as well as up', () => {
  // Up to 4px squares: the capture is sized for those (StripCapture.stripPixels).
  for (const scale of [0.75, 0.875, 1.25]) {
    const pitch = 3 * scale;
    const payload = `scaled ${scale} `.repeat(30);
    const out = decodeImage(scaledStrip(encodeFrame(7, payload), { pitch, inset: Math.round(9 * scale) }), null, { searchY: 80 });
    assert.ok(out && !out.error, `${scale}: ${out?.error}`);
    assert.equal(out.payload.toString('utf8'), payload, `scale ${scale}`);
  }
});

test('a fractional spacing found once reads the next frame from the hint', () => {
  const opts = { pitch: 3.375, inset: 10 };
  const first = decodeImage(scaledStrip(encodeFrame(1, 'first'), opts), null, { searchY: 80 });
  assert.ok(first && !first.error, first?.error);
  const next = decodeImage(scaledStrip(encodeFrame(2, 'a longer second frame '.repeat(20)), opts), first.geo, { searchY: 80 });
  assert.ok(next && !next.error, next?.error);
  assert.equal(next.seq, 2);
  // The longer frame pins the spacing down, and the one after reads from that.
  const third = decodeImage(scaledStrip(encodeFrame(3, 'third'), opts), next.geo, { searchY: 80 });
  assert.equal(third?.seq, 3);
  assert.deepEqual(third.geo, next.geo);
});

test('a damaged strip at a fractional spacing says why instead of reading as no strip', () => {
  const cells = encodeFrame(3, 'y'.repeat(200));
  cells[cells.length - 10] ^= 0b111;
  const out = decodeImage(scaledStrip(cells, { pitch: 3.375, inset: 10 }), null, { searchY: 80 });
  assert.ok(out?.error, 'expected an error');
  assert.ok(out.geo);
});

test('scenery without a strip is not taken for one at any spacing', () => {
  const rand = (x, y) => (Math.imul(x * 7919 + y * 104729, 2654435761) >>> 24) & 255;
  const backgrounds = {
    grass: () => [40, 170, 50], // the magic's first cell everywhere
    noise: (x, y) => [rand(x, y), rand(y, x + 1), rand(x + 2, y)],
  };
  for (const [name, background] of Object.entries(backgrounds)) {
    assert.equal(decodeImage(scaledStrip([], { pitch: 3, inset: 9, background }), null, { searchY: 80 }), null, name);
  }
});

test('max payload fits', () => {
  const payload = 'x'.repeat(MAX_PAYLOAD);
  const cells = encodeFrame(9, payload);
  const out = decodeImage(renderCells(cells, { cell: 3 }));
  assert.equal(out.payload.length, MAX_PAYLOAD);
  assert.throws(() => encodeFrame(9, payload + 'y'));
});

test('Lua encoder matches JS encoder', { skip: !lua && 'no lua interpreter' }, () => {
  const payload = Buffer.from('C\x1f7\x1fsend\x1fabc\x1fünïcödé | text', 'utf8');
  const fromLua = luaCells(65537, payload.toString('hex'));
  const fromJs = encodeFrame(1, payload);
  assert.deepEqual(fromLua, fromJs);
});

// The strip the addon draws with its keys and a queued message: its cells and where its
// top-left corner is, in physical pixels from the game's.
function addonStrip(keys) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 't3wow-slot-'));
  const slot = path.join(dir, 'Inbox.lua');
  fs.writeFileSync(slot, luaAssignment('T3Code_Inbox', { v: 1, gen: 5, now: 1, nextSig: 1, key: keys.hex, threads: [], projects: [], usage: [], bridge: {} }));
  const [cells, , origin] = execFileSync(lua, ['tools/strip_e2e.lua', 'addon/T3Code', slot, 'thread-42', 'run the tests'], { cwd: root }).toString().trim().split('\n');
  fs.rmSync(dir, { recursive: true, force: true });
  const [ox, oy] = origin.split(',').map(Number);
  return { cells: [...cells].map(Number), ox, oy };
}

test('the strip the addon draws is read through a window corner the desktop rounds, at 100 to 200 percent scaling', { skip: !lua && 'no lua interpreter' }, () => {
  const keys = deriveKeys(crypto.randomBytes(32));
  const { cells, ox, oy } = addonStrip(keys);
  assert.ok(cells.length > 2 * 160, 'a frame of several rows');
  const { width, height } = StripCapture.stripPixels(4);
  for (const scale of [1, 1.25, 1.5, 1.75, 2]) {
    const corner = (x, y) => roundCorner(renderCells(cells, { cell: 3, ox: x, oy: y, width, height, background: [40, 90, 60] }), 8 * scale);
    const out = decodeImage(corner(ox, oy));
    assert.ok(out && !out.error, `read at ${scale * 100}%: ${out ? out.error : 'no strip found'}`);
    if (scale === 1) assert.deepEqual([out.geo.ox, out.geo.oy], [ox, oy], 'found at its own corner, so each cell is read at its centre');
    assert.equal(open(keys, out.seq, out.payload).toString().split('\x1e').at(-1), 'C\x1f1\x1fsend\x1fthread-42\x1frun the tests\x1fauto');
  }
});

test('parse ppm', () => {
  const header = Buffer.from('P6\n# comment\n2 1\n255\n', 'latin1');
  const img = parsePPM(Buffer.concat([header, Buffer.from([255, 0, 0, 0, 255, 0])]));
  assert.equal(img.width, 2);
  assert.equal(img.data[3], 0);
  assert.equal(img.data[4], 255);
});

// A BMP like macOS screencapture writes: 32-bit with bitfields, or plain 24-bit, either row order.
function toBMP(img, { bpp = 32, topDown = false, rgbOrder = false } = {}) {
  const stride = Math.ceil((img.width * bpp) / 32) * 4;
  const header = bpp === 32 ? 54 + 12 : 54;
  const b = Buffer.alloc(header + stride * img.height);
  b.write('BM', 0, 'ascii');
  b.writeUInt32LE(b.length, 2);
  b.writeUInt32LE(header, 10);
  b.writeUInt32LE(40, 14);
  b.writeInt32LE(img.width, 18);
  b.writeInt32LE(topDown ? -img.height : img.height, 22);
  b.writeUInt16LE(1, 26);
  b.writeUInt16LE(bpp, 28);
  b.writeUInt32LE(bpp === 32 ? 3 : 0, 30);
  if (bpp === 32) {
    b.writeUInt32LE(rgbOrder ? 0x000000ff : 0x00ff0000, 54);
    b.writeUInt32LE(0x0000ff00, 58);
    b.writeUInt32LE(rgbOrder ? 0x00ff0000 : 0x000000ff, 62);
  }
  for (let y = 0; y < img.height; y++) {
    const row = header + (topDown ? y : img.height - 1 - y) * stride;
    for (let x = 0; x < img.width; x++) {
      const [r, g, bl] = img.data.subarray((y * img.width + x) * 3, (y * img.width + x) * 3 + 3);
      if (bpp === 32 && rgbOrder) b.writeUInt32LE(((0xff << 24) | (bl << 16) | (g << 8) | r) >>> 0, row + x * 4);
      else if (bpp === 32) b.writeUInt32LE(((0xff << 24) | (r << 16) | (g << 8) | bl) >>> 0, row + x * 4);
      else b.set([bl, g, r], row + x * 3);
    }
  }
  return b;
}

test('BMP captures decode like PPM ones', () => {
  const cells = encodeFrame(7, 'hello from macOS');
  const img = renderCells(cells, { cell: 6, ox: 1, oy: 2, width: 161 * 6 + 3, height: 30 });
  for (const opts of [{ bpp: 32 }, { bpp: 32, topDown: true }, { bpp: 24 }, { bpp: 32, rgbOrder: true }]) {
    const back = parseBMP(toBMP(img, opts));
    assert.deepEqual([back.width, back.height], [img.width, img.height]);
    assert.ok(back.data.equals(img.data), `pixels differ for ${JSON.stringify(opts)}`);
    assert.equal(decodeImage(back).payload.toString(), 'hello from macOS');
  }
});

// KWin's raw pixels in a QImage format, with rows padded past the image's width.
function toQImage(img, format) {
  const bytes = format >= 25 ? 8 : 4;
  const stride = img.width * bytes + 12;
  const b = Buffer.alloc(stride * img.height, 0x5a);
  for (let y = 0; y < img.height; y++) {
    for (let x = 0; x < img.width; x++) {
      const [r, g, bl] = img.data.subarray((y * img.width + x) * 3, (y * img.width + x) * 3 + 3);
      const o = y * stride + x * bytes;
      if (format === 6) b.writeUInt32LE(((0xff << 24) | (r << 16) | (g << 8) | bl) >>> 0, o);
      else if (format === 16) b.set([r, g, bl, 0xff], o);
      else for (const [i, v] of [r, g, bl, 0xff].entries()) b.writeUInt16LE(v * 257, o + i * 2);
    }
  }
  return { buf: b, meta: { width: img.width, height: img.height, stride, format } };
}

test('KWin raw captures decode like PPM ones, in its 8- and 16-bit formats', () => {
  const cells = encodeFrame(8, 'hello from KWin');
  const img = renderCells(cells, { cell: 4, ox: 2, oy: 1, width: 161 * 4 + 2, height: 24 });
  for (const format of [6, 16, 26]) {
    const { buf, meta } = toQImage(img, format);
    const back = parseQImage(buf, meta);
    assert.ok(back.data.equals(img.data), `pixels differ for format ${format}`);
    assert.equal(decodeImage(back).payload.toString(), 'hello from KWin');
  }
  assert.throws(() => parseQImage(Buffer.alloc(64), { width: 4, height: 4, stride: 16, format: 30 }), /unsupported KWin image format 30/);
});

test('searchY finds a strip below a title bar', () => {
  const cells = encodeFrame(9, 'under the title bar');
  const img = renderCells(cells, { cell: 6, ox: 0, oy: 56, width: 160 * 6 + 8, height: 120 });
  assert.equal(decodeImage(img), null);
  assert.equal(decodeImage(img, null, { searchY: 80 }).payload.toString(), 'under the title bar');
});
