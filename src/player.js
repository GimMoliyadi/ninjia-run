import { G, ST } from './state.js';
import {
  START_SPEED, PLAYER_X, JUMP_V, JUMP2_V, DIVE_V, AIR_CANCEL_V, JUMP_BUFFER,
  DASH_JUMP_BOOST_DUR, DASH_SHIFT_MAX,
  DOUBLE_TAP_MS, CLONE_DURATION, CLONE_OFFSET, CLONE_CAST_INVULN_T, ENERGY_MAX, HP_MAX,
  W,
} from './constants.js';
import { initTerrain, groundYAt } from './terrain.js';
import { burst, inkBurst } from './particles.js';
import { updateMetrics } from './physics.js';

export function resetGame() {
  G.state = ST.RUN;
  initTerrain();
  G.scrollX = 0; G.speed = START_SPEED; G.gameTime = 0;
  G.score = 0; G.collectScore = 0; G.distM = 0;
  G.combo = 0; G.comboTimer = 0; G.energy = 0;
  G.deathT = 0; G.deadAt = 0; G.newBest = false;
  const p = G.player;
  p.x = PLAYER_X; p.y = groundYAt(PLAYER_X); p.vy = 0;
  p.onGround = true; p.jumps = 0; p.sliding = false; p.slideT = 0; p.slideQueued = false;
  p.jumpT = 0;
  p.dashBoostT = 0; p.dashCarrying = false;
  p.invuln = 0; p.shieldT = 0; p.runT = 0; p.hp = HP_MAX; p.hpBarT = 0;
  G.wallPushed = false;
  G.dashShift = 0;
  G.dashHoldT = 0;
  G.obstacles = []; G.collectibles = []; G.particles = [];
  G.clone = null;
  G.lastEventKind = 'rest';
  G.tplIdx = 0;
  G.coyote = 0; G.jumpBuf = 0;
  G.airDownT = -1e9;
  G.nextSpawnX = W + 420;
}

export function die() {
  G.state = ST.DEAD;
  G.clone = null;
  G.deadAt = G.gameTime;
  // 结算分
  updateMetrics();
  if (G.score > G.best) { G.best = G.score; G.newBest = true; localStorage.setItem('inkNinjaBest', G.best); }
  burst(G.player.x + G.dashShift, G.player.y - 30, 46, { c: '40,40,46', sp: 260, up: 220, g: 800, s: [2, 7], l: [0.4, 1.0] });
  burst(G.player.x + G.dashShift, G.player.y - 30, 10, { c: '165,58,46', sp: 200, up: 160, g: 700, s: [2, 6], l: [0.4, 0.9] });
}

export function finishSlide() {
  if (!G.player.sliding) return false;
  G.player.sliding = false;
  G.player.slideT = 0;
  G.player.slideQueued = false;
  return true;
}

export function doJump() {
  const p = G.player;
  if (p.onGround || G.coyote > 0) {
    const slideJump = p.sliding;
    p.vy = -JUMP_V; p.onGround = false; p.jumps = 1; p.jumpT = 0;
    if (slideJump) {
      finishSlide();
      // 冲刺窗口独立于跳跃姿态，二段跳只继承剩余窗口，不重置计时。
      p.dashBoostT = DASH_JUMP_BOOST_DUR;
      p.dashCarrying = true;
    } else if (G.dashShift > 0) {
      // 滑铲刚结束、前移尚未回位：普通起跳也继承剩余前移，空中保持不衰减。
      p.dashCarrying = true;
    }
    G.coyote = 0; G.jumpBuf = 0;
  } else if (p.jumps === 0) {
    // 空中首跳：没跳过就离地（掉坑 / 被墙顶落），按一段跳计，保留二段跳救场
    const slideJump = p.sliding;
    p.vy = -JUMP_V; p.jumps = 1; p.jumpT = 0;
    if (slideJump) {
      finishSlide();
      p.dashBoostT = DASH_JUMP_BOOST_DUR;
      p.dashCarrying = true;
    }
    G.coyote = 0; G.jumpBuf = 0;
  } else if (p.jumps === 1) {
    const slideJump = p.sliding;
    p.vy = -JUMP2_V; p.jumps = 2; p.jumpT = 0;
    if (slideJump) {
      finishSlide();
      // 普通起跳后再俯冲滑铲接二段跳，也进入同一套本地冲刺。
      p.dashBoostT = DASH_JUMP_BOOST_DUR;
      p.dashCarrying = true;
    }
    G.coyote = 0; G.jumpBuf = 0;
    burst(p.x + G.dashShift, p.y, 10, { c: '90,90,100', sp: 150, up: 60, g: 500, s: [1, 3], l: [0.2, 0.5] });
  } else {
    G.jumpBuf = JUMP_BUFFER;     // 已用尽两跳，缓冲到落地自动起跳
  }
}

export function startSlide() {
  const p = G.player;
  // 滑铲中再次按下时缓冲下一段，当前动作结束的同一帧直接衔接。
  if (p.sliding) { p.slideQueued = true; return; }
  if (p.onGround) {
    p.sliding = true; p.slideT = 0; p.slideQueued = false;
    return;
  }
  // 空中：
  const now = performance.now();
  const rising = p.vy < 0;
  if (rising) {
    if (now - G.airDownT < DOUBLE_TAP_MS) {
      // 上升中连按两次 ↓：俯冲 + 落地后保持滑铲冲刺
      p.vy = DIVE_V;
      p.sliding = true;
      G.dashShift = Math.max(G.dashShift, DASH_SHIFT_MAX * 0.6);
      burst(p.x + G.dashShift, p.y, 14, { c: '90,90,100', sp: 200, up: 30, g: 700, s: [1, 4], l: [0.2, 0.6] });
    } else {
      // 上升或空中按一次 ↓：快速打断起跳，加速砸落（不冲刺）
      p.vy = AIR_CANCEL_V;
      burst(p.x + G.dashShift, p.y, 10, { c: '90,90,100', sp: 120, up: 20, g: 600, s: [1, 3], l: [0.2, 0.4] });
    }
  } else {
    // 已在下落：直接俯冲滑铲
    p.vy = DIVE_V;
    p.sliding = true;
    G.dashShift = Math.max(G.dashShift, DASH_SHIFT_MAX * 0.6);
    burst(p.x + G.dashShift, p.y, 14, { c: '90,90,100', sp: 200, up: 120, g: 600, s: [1, 4], l: [0.3, 0.6] });
  }
  G.airDownT = now;
}

export function castNinjutsu() {
  const p = G.player;
  if (G.energy < ENERGY_MAX || p.invuln > 0) return;
  G.energy = 0;
  p.invuln = CLONE_CAST_INVULN_T;
  G.clone = { age: 0, duration: CLONE_DURATION };
  inkBurst(p.x + G.dashShift + CLONE_OFFSET, p.y - 42, 20, 1.2);
}

export function startGame() { resetGame(); }
