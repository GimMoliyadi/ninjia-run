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
const { CLEAR_SCORE, COIN_R, DASH_SHIFT_MAX, ENERGY_MAX, GROUND, PLAYER_X, RASENGAN_LIFE, SHIELD_DUR, SHIELD_R, SLIDE_ACCEL_T, SLIDE_DUR, SLIDE_RECOVER_T, START_SPEED, W } = await import('../src/constants.js');
const { castNinjutsu, doJump, startSlide } = await import('../src/player.js');
const { makeEvent } = await import('../src/generator.js');
const { updateNinjutsu } = await import('../src/ninjutsu.js');
const { SPAWN_CONFIG } = await import('../src/spawn-config.js');
const { collectPickups, speedAt, updateCollisions, updateSpeed } = await import('../src/physics.js');

test('starting a consecutive slide does not reset the ninja position', () => {
  Object.assign(G.player, {
    x: PLAYER_X,
    onGround: true,
    sliding: false,
    slideT: 0,
    dashBoostT: 0,
    dashCarrying: false,
  });
  G.obstacles = [];
  G.scrollX = 0;
  G.dashShift = DASH_SHIFT_MAX;
  G.dashHoldT = 0.2;
  G.slideLockT = 0;   // 清掉起身间歇，保证本测试从零开始
  G.wallPushed = false;

  startSlide();
  const shiftBeforeNextFrame = G.dashShift;
  updateSpeed(1 / 60);

  assert.ok(
    G.dashShift >= shiftBeforeNextFrame,
    `dash shift moved backward from ${shiftBeforeNextFrame} to ${G.dashShift}`,
  );
});

test('a slide ends, and a fresh press waits out the short recovery', () => {
  Object.assign(G.player, {
    x: PLAYER_X,
    onGround: true,
    sliding: false,
    slideT: 0,
    dashBoostT: 0,
    dashCarrying: false,
  });
  G.obstacles = [];
  G.scrollX = 0;
  G.dashShift = 0;
  G.dashHoldT = 0;
  G.slideLockT = 0;   // 清掉可能残留的起身间歇，本测试从零开始
  G.wallPushed = false;

  startSlide();   // 按下 ↓：第一段滑铲开始
  updateSpeed(SLIDE_DUR - 0.01);   // 推进到接近本段时长上限
  assert.equal(G.player.sliding, true);   // 本段仍在滑铲中

  updateSpeed(0.02);   // 跨过时长上限：本段结束
  assert.equal(G.player.sliding, false);   // 先起身站立
  assert.ok(G.slideLockT > 0);             // 进入起身间歇（约 0.1s 内不可直接续滑）

  startSlide();   // 间歇内立刻再按：只记录缓冲，不马上续滑
  assert.equal(G.player.sliding, false);    // 仍在站立，等间歇走完
  assert.equal(G.player.slideQueued, true); // 请求已被缓冲

  updateSpeed(SLIDE_RECOVER_T);   // 间歇倒计时走完
  assert.equal(G.player.sliding, true);     // 自动衔接下一段滑铲
  assert.equal(G.player.slideQueued, false);
});

test('a buffered slide waits for the recovery interval then resumes', () => {
  Object.assign(G.player, {
    x: PLAYER_X,
    y: 462,
    onGround: true,
    sliding: false,
    slideT: 0,
    slideQueued: false,
    dashBoostT: 0,
    dashCarrying: false,
  });
  G.scrollX = 0;
  G.dashShift = 0;
  G.dashHoldT = 0;
  G.slideLockT = 0;   // 清掉可能残留的起身间歇，保证本测试从零开始

  startSlide();                     // 第一段滑铲开始
  updateSpeed(SLIDE_DUR - 0.04);    // 推进到接近本段末尾
  startSlide();                     // 段末再按 ↓：缓冲下一段请求
  assert.equal(G.player.slideQueued, true);

  updateSpeed(0.05);                // 跨过时长上限：本段结束
  assert.equal(G.player.sliding, false);        // 先起身，不再无缝续滑
  assert.ok(G.slideLockT > 0);                  // 进入起身间歇

  updateSpeed(SLIDE_RECOVER_T);     // 间歇倒计时走完
  assert.equal(G.player.sliding, true);         // 自动衔接下一段滑铲
  assert.equal(G.player.slideQueued, false);
  assert.ok(G.player.slideT < 0.02);            // 衔接段刚起步，滑铲计时从零附近开始
});

test('sliding keeps acceleration feedback free of stored visual ghosts', () => {
  Object.assign(G.player, {
    x: PLAYER_X,
    y: 462,
    onGround: true,
    sliding: false,
    slideT: 0,
  });
  G.scrollX = 0;
  G.dashShift = 0;
  G.dashHoldT = 0;
  G.slideLockT = 0;   // 清掉起身间歇，保证本测试从零开始
  delete G.afterimages;

  startSlide();
  updateSpeed(0.08);
  assert.equal(Object.hasOwn(G, 'afterimages'), false);
});

test('sliding increases the actual world speed', () => {
  Object.assign(G.player, {
    x: PLAYER_X,
    y: 462,
    onGround: true,
    sliding: false,
    slideT: 0,
    dashBoostT: 0,
    dashCarrying: false,
  });
  G.scrollX = 0;
  G.dashShift = 0;
  G.dashHoldT = 0;
  G.slideLockT = 0;   // 清掉起身间歇，保证本测试从零开始

  const base = speedAt(0);
  startSlide();
  updateSpeed(SLIDE_ACCEL_T);

  assert.ok(G.speed > base, `expected slide speed above ${base}, got ${G.speed}`);
  assert.ok(G.scrollX > base * SLIDE_ACCEL_T);
});

