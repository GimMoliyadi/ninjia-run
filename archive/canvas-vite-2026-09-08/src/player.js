import { G, ST } from './state.js';
import {
  START_SPEED, PLAYER_X, JUMP_V, JUMP2_V, DIVE_V, AIR_CANCEL_V, JUMP_BUFFER,
  DASH_JUMP_BOOST_DUR, DASH_SHIFT_MAX,
  DOUBLE_TAP_MS, RASENGAN_LIFE, RASENGAN_LIFT, RASENGAN_CAST_INVULN_T, ENERGY_MAX, HP_MAX,
  FIRE_CD, FIRE_ORB_COUNT, FIRE_LIFE, FIRE_LIFT,
  W,
} from './constants.js';
import { initTerrain, groundYAt, segAt } from './terrain.js';
import { burst, inkBurst, splatBurst } from './particles.js';
import { updateMetrics } from './physics.js';

export function resetGame() {
  G.state = ST.RUN;
  initTerrain();
  G.scrollX = 0; G.speed = START_SPEED; G.gameTime = 0;
  G.score = 0; G.collectScore = 0; G.distM = 0;
  G.energy = 0;
  G.deathT = 0; G.deadAt = 0; G.newBest = false;
  const p = G.player;
  p.x = PLAYER_X; p.y = groundYAt(PLAYER_X); p.vy = 0;
  p.onGround = true; p.jumps = 0; p.sliding = false; p.slideT = 0; p.slideQueued = false;
  p.jumpT = 0;
  p.dashBoostT = 0; p.dashCarrying = false;
  p.invuln = 0; p.shieldT = 0; p.runT = 0; p.hp = HP_MAX; p.hpBarT = 0;
  p.heldJump = false;
  p.dropThroughT = 0;
  p.ropeMode = false; p.ropeOffset = 0; p.ropeFlipT = 0;
  p.ropeFlipFrom = 0; p.ropeFlipTo = 0;
  p.ropeRouteStart = null; p.ropeRouteEnd = null;
  G.wallPushed = false;
  G.dashShift = 0;
  G.dashHoldT = 0;
  G.slideLockT = 0;   // 清掉起身间歇：重开后第一次按 ↓ 立即生效
  G.obstacles = []; G.collectibles = []; G.particles = [];
  G.rasengan = null;
  G.fireballs = null;
  G.fireCd = 0;    // 重开清冷却：新的一局火球术立即可用
  G.lastEventKind = 'rest';
  G.lastDangerKind = null;   // 清危险记忆：重开防重复限制从零开始
  G.tplIdx = 0;              // 固定精锐编排从第一段开始
  G.forceEvent = null;
  G.coyote = 0; G.jumpBuf = 0;
  G.airDownT = -1e9;
  G.nextSpawnX = W + 420;
  G.moduleName = null;
}

