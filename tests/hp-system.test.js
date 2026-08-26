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

const { G, ST } = await import('../src/state.js');
const { CLEAR_SCORE, DMG_NINJA, DMG_PILLAR, DMG_SPIKE, DMG_DART, HIT_INVULN_T, HIT_KNOCK_PX, HP_MAX, HP_REGEN, HP_BAR_FADE, GROUND, NINJA_W, NINJA_H, PLAYER_X, DART_W, DART_H, DART_HIGH_LIFT } = await import('../src/constants.js');
const { resetGame } = await import('../src/player.js');
const { updateCollisions, updateSpeed } = await import('../src/physics.js');
const { makeEvent } = await import('../src/generator.js');
const { update } = await import('../src/engine.js');

// 重置到可预测状态：满血、站地、平地、空场，避免随机地形影响
function fresh() {
  resetGame();
  G.terrain = [{ type: 'flat', start: 0, end: 100000 }];
  G.player.y = GROUND;
  G.player.invuln = 0;
  G.player.shieldT = 0;
  G.player.hp = HP_MAX;
  G.scrollX = 0;
  G.dashShift = 0;
  G.obstacles = [];
  G.collectScore = 0;
}

function ninjaOb(x = 200) {
  return { kind: 'ninja', x, y: GROUND - NINJA_H, w: NINJA_W, h: NINJA_H, dmg: DMG_NINJA };
}
const boxOf = (ob) => ({ x: ob.x, y: ob.y, w: ob.w, h: ob.h });

test('a ninja strike costs 30 HP and grants hit invincibility', () => {
  fresh();
  G.obstacles = [ninjaOb()];
  const res = updateCollisions(boxOf(G.obstacles[0]));

  assert.equal(res, false);
  assert.equal(G.player.hp, HP_MAX - DMG_NINJA);
  assert.equal(G.player.invuln, HIT_INVULN_T);
  assert.equal(G.state, ST.RUN);
});

test('hit invincibility blocks further damage for the window', () => {
  fresh();
  G.obstacles = [ninjaOb()];
  updateCollisions(boxOf(G.obstacles[0]));
  const hpAfterFirst = G.player.hp;

  G.obstacles = [ninjaOb(250)];
  const res = updateCollisions(boxOf(G.obstacles[0]));

  assert.equal(res, false);
  assert.equal(G.player.hp, hpAfterFirst);
});

test('after invincibility expires the same hazard damages again', () => {
  fresh();
  G.obstacles = [ninjaOb()];
  updateCollisions(boxOf(G.obstacles[0]));

  G.player.invuln = 0;
  const res = updateCollisions(boxOf(G.obstacles[0]));

  assert.equal(res, false);
  assert.equal(G.player.hp, HP_MAX - 2 * DMG_NINJA);
});

test('pillar and spike deal their own damage values', () => {
  fresh();
  G.obstacles = [{ kind: 'pillar', x: 200, y: GROUND - 80, w: 46, h: 80, dmg: DMG_PILLAR }];
  updateCollisions(boxOf(G.obstacles[0]));
  assert.equal(G.player.hp, HP_MAX - DMG_PILLAR);

  fresh();
  G.obstacles = [{ kind: 'spike', x: 200, y: GROUND - 72, w: 18, h: 72, dmg: DMG_SPIKE }];
  updateCollisions(boxOf(G.obstacles[0]));
  assert.equal(G.player.hp, HP_MAX - DMG_SPIKE);
});

test('HP reaching zero ends the run', () => {
  fresh();
  G.player.hp = DMG_NINJA - 1;
  G.obstacles = [ninjaOb()];

  const res = updateCollisions(boxOf(G.obstacles[0]));

  assert.equal(res, true);
  assert.equal(G.state, ST.DEAD);
});

test('HP regenerates over time and caps at the maximum', () => {
  fresh();
  G.player.hp = 70;
  update(0.5);
  assert.equal(G.player.hp, 70 + HP_REGEN * 0.5);

  G.player.hp = HP_MAX - 1;
  update(0.5);
  assert.equal(G.player.hp, HP_MAX);
});

