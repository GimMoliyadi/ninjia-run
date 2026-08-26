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
const { CLEAR_SCORE, COIN_R, DASH_SHIFT_MAX, ENERGY_MAX, GROUND, NINJUTSU_DURATION, PLAYER_X, SHIELD_DUR, SHIELD_R, SLIDE_ACCEL_T, SLIDE_DUR, START_SPEED, W } = await import('../src/constants.js');
const { castNinjutsu, doJump, startSlide } = await import('../src/player.js');
const { makeEvent } = await import('../src/generator.js');
const { updateNinjutsu } = await import('../src/ninjutsu.js');
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
  G.wallPushed = false;

  startSlide();
  const shiftBeforeNextFrame = G.dashShift;
  updateSpeed(1 / 60);

  assert.ok(
    G.dashShift >= shiftBeforeNextFrame,
    `dash shift moved backward from ${shiftBeforeNextFrame} to ${G.dashShift}`,
  );
});

test('a slide completes before the next one starts', () => {
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
  G.wallPushed = false;

  startSlide();
  updateSpeed(SLIDE_DUR - 0.01);
  assert.equal(G.player.sliding, true);

  updateSpeed(0.02);
  assert.equal(G.player.sliding, false);

  startSlide();
  assert.equal(G.player.sliding, true);
});

test('a buffered slide chains without a standing collision frame', () => {
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

  startSlide();
  updateSpeed(SLIDE_DUR - 0.04);
  startSlide();
  assert.equal(G.player.slideQueued, true);

  updateSpeed(0.05);
  assert.equal(G.player.sliding, true);
  assert.equal(G.player.slideQueued, false);
  assert.ok(G.player.slideT < 0.02);
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
  G.tplIdx = 1; // jump1
  G.obstacles = [];
  G.collectibles = [{ x: 3000, y: GROUND - 48, type: 'coin', r: COIN_R, taken: false }];

  makeEvent(3000);

  assert.equal(G.collectibles.some((coin) => coin.type === 'coin' && coin.x === 3000), false);
});

test('the opening route keeps each obstacle family in its own section', () => {
  const kinds = [];
  G.terrain = [{ type: 'flat', start: 0, end: 30000 }];
  G.gameTime = 0;
  G.obstacles = [];
  G.collectibles = [];
  G.tplIdx = 0;

  for (let i = 0; i < 26; i++) {
    makeEvent(2000 + i * 900);
    if (!G.lastEventKind.startsWith('reward') && G.lastEventKind !== 'coins_flat') kinds.push(G.lastEventKind);
  }

  assert.deepEqual(kinds, ['jump1', 'jump1', 'jump2', 'slide', 'slide', 'slide', 'ninja', 'dart_wave', 'ninja', 'dart_wave', 'pillar', 'pillar']);
});

test('ninjutsu wave destroys only obstacles it reaches', () => {
  Object.assign(G.player, {
    x: PLAYER_X,
    y: 462,
    invuln: 0,
  });
  G.scrollX = 0;
  G.dashShift = 0;
  G.energy = ENERGY_MAX;
  G.collectScore = 0;
  G.ninjutsu = null;
  G.obstacles = [
    { kind: 'spike', x: 500, y: 412, w: 32, h: 50 },
    { kind: 'spike', x: 1200, y: 412, w: 32, h: 50 },
  ];

  castNinjutsu();
  assert.equal(G.energy, 0);
  assert.ok(G.ninjutsu);
  assert.equal(G.obstacles.length, 2);

  updateNinjutsu(0.22);
  assert.deepEqual(G.obstacles.map((ob) => ob.x), [1200]);

  updateNinjutsu(NINJUTSU_DURATION);
  assert.equal(G.ninjutsu, null);
});
