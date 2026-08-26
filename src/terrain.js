import { G } from './state.js';
import { GROUND, ABYSS, SAFE_FLAT_PX } from './constants.js';
import { rand } from './utils.js';

export function initTerrain() {
  G.terrain = [];
  let x = 0;
  const MAX = 2000000;   // 约 2 万米，支撑"1 万米才达极速"的节奏
  // 开局纯平地：先让玩家适应奔跑与金币收集，再渐进引入深坑
  G.terrain.push({ type: 'flat', start: 0, end: SAFE_FLAT_PX });
  x = SAFE_FLAT_PX;
  while (x < MAX) {
    // 先决定是否安排深坑，再把坑前缓冲并入平地段尾部，
    // 保证各段首尾相接、互不重叠（旧版 x+=0 导致段重叠，坑黑块盖在平地上）
    const hasPit = Math.random() < 0.42;
    const buffer = hasPit ? rand(260, 520) : 0;
    const flatLen = rand(720, 1040) + buffer;
    G.terrain.push({ type: 'flat', start: x, end: x + flatLen });
    x += flatLen;
    if (hasPit) {
      const pitLen = rand(170, 300);
      G.terrain.push({ type: 'pit', start: x, end: x + pitLen });
      x += pitLen;
    }
  }
}

// 二分查找 x 所在的地形段
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

// 世界坐标 x → 地表 y（物理用：深坑为 ABYSS，踩空即掉）
export function groundYAt(x) {
  const s = segAt(x);
  if (!s) return GROUND;
  return s.type === 'pit' ? ABYSS : GROUND;
}
