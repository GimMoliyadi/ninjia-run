import test from 'node:test';
import assert from 'node:assert/strict';

globalThis.localStorage = { getItem: () => null, setItem: () => {} };
globalThis.Image = class {
  constructor() { this.complete = true; this.naturalWidth = 648; }
};
const drawCalls = [];
const context = new Proxy({}, { get(target, key) {
  if (!(key in target)) {
    target[key] = key === 'createLinearGradient' || key === 'createRadialGradient'
      ? () => ({ addColorStop() {} })
      : (...args) => { drawCalls.push([key, ...args]); };
  }
  return target[key];
} });
globalThis.document = { getElementById: () => ({ getContext: () => context }) };

const { G } = await import('../src/state.js');
const { GROUND, PLAYER_X } = await import('../src/constants.js');
const { resetGame, moveOnRope } = await import('../src/player.js');
const { updateGravity } = await import('../src/physics.js');
const { MODULES } = await import('../src/generator.js');
const { spawnInfiniteLoop } = await import('../src/generator.js');
const { drawBackground } = await import('../src/render/background.js');
const { drawPlayer } = await import('../src/render/entities.js');

function fresh() {
  resetGame();
  G.scrollX = 0;
  G.dashShift = 0;
  G.terrain = [
    { type: 'slope', start: 0, end: 120, y0: GROUND, y1: GROUND - 112 },
    { type: 'rope', start: 120, end: 680, y: GROUND - 112, ropeMin: GROUND - 188, ropeMax: GROUND - 72 },
    { type: 'slope', start: 680, end: 800, y0: GROUND - 112, y1: GROUND },
  ];
  Object.assign(G.player, { x: PLAYER_X, y: GROUND - 112, onGround: true, ropeMode: false, ropeOffset: 0, ropeFlipT: 0, ropeFlipFrom: 0, ropeFlipTo: 0, vy: 0, jumps: 0, sliding: false });
}

test('entering a rope keeps the ninja attached at a continuous height', () => {
  fresh();
  updateGravity(1 / 60);
  assert.equal(G.player.ropeMode, true);
  assert.equal(G.player.y, GROUND - 112);
  assert.equal(G.player.vy, 0);
});

test('a rope frame renders the player after the background', () => {
  fresh();
  updateGravity(1 / 60);
  drawCalls.length = 0;
  assert.doesNotThrow(() => drawBackground());
  const backgroundCallCount = drawCalls.length;
  assert.doesNotThrow(() => drawPlayer());
  assert.ok(drawCalls.length > backgroundCallCount);
});

test('rope running keeps using the ninja sprite sheet', () => {
  fresh();
  updateGravity(1 / 60);
  drawCalls.length = 0;
  drawPlayer();
  assert.ok(drawCalls.some(([method]) => method === 'drawImage'));
});

test('the lower rope stance rotates the whole sprite upside down', () => {
  fresh();
  updateGravity(1 / 60);
  assert.equal(moveOnRope(1), true);
  updateGravity(0.24);
  assert.equal(G.player.y, GROUND - 112);
  drawCalls.length = 0;
  drawPlayer();
  const rotations = drawCalls.filter(([method]) => method === 'rotate').map(([, angle]) => angle);
  assert.ok(rotations.some((angle) => Math.abs(angle - Math.PI) < 1e-9));
});

test('a slope-to-rope transition captures an airborne ninja before pit fall', () => {
  fresh();
  G.player.onGround = false;
  G.player.y = GROUND - 190;
  G.player.vy = 260;
  G.scrollX = 210;
  updateGravity(1 / 60);
  assert.equal(G.player.ropeMode, true);
  assert.equal(G.player.onGround, true);
  assert.equal(G.player.vy, 0);
  assert.ok(G.player.y >= GROUND - 188 && G.player.y <= GROUND - 72);
});

test('rope flips interpolate between upright and upside-down stances', () => {
  fresh();
  updateGravity(1 / 60);
  assert.equal(G.player.ropeOffset, 0);
  assert.equal(moveOnRope(-1), false);
  assert.equal(moveOnRope(1), true);
  updateGravity(0.12);
  assert.ok(G.player.ropeOffset > 0 && G.player.ropeOffset < 1);
  updateGravity(0.2);
  assert.equal(G.player.ropeOffset, 1);
  assert.equal(moveOnRope(1), false);
  assert.equal(moveOnRope(-1), true);
});

test('leaving the rope restores ordinary slope physics', () => {
  fresh();
  G.scrollX = 650;
  G.player.x = PLAYER_X;
  G.player.ropeMode = true;
  G.player.ropeOffset = 0;
  updateGravity(1 / 60);
  assert.equal(G.player.ropeMode, false);
  assert.equal(G.player.onGround, true);
  assert.equal(G.player.vy, 0);
});

test('a long rope route keeps the ninja present for its whole section', () => {
  fresh();
  G.terrain = [
    { type: 'flat', start: 0, end: 300, y: GROUND },
    { type: 'slope', start: 300, end: 480, y0: GROUND, y1: GROUND - 112 },
    { type: 'rope', start: 480, end: 1800, y: GROUND - 112, ropeMin: GROUND - 188, ropeMax: GROUND - 72, route: true },
    { type: 'slope', start: 1800, end: 1980, y0: GROUND - 112, y1: GROUND },
  ];
  let sawRope = false;
  for (let i = 0; i < 260; i++) {
    G.speed = 360;
    G.scrollX += G.speed / 60;
    updateGravity(1 / 60);
    if (G.player.ropeMode) {
      sawRope = true;
      assert.ok(Number.isFinite(G.player.y));
      assert.ok(G.player.y >= 0 && G.player.y <= 540);
    }
  }
  assert.equal(sawRope, true);
  assert.equal(G.player.ropeMode, false);
  assert.equal(G.player.onGround, true);
});

test('the generated rope module is a standalone long route with hazards inside it', () => {
  const mod = MODULES.find((m) => m.name === 'rope');
  const ropePart = mod.parts.find((part) => part.type === 'rope');
  assert.ok(ropePart.width >= 2000);
  assert.equal(ropePart.route, true);
  assert.equal(mod.parts[0].type, 'flat');
  assert.equal(mod.parts.at(-1).type, 'flat');
});

test('rope hazards remain available while the player traverses the route', () => {
  fresh();
  const routeStart = 120;
  const routeEnd = 2200;
  G.terrain = [{ type: 'rope', start: routeStart, end: routeEnd, y: GROUND - 112, ropeMin: GROUND - 188, ropeMax: GROUND - 72, route: true }];
  G.obstacles = [{ kind: 'spike', x: 180, y: GROUND - 180, w: 24, h: 72, routeStart, routeEnd }];
  G.player.ropeMode = true;
  G.player.ropeRouteStart = routeStart;
  G.player.ropeRouteEnd = routeEnd;
  G.scrollX = 700;
  spawnInfiniteLoop();
  assert.ok(G.obstacles.some((ob) => ob.routeStart === routeStart && ob.x === 180));
});