test('slide jump temporarily scrolls faster than the base running speed', () => {
  Object.assign(G.player, {
    x: PLAYER_X,
    y: 462,
    onGround: true,
    sliding: true,
    slideT: 0.3,
    dashBoostT: 0,
    dashCarrying: false,
  });
  G.scrollX = 0;
  G.dashShift = DASH_SHIFT_MAX;
  G.dashHoldT = 0;
  G.slideLockT = 0;   // 清掉起身间歇，保证本测试从零开始

  doJump();
  updateSpeed(1 / 60);

  assert.ok(G.speed > speedAt(0), `expected speed boost, got ${G.speed}`);
});

test('each jump starts its own action animation timer', () => {
  Object.assign(G.player, {
    x: PLAYER_X,
    y: 462,
    onGround: true,
    sliding: false,
    jumps: 0,
    jumpT: 0.4,
  });
  G.coyote = 0;
  G.jumpBuf = 0;

  doJump();
  assert.equal(G.player.jumps, 1);
  assert.equal(G.player.jumpT, 0);

  G.player.onGround = false;
  G.player.jumpT = 0.25;
  doJump();
  assert.equal(G.player.jumps, 2);
  assert.equal(G.player.jumpT, 0);
});

test('collecting a shield grants ten seconds of protection', () => {
  G.player.shieldT = 0;
  G.collectibles = [{ x: 300, y: 400, type: 'shield', r: SHIELD_R, taken: false }];

  collectPickups({ x: 285, y: 385, w: 30, h: 30 });

  assert.equal(G.player.shieldT, SHIELD_DUR);
  assert.equal(G.collectibles.length, 0);
});

test('an active shield destroys an obstacle collision', () => {
  Object.assign(G.player, { y: 462, invuln: 0, shieldT: 2 });
  G.obstacles = [{ kind: 'spike', x: 280, y: 412, w: 32, h: 50 }];
  G.collectScore = 0;

  assert.equal(updateCollisions({ x: 280, y: 412, w: 46, h: 50 }), false);
  assert.equal(G.obstacles.length, 0);
  assert.equal(G.collectScore, CLEAR_SCORE);
});

test('a newly generated obstacle removes an overlapping earlier coin', () => {
  G.terrain = [{ type: 'flat', start: 0, end: 10000 }];
  G.scrollX = 0;
  G.gameTime = 0;
  G.forceEvent = 'jump1'; // 指定模板：jump1
  G.obstacles = [];
  G.collectibles = [{ x: 3000, y: GROUND - 48, type: 'coin', r: COIN_R, taken: false }];

  makeEvent(3000);

  assert.equal(G.collectibles.some((coin) => coin.type === 'coin' && coin.x === 3000), false);
});

test('weighted spawning alternates danger and calm events strictly', () => {
  // 固定权重做确定性验证：jump1 是唯一危险源，coins_flat 是唯一奖励源
  SPAWN_CONFIG.mode = 'weights';
  SPAWN_CONFIG.dangerWeights = { jump1: 4 };
  SPAWN_CONFIG.calmWeights = { coins_flat: 3 };
  G.terrain = [{ type: 'flat', start: 0, end: 60000 }];
  G.gameTime = 0;
  G.obstacles = [];
  G.collectibles = [];
  G.lastEventKind = 'coin';
  G.lastDangerKind = null;
  G.forceEvent = null;

  const kinds = [];
  for (let i = 0; i < 20; i++) {
    makeEvent(2000 + i * 1000);
    kinds.push(G.lastEventKind);
  }

  // 危险与奖励严格交替：偶数位 danger，奇数位 calm
  for (let i = 0; i < kinds.length; i++) {
    assert.equal(kinds[i], i % 2 === 0 ? 'jump1' : 'coins_flat', `kind[${i}] = ${kinds[i]}`);
  }

  // 还原默认模式，避免影响本文件其他用例
  SPAWN_CONFIG.mode = 'cycle';
});

test('rasengan pierces the obstacle it hits, then expires', () => {
  Object.assign(G.player, { x: PLAYER_X, y: 462, invuln: 0 });
  G.scrollX = 0;
  G.dashShift = 0;
  G.energy = ENERGY_MAX;
  G.collectScore = 0;
  G.rasengan = null;
  G.obstacles = [
    { kind: 'spike', x: 380, y: 412, w: 32, h: 50 },
    { kind: 'spike', x: 1500, y: 412, w: 32, h: 50 },
  ];

  castNinjutsu();
  assert.equal(G.energy, 0);
  assert.ok(G.rasengan);
  assert.ok(G.rasengan.x > PLAYER_X);   // 出手点在玩家前方的掌心位置
  assert.equal(G.obstacles.length, 2);

  // 螺旋丸前飞命中第一个尖刺：击碎清障加分，本体连穿不消失
  updateNinjutsu(0.05);
  updateCollisions({ x: 247, y: 396, w: 46, h: 66 });
  assert.deepEqual(G.obstacles.map((ob) => ob.x), [1500]);
  assert.ok(G.rasengan);
  assert.equal(G.collectScore, CLEAR_SCORE);

  // 飞满寿命后自行墨散消隐
  updateNinjutsu(RASENGAN_LIFE);
  assert.equal(G.rasengan, null);
});
