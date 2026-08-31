import test from 'node:test';
import assert from 'node:assert/strict';

globalThis.localStorage = {
  getItem: () => null,
  setItem: () => {},
};

const context = new Proxy({}, {
  get(target, key) {
    if (!(key in target)) target[key] = () => {};
    return target[key];
  },
});

globalThis.document = {
  getElementById: () => ({ getContext: () => context }),
};

const { G } = await import('../src/state.js');
const {
  DART_W, DART_H, DART_SPEED, DART_LOW_LIFT, DART_HIGH_LIFT,
  DART_WAVE_MIN, DART_WAVE_MAX, DART_GAP_T_MIN, DART_GAP_T_MAX,
  DART_FIRST_LEAD, DART_WAVE_TAIL_GAP, DMG_DART,
  DART_PATTERN_MIX, DART_PATTERN_MIX_M, DART_PATTERN_HARD_M,
  GROUND, PX_PER_M, PW, PLAYER_X, STAND_H, SLIDE_H,
} = await import('../src/constants.js');
const { resetGame } = await import('../src/player.js');
const { makeEvent, waveHigh, pickDartPattern } = await import('../src/generator.js');
const { speedAt, updateEnemies } = await import('../src/physics.js');
const { aabb } = await import('../src/utils.js');

// 重置到飞镖潮可控状态：平地、吃 dart_wave 模板（idx19）、清空障碍与生成游标
function fresh() {
  resetGame();
  G.terrain = [{ type: 'flat', start: 0, end: 30000 }];
  G.tplIdx = 19;
  G.obstacles = [];
  G.collectibles = [];
  G.scrollX = 0;
  G.gameTime = 0;
  G.nextSpawnX = 0;
}

const dartsOf = () => G.obstacles.filter((o) => o.kind === 'dart');

test('a dart wave spawns 3-5 darts on mixed rails with frozen time-gaps', () => {
  fresh();
  const pace = speedAt(3000 / PX_PER_M);          // 生成点 3000px ≈ 30m 的接近速度
  const minGap = (pace + DART_SPEED) * DART_GAP_T_MIN;
  const maxGap = (pace + DART_SPEED) * DART_GAP_T_MAX;

  makeEvent(3000);

  const darts = dartsOf();
  assert.ok(darts.length >= DART_WAVE_MIN && darts.length <= DART_WAVE_MAX,
    `wave size ${darts.length} outside [${DART_WAVE_MIN}, ${DART_WAVE_MAX}]`);
  for (const d of darts) {
    assert.equal(d.dmg, DMG_DART);
    assert.ok(d.y === GROUND - DART_LOW_LIFT || d.y === GROUND - DART_HIGH_LIFT,
      `dart y ${d.y} not on a rail {${GROUND - DART_LOW_LIFT}, ${GROUND - DART_HIGH_LIFT}}`);
  }
  // 首枚预留入屏预警距离
  assert.equal(darts[0].x, 3000 + DART_FIRST_LEAD);
  // x 严格递增，相邻间距落在 [minGap, maxGap) 时间窗内（生成即冻结，不随速度漂移）
  for (let i = 1; i < darts.length; i++) {
    const gap = darts[i].x - darts[i - 1].x;
    assert.ok(gap >= minGap && gap < maxGap, `gap ${gap} outside [${minGap}, ${maxGap})`);
  }
});

test('the two rails lock the dodge semantics: low must jump, high requires slide', () => {
  const standBox = { x: PLAYER_X, y: GROUND - STAND_H, w: PW, h: STAND_H };   // 站立 [396,462]
  const slideBox = { x: PLAYER_X, y: GROUND - SLIDE_H, w: PW, h: SLIDE_H };   // 滑铲 [430,462]
  const dartAt = (lift) => ({ x: PLAYER_X + 5, y: GROUND - lift, w: DART_W, h: DART_H });

  assert.equal(aabb(standBox, dartAt(DART_LOW_LIFT)), true);   // 低轨:站立也中
  assert.equal(aabb(slideBox, dartAt(DART_LOW_LIFT)), true);   // 低轨:滑铲也中 → 只能跳
  assert.equal(aabb(standBox, dartAt(DART_HIGH_LIFT)), true);  // 高轨:站立必中
  assert.equal(aabb(slideBox, dartAt(DART_HIGH_LIFT)), false); // 高轨:滑铲盒底之上净空 → 钻得过去
});

test('a dart flies head-on toward the player at constant speed', () => {
  fresh();
  makeEvent(3000);
  const xBefore = dartsOf()[0].x;

  updateEnemies(0.1);

  assert.equal(dartsOf()[0].x, xBefore - DART_SPEED * 0.1);
});

test('the wave tail leaves a no-dart zone by pushing the spawn cursor forward', () => {
  fresh();
  makeEvent(3000);

  const lastDartX = Math.max(...dartsOf().map((d) => d.x));
  assert.ok(G.nextSpawnX > lastDartX,
    `next spawn ${G.nextSpawnX} not beyond wave tail ${lastDartX}`);
  assert.ok(G.nextSpawnX >= lastDartX + DART_WAVE_TAIL_GAP);
});

// —— 波形编排：每波由一个 pattern 决定高低轨序列，按距离从纯波教学渐进到混合波 ——

test('waveHigh resolves the four wave patterns deterministically', () => {
  const n = 5;
  for (let i = 0; i < n; i++) {
    assert.equal(waveHigh('hop', i, n), false, `hop[${i}] should be low`);
    assert.equal(waveHigh('slide', i, n), true, `slide[${i}] should be high`);
    assert.equal(waveHigh('alt', i, n), i % 2 === 1, `alt[${i}] alternates`);
    assert.equal(waveHigh('lead', i, n), i === n - 1, `lead[${i}] only the tail is high`);
  }
});

test('pickDartPattern teaches pure waves first, then mixes in harder shapes', () => {
  const early = new Set();
  for (let i = 0; i < 200; i++) early.add(pickDartPattern(DART_PATTERN_MIX_M - 1));
  assert.deepEqual([...early].sort(), ['hop', 'slide'], 'teaching period only pure waves');

  const late = new Set();
  for (let i = 0; i < 200; i++) late.add(pickDartPattern(DART_PATTERN_HARD_M + 1));
  for (const p of DART_PATTERN_MIX) assert.ok(late.has(p), `late game should also roll ${p}`);
});

test('a generated wave sticks to its single pattern across the whole cluster', () => {
  fresh();
  G.scrollX = DART_PATTERN_HARD_M * PX_PER_M + 1000;   // 后期距离，混合波可达
  G.nextSpawnX = G.scrollX;
  makeEvent(G.scrollX);

  const darts = dartsOf();
  assert.ok(darts.length >= 2, 'need >=2 darts to judge a wave pattern');
  const pattern = darts[0].pattern;
  assert.ok(DART_PATTERN_MIX.includes(pattern), `unknown wave pattern ${pattern}`);
  darts.forEach((d, i) => {
    assert.equal(d.high, waveHigh(pattern, i, darts.length), `dart ${i} breaks the ${pattern} wave`);
  });
});