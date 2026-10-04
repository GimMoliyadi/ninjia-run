import { G } from './state.js';
import { GROUND, ABYSS, SAFE_FLAT_PX } from './constants.js';

export function initTerrain() {
  G.terrain = [{ type: 'flat', start: 0, end: SAFE_FLAT_PX, y: GROUND }];
  G.nextChunkX = SAFE_FLAT_PX;
  G.chunkIndex = 0;
}

export function appendTerrain(parts, start = G.nextChunkX) {
  let x = start;
  for (const part of parts) {
    const width = part.width ?? (part.end - part.start);
    const seg = { ...part, start: x, end: x + width };
    delete seg.width;
    if (seg.type === 'flat' && seg.y == null) seg.y = GROUND;
    G.terrain.push(seg);
    x += width;
  }
  G.nextChunkX = x;
  return { start, end: x };
}

export function segAt(x) {
  let lo = 0, hi = G.terrain.length - 1;
  while (lo <= hi) {
    const m = (lo + hi) >> 1, s = G.terrain[m];
    if (x < s.start) hi = m - 1;
    else if (x >= s.end) lo = m + 1;
    else return s;
  }
  return null;
}

export function segTypeAt(x) { const s = segAt(x); return s ? s.type : 'flat'; }

export function groundYAt(x) {
  const s = segAt(x);
  if (!s) return GROUND;
  if (s.type === 'pit') return ABYSS;
  if (s.type === 'slope') {
    const t = Math.max(0, Math.min(1, (x - s.start) / Math.max(1, s.end - s.start)));
    return s.y0 + (s.y1 - s.y0) * t;
  }
  return s.y ?? GROUND;
}

export function isSolidAt(x, y = null) {
  const s = segAt(x);
  if (!s || s.type === 'pit') return false;
  if (s.type === 'platform' && y != null && y < s.y - 8) return false;
  return true;
}