export function die() {
  G.state = ST.DEAD;
  G.rasengan = null;
  G.fireballs = null;   // 死亡清空环绕中的火球
  G.deadAt = G.gameTime;
  // 结算分
  updateMetrics();
  if (G.score > G.best) { G.best = G.score; G.newBest = true; localStorage.setItem('inkNinjaBest', G.best); }
  burst(G.player.x + G.dashShift, G.player.y - 30, 46, { c: '40,40,46', sp: 260, up: 220, g: 800, s: [2, 7], l: [0.4, 1.0] });
  burst(G.player.x + G.dashShift, G.player.y - 30, 10, { c: '165,58,46', sp: 200, up: 160, g: 700, s: [2, 6], l: [0.4, 0.9] });
  splatBurst(G.player.x + G.dashShift, G.player.y - 30, 4, 1, 1.5);   // 死亡：大范围泼墨溅开
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
  // 起跳即清掉滑铲缓冲与起身间歇：跳起来就不该再自动衔接下一段滑铲
  p.slideQueued = false;
  G.slideLockT = 0;
  if (p.onGround || G.coyote > 0) {
    const slideJump = p.sliding;
    p.vy = -JUMP_V; p.onGround = false; p.jumps = 1; p.jumpT = 0;
    p.heldJump = G.jumpHeld;
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
    p.heldJump = G.jumpHeld;
    if (slideJump) {
      finishSlide();
      p.dashBoostT = DASH_JUMP_BOOST_DUR;
      p.dashCarrying = true;
    }
    G.coyote = 0; G.jumpBuf = 0;
  } else if (p.jumps === 1) {
    const slideJump = p.sliding;
    p.vy = -JUMP2_V; p.jumps = 2; p.jumpT = 0;
    p.heldJump = G.jumpHeld;
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
  if (p.ropeMode) {
    moveOnRope(1);
    return;
  }
  // 滑铲进行中再次按下：只记录缓冲请求，等本段结束 + 起身间歇走完再自动衔接
  if (p.sliding) { p.slideQueued = true; return; }
  // 刚结束滑铲的起身间歇内按下：同样先缓冲，不立刻续滑，保证两段之间有停顿
  if (p.onGround && G.slideLockT > 0) { p.slideQueued = true; return; }
  if (p.onGround) {
    const seg = segAt(G.scrollX + p.x + G.dashShift);
    if (seg?.type === 'platform') {
      p.onGround = false;
      p.dropThroughT = 0.24;
      p.vy = 180;
      p.y += 6;
      return;
    }
    // 贴地起手：进入滑铲姿态，并清掉可能残留的缓冲标记
    p.sliding = true; p.slideT = 0; p.slideQueued = false;
    // 起手前移：按下瞬间给一小段"窜出去"的位移反馈，不等缓入曲线慢慢爬升
    G.dashShift = Math.max(G.dashShift, DASH_SHIFT_MAX * 0.25);
    return;
  }
  // —— 空中按下 ↓（俯冲/打断起跳）——
  const now = performance.now();            // 记录本次按键时刻，用于双按判定
  const rising = p.vy < 0;                  // 上升还是下落？决定走哪条空中分支
  if (rising) {
    if (now - G.airDownT < DOUBLE_TAP_MS) {
      // 上升中连按两次 ↓：触发俯冲滑铲，落地后保持滑铲冲刺
      p.vy = DIVE_V;                        // 把上升速度反转为向下俯冲初速
      p.sliding = true;                     // 进入滑铲低姿态
      G.dashShift = Math.max(G.dashShift, DASH_SHIFT_MAX * 0.6);   // 俯冲也带一段前移
      burst(p.x + G.dashShift, p.y, 14, { c: '90,90,100', sp: 200, up: 30, g: 700, s: [1, 4], l: [0.2, 0.6] });
    } else {
      // 上升中按一次 ↓：快速打断起跳，加速砸落（不进入滑铲）
      p.vy = AIR_CANCEL_V;                  // 改向下落，中断上升
      burst(p.x + G.dashShift, p.y, 10, { c: '90,90,100', sp: 120, up: 20, g: 600, s: [1, 3], l: [0.2, 0.4] });
    }
  } else {
    // 已在下落中按 ↓：直接俯冲滑铲，落地延续
    p.vy = DIVE_V;                          // 加速下坠
    p.sliding = true;                       // 进入滑铲低姿态
    G.dashShift = Math.max(G.dashShift, DASH_SHIFT_MAX * 0.6);   // 俯冲也带一段前移
    burst(p.x + G.dashShift, p.y, 14, { c: '90,90,100', sp: 200, up: 120, g: 600, s: [1, 4], l: [0.3, 0.6] });
  }
  G.airDownT = now;                         // 更新按键时刻供下次双按判定
}

// 绳索上的上下翻身：0 = 绳上正立，1 = 绳下倒立。
export function moveOnRope(direction) {
  const p = G.player;
  if (!p.ropeMode) return false;
  const wx = G.scrollX + p.x + G.dashShift;
  const seg = p.ropeRouteStart == null
    ? segAt(wx)
    : G.terrain.find((s) => s.type === 'rope' && s.start === p.ropeRouteStart);
  if (!seg || seg.type !== 'rope') return false;
  const current = p.ropeOffset;
  const target = direction > 0 ? 1 : 0;
  if (Math.abs(target - current) < 0.001) return false;
  p.ropeFlipFrom = current;
  p.ropeFlipTo = target;
  p.ropeFlipT = 0.24;
  p.ropeOffset = current;
  p.vy = 0;
  p.onGround = true;
  p.sliding = false;
  p.slideT = 0;
  return true;
}

export function castNinjutsu() {
  const p = G.player;
  if (G.energy < ENERGY_MAX || p.invuln > 0) return;
  G.energy = 0;
  p.invuln = RASENGAN_CAST_INVULN_T;
  // 向前搓出螺旋丸：出手点在掌心高度，世界坐标固定（不随玩家移动）
  G.rasengan = {
    x: G.scrollX + p.x + G.dashShift + 58,
    y: p.y - RASENGAN_LIFT,
    age: 0, life: RASENGAN_LIFE,
  };
  inkBurst(p.x + G.dashShift + 58, p.y - RASENGAN_LIFT, 28, 1.7);
}

// 火球术（武器技能）：不耗能量，只受 20 秒冷却限制；Q 键或点击右下按钮触发。
// 召唤 3 枚火球环绕护体，自动追踪飞镖/滚石/剑忍（索敌规则见 fireballs.js）。
export function castFireballs() {
  const p = G.player;
  if (G.fireCd > 0) return;                          // 冷却中：忽略本次触发
  G.fireCd = FIRE_CD;                                // 进入冷却
  const orbs = [];
  for (let i = 0; i < FIRE_ORB_COUNT; i++) {
    orbs.push({
      ang: (i / FIRE_ORB_COUNT) * Math.PI * 2,       // 三球均分 120° 相位
      x: G.scrollX + p.x + G.dashShift,              // 初始位置：环轨中心（世界坐标）
      y: p.y - FIRE_LIFT,
      vx: 0, vy: 0,                                  // 追踪时的速度向量
      mode: 'orbit',                                 // orbit 环绕待机 → seek 脱轨追踪
      tx: null,                                      // 锁定的目标障碍（引用）
      age: 0,                                        // 火苗跳动动画计时
    });
  }
  G.fireballs = { age: 0, life: FIRE_LIFE, orbs };
  burst(p.x + G.dashShift, p.y - FIRE_LIFT, 16, { c: '230,120,50', sp: 220, up: 90, g: 250, s: [2, 5], l: [0.25, 0.5] });   // 召唤火光
}

export function startGame() { resetGame(); }