test('a hit knocks the player back, then the stance recovers', () => {
  fresh();
  G.obstacles = [ninjaOb()];
  updateCollisions(boxOf(G.obstacles[0]));

  // 受击瞬间被弹到默认站位左侧 = 身后（画面左）
  assert.equal(G.player.x, PLAYER_X - HIT_KNOCK_PX);

  // 奔跑恢复逻辑把站位平滑拉回默认
  updateSpeed(0.5);
  assert.equal(G.player.x, PLAYER_X);
});

test('the HP bar stays hidden until a hit, then fades after full recovery', () => {
  fresh();
  assert.equal(G.player.hpBarT, 0);            // 满血时血条隐藏

  G.obstacles = [ninjaOb()];
  updateCollisions(boxOf(G.obstacles[0]));
  assert.equal(G.player.hpBarT, 1);            // 受击点亮

  G.player.hp = HP_MAX;                        // 回满后开始淡出
  update(HP_BAR_FADE - 0.1);
  assert.ok(G.player.hpBarT > 0);              // 淡出中仍可见
  update(0.2);
  assert.equal(G.player.hpBarT, 0);            // 完全淡出隐藏
});

test('an active shield shatters an ordinary hazard without HP loss', () => {
  fresh();
  G.player.shieldT = 5;
  G.obstacles = [ninjaOb()];

  const res = updateCollisions(boxOf(G.obstacles[0]));

  assert.equal(res, false);
  assert.equal(G.obstacles.length, 0);
  assert.equal(G.collectScore, CLEAR_SCORE);
  assert.equal(G.player.hp, HP_MAX);
});

test('a dart hit costs spike-level HP without killing', () => {
  fresh();
  G.obstacles = [{ kind: 'dart', x: 200, y: GROUND - DART_HIGH_LIFT, w: DART_W, h: DART_H, dmg: DMG_DART }];

  const res = updateCollisions(boxOf(G.obstacles[0]));

  assert.equal(res, false);
  assert.equal(G.player.hp, HP_MAX - DMG_DART);
  assert.equal(G.state, ST.RUN);
});

test('an active shield shatters a dart without HP loss', () => {
  fresh();
  G.player.shieldT = 5;
  G.obstacles = [{ kind: 'dart', x: 200, y: GROUND - DART_HIGH_LIFT, w: DART_W, h: DART_H, dmg: DMG_DART }];

  const res = updateCollisions(boxOf(G.obstacles[0]));

  assert.equal(res, false);
  assert.equal(G.obstacles.length, 0);
  assert.equal(G.collectScore, CLEAR_SCORE);
  assert.equal(G.player.hp, HP_MAX);
});

test('a ceiling beam pushes without HP loss', () => {
  fresh();
  G.obstacles = [{ kind: 'beam', x: 600, y: 0, w: 40, h: GROUND - 52 }];

  const res = updateCollisions(boxOf(G.obstacles[0]));

  assert.equal(res, false);
  assert.equal(G.wallPushed, true);
  assert.equal(G.player.hp, HP_MAX);
  assert.equal(G.state, ST.RUN);
});

test('the jump2 template spawns both spikes with damage', () => {
  fresh();
  G.tplIdx = 5; // jump2

  makeEvent(3000);

  assert.equal(G.obstacles.length, 2);
  assert.ok(G.obstacles.every((o) => o.kind === 'spike'));
  assert.ok(G.obstacles.every((o) => o.dmg === DMG_SPIKE));
  assert.equal(G.lastEventKind, 'jump2');
});

test('the ninja template spawns a ninja with its damage', () => {
  fresh();
  G.tplIdx = 15; // ninja

  makeEvent(3000);

  assert.equal(G.obstacles.length, 1);
  assert.equal(G.obstacles[0].kind, 'ninja');
  assert.equal(G.obstacles[0].dmg, DMG_NINJA);
  assert.equal(G.lastEventKind, 'ninja');
});
