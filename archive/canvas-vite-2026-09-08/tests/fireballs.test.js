import test from 'node:test';
import assert from 'node:assert/strict';

// 测试环境桩：无 localStorage / canvas 也能跑
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
const { CLEAR_SCORE, PLAYER_X, FIRE_CD } = await import('../src/constants.js');
const { castFireballs } = await import('../src/player.js');
const { updateFireballs } = await import('../src/fireballs.js');
const { updateCollisions } = await import('../src/physics.js');

test('fire orbs burn living hazards but spare buildings and rocks', () => {
  // 布景：建筑（石柱）+ 落石 + 活物（飞镖）摆在同一区域
  Object.assign(G.player, { x: PLAYER_X, y: 462, invuln: 0 });
  G.scrollX = 0;
  G.dashShift = 0;
  G.fireCd = 0;           // 冷却就绪
  G.fireballs = null;
  G.collectScore = 0;
  G.obstacles = [
    { kind: 'pillar', x: 400, y: 382, w: 46, h: 80 },   // 固定建筑：不可烧
    { kind: 'rock', x: 460, y: 422, w: 40, h: 40 },     // 落石：不可烧
    { kind: 'dart', x: 420, y: 412, w: 34, h: 36 },     // 活物：可烧
  ];

  castFireballs();
  assert.equal(G.fireballs.orbs.length, 3);   // 一次召唤 3 枚
  assert.equal(G.fireCd, FIRE_CD);            // 进入 20 秒冷却

  castFireballs();   // 冷却中再按：应被忽略
  assert.equal(G.fireballs.orbs.length, 3);   // 没有重复召唤

  // 三枚火球直接摆进障碍群（跳过索敌，专注验证碰撞规则）
  for (const o of G.fireballs.orbs) { o.x = 430; o.y = 430; }
  updateCollisions({ x: 247, y: 396, w: 46, h: 66 });

  const kinds = G.obstacles.map((o) => o.kind);
  assert.equal(kinds.includes('dart'), false);     // 活物被焚毁
  assert.ok(kinds.includes('pillar'));             // 固定建筑完好无损
  assert.ok(kinds.includes('rock'));               // 落石完好无损
  assert.equal(G.collectScore, CLEAR_SCORE);       // 清障加分入账
  assert.equal(G.fireballs.orbs.length, 2);        // 消耗一枚，剩两枚继续环绕
});

test('orbiting fireballs lock onto nearby living hazards only', () => {
  Object.assign(G.player, { x: PLAYER_X, y: 462, invuln: 0 });
  G.scrollX = 0;
  G.dashShift = 0;
  G.fireCd = 0;
  G.fireballs = null;
  G.obstacles = [{ kind: 'dart', x: 700, y: 412, w: 34, h: 36 }];   // 索敌范围内的活物

  castFireballs();
  updateFireballs(1 / 60);   // 推进一帧：触发索敌

  assert.ok(G.fireballs.orbs.some((o) => o.mode === 'seek'), 'orb should lock onto the dart');

  // 场上换成建筑：不在索敌名单，任何火球都不应脱轨
  G.obstacles = [{ kind: 'inkwall', x: 700, y: 342, w: 56, h: 68 }];
  for (const o of G.fireballs.orbs) { o.mode = 'orbit'; o.tx = null; }
  updateFireballs(1 / 60);
  assert.ok(G.fireballs.orbs.every((o) => o.mode === 'orbit'), 'buildings must not be targeted');
});
