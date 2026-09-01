import { G } from './state.js';
import {
  SCORE_PER_PX, PX_PER_M, START_SPEED, MAX_SPEED, DASH_SHIFT_MAX, SLIDE_ACCEL_T,
  SLIDE_SPEED_BONUS, DASH_JUMP_SHIFT_MAX, DASH_RETURN_SPEED, DASH_HOLD_T, SLIDE_DUR, JUMP_V, DASH_JUMP_BOOST_DUR, DASH_JUMP_SPEED_BONUS,
  GRAV, DIVE_GRAV_MULT, LAND_IMPACT_VY, PIT_FALL_VY, ABYSS, DEATH_DEPTH_MARGIN,
  COMBO_TIMEOUT, COMBO_SCORE, COMBO_CAP, ENERGY_MAX, COIN_ENERGY, SCROLL_ENERGY, SCROLL_SCORE, SHIELD_DUR,
  CLEAR_SCORE, CLEAN_MARGIN,
  COLLECT_RADIUS_EXTRA, PW, PLAYER_X, W, STAND_H,
  HIT_INVULN_T, HIT_KNOCK_PX,
  HIT_ENERGY, DODGE_ENERGY, DODGE_SCORE,
  DART_SPEED, BOULDER_SPEED,
  ROCK_FALL_V,
  CLONE_INVULN_T,
} from './constants.js';
import { groundYAt, segTypeAt } from './terrain.js';
import { burst, inkBurst, splatBurst } from './particles.js';
import { aabb, circleRect } from './utils.js';
import { finishSlide, die } from './player.js';

export function updateMetrics() {
  G.score = G.collectScore + Math.floor(G.scrollX / SCORE_PER_PX);
  G.distM = Math.floor(G.scrollX / PX_PER_M);
}

// 速度曲线：按行进距离分段加速，约 1 千米后封顶（单局 2-3 分钟节奏）
const SPEED_STAGES = [
  { at: 0, speed: START_SPEED },   // 开局
  { at: 200, speed: 520 },         // 竹林区加速
  { at: 500, speed: 700 },         // 黄昏村
  { at: 800, speed: 900 },         // 夜冥山
  { at: 1000, speed: MAX_SPEED },  // 1 千米：达到最快
];
export function speedAt(m) {
  const last = SPEED_STAGES[SPEED_STAGES.length - 1];
  if (m >= last.at) return last.speed;
  for (let i = 1; i < SPEED_STAGES.length; i++) {
    const a = SPEED_STAGES[i - 1], b = SPEED_STAGES[i];
    if (m <= b.at) {
      const t = (m - a.at) / (b.at - a.at);
      return a.speed + (b.speed - a.speed) * t;
    }
  }
  return last.speed;
}

export function updateSpeed(dt) {
  const base = speedAt(G.scrollX / PX_PER_M);
  const p = G.player;
  // 先取基础速度，滑铲和滑铲接跳分支再叠加各自的真实场景加速。
  G.speed = base;
  if (p.onGround && p.sliding) {
    p.slideT += dt;
    // 三次缓入同时驱动场景加速和角色前移，避免只有位置变化却没有速度变化。
    const slideP = Math.min(1, p.slideT / SLIDE_ACCEL_T);
    const slideEase = Math.max(
      slideP * slideP * (3 - 2 * slideP),
      Math.min(1, G.dashShift / DASH_SHIFT_MAX),
    );
    G.speed = base + SLIDE_SPEED_BONUS * slideEase;
    G.dashShift = Math.max(G.dashShift, DASH_SHIFT_MAX * slideEase);
    if (p.slideT >= SLIDE_DUR) {
      if (p.slideQueued) {
        p.slideT -= SLIDE_DUR;
        p.slideQueued = false;
      } else {
        G.dashHoldT = DASH_HOLD_T;
        finishSlide();
      }
    }
  } else if (p.dashBoostT > 0) {
    const boostDt = Math.min(dt, p.dashBoostT);
    G.speed = base + DASH_JUMP_SPEED_BONUS * (p.dashBoostT / DASH_JUMP_BOOST_DUR);
    // 无论滑铲多久后起跳，都将剩余前移均匀铺满整个冲刺窗口。
    const remainingShift = Math.max(0, DASH_JUMP_SHIFT_MAX - G.dashShift);
    G.dashShift = Math.min(DASH_JUMP_SHIFT_MAX, G.dashShift + remainingShift * boostDt / p.dashBoostT);
    p.dashBoostT = Math.max(0, p.dashBoostT - boostDt);
  } else if (p.dashCarrying && !p.onGround) {
    // 冲刺时窗结束后把已获得的前移保留到落地，才会形成真实跳距增益。
  } else if (G.dashHoldT > 0) {
    // 滑铲刚结束的惯性窗口：保持前移位，期间再按 ↓ 从高位继续，连滑不回退不抽搐
    G.dashHoldT = Math.max(0, G.dashHoldT - dt);
  } else if (G.dashShift > 0) {
    G.dashShift = Math.max(0, G.dashShift - DASH_RETURN_SPEED * dt);
  }
  G.scrollX += G.speed * dt;
  p.runT += dt;

  // 未被墙顶住时，把被推偏的站位平滑回到默认位置（滑铲穿过竖板后自动回正）
  if (!G.wallPushed && p.x !== PLAYER_X) {
    const back = Math.min(Math.abs(PLAYER_X - p.x), DASH_RETURN_SPEED * dt);
    p.x += PLAYER_X > p.x ? back : -back;
  }
}

// 活体障碍每帧推进：飞镖与滚石迎面朝玩家水平飞（世界坐标 x 递减），碰撞盒与渲染共用当前位置。
// 落石固定在世界坐标 x，预警期（warnT>0）倒计时，结束后从上方急速下落到地面。
export function updateEnemies(dt) {
  for (const ob of G.obstacles) {
    if (ob.kind === 'dart') ob.x -= DART_SPEED * dt;
    else if (ob.kind === 'boulder') ob.x -= BOULDER_SPEED * dt;
    else if (ob.kind === 'rock') {
      if (ob.warnT > 0) {
        ob.warnT -= dt;  // 预警倒计时，期间无碰撞，仅在地面显示扩散阴影圈
      } else if (ob.y < ob.landY) {
        ob.y = Math.min(ob.landY, ob.y + ROCK_FALL_V * dt);  // 预警结束，落石急速下落
      }
    }
  }
}

export function updateGravity(dt) {
  const p = G.player;
  if (!p.onGround) {
    p.jumpT += dt;
    let g = GRAV;
    if (p.sliding) g = GRAV * DIVE_GRAV_MULT;   // 俯冲加重
    p.vy += g * dt;
    p.y += p.vy * dt;
    const gy = groundYAt(G.scrollX + p.x + G.dashShift);
    if (p.y >= gy) {
      if (p.vy > LAND_IMPACT_VY) burst(p.x + G.dashShift, gy, 16, { c: '90,90,100', sp: 220, up: 40, g: 800, s: [2, 5], l: [0.2, 0.5] });
      if (G.jumpBuf > 0) {
        // 落地缓冲：落地瞬间自动起跳
        G.jumpBuf = 0; G.coyote = 0; p.y = gy;
        p.vy = -JUMP_V; p.onGround = false; p.jumps = 1; p.jumpT = 0;
        if (finishSlide()) {
          p.dashBoostT = DASH_JUMP_BOOST_DUR;
          p.dashCarrying = true;
        } else {
          p.dashBoostT = 0;
          p.dashCarrying = false;
        }
      } else {
        p.y = gy; p.vy = 0;
        p.onGround = true; p.jumps = 0; p.jumpT = 0;
        p.dashBoostT = 0;
        p.dashCarrying = false;
        // 俯冲落地后开始一整段滑铲，结束后仍需起身恢复。
        if (p.sliding) { p.slideT = 0; } else { p.sliding = false; }
      }
    }
  } else {
    // 站地：跟随脚下地形起伏
    const wx = G.scrollX + p.x + G.dashShift;
    if (segTypeAt(wx) === 'pit') {
      // 踏入深坑：失去站立，开始自由坠落（可见的下坠过程）
      finishSlide();
      p.onGround = false;
      p.vy = Math.max(p.vy, PIT_FALL_VY);
    } else {
      p.y = groundYAt(wx);
    }
  }
}

// 竖板实体墙：角色被钉在墙左缘（世界坐标），随世界滚动被推向屏幕左，出屏即死。
// 滑铲时碰撞盒变矮（SLIDE_H=32）可穿过竖板底部空隙（52px）脱困。
function wallPush(ob) {
  const p = G.player;
  G.wallPushed = true;
  // 钉住：角色右缘贴墙左缘 → player.x 随 scrollX 增大而被迫减小（被推向左）
  p.x = ob.x - G.scrollX - G.dashShift - PW / 2;
  // 空中撞墙：取消上升，贴墙垂直下落（不能穿过墙）
  if (!p.onGround && p.vy < 0) p.vy = 0;
  // 被完全推出画面左缘 → 死亡
  if (p.x + G.dashShift < -PW / 2) { die(); return true; }
  return false;
}

function destroyHazard(list, index, hazard) {
  list.splice(index, 1);
  G.collectScore += CLEAR_SCORE;
  burst(hazard.x - G.scrollX + hazard.w / 2, hazard.y + hazard.h / 2, 14, { c: '72,146,164', sp: 190, up: 80, g: 480, s: [1, 4], l: [0.2, 0.5] });
}

// 墨影分身碰撞盒
function cloneBox(c) {
  return { x: c.x - PW / 2, y: c.y - STAND_H, w: PW, h: STAND_H };
}

// 分身替挡：消散 + 无敌 + 墨渍爆裂（Splat 墨渍叠加，视觉更浓烈）
function breakClone() {
  const c = G.clone;
  if (!c) return;
  G.clone = null;
  G.player.invuln = Math.max(G.player.invuln, CLONE_INVULN_T);
  const cx = c.x - G.scrollX, cy = c.y - STAND_H;
  splatBurst(cx, cy, 4, 1, 1.3);          // 大号墨渍爆散，体现"替挡"的分量
  inkBurst(cx, cy, 10, 1.2);              // 再铺一层细墨点，增加飞溅层次
}

// 碰撞检测：仅深坑坠落即死；普通障碍按血条扣血 + 无敌帧，奔跑不中断。
// 护盾可挡下普通伤害障碍（清障加分），但挡不住深坑即死。
export function updateCollisions(box) {
  const p = G.player;
  // 掉进深坑：下坠到坑底附近才死（先有一段可见坠落）
  if (p.y > ABYSS - DEATH_DEPTH_MARGIN) { die(); return true; }
  G.wallPushed = false;
  for (let i = G.obstacles.length - 1; i >= 0; i--) {
    const ob = G.obstacles[i];
    // 落石预警/下落途中无碰撞：只有落地形成实体才参与判定
    if (ob.kind === 'rock' && (ob.warnT > 0 || ob.y < ob.landY)) continue;

    // 墨影分身挡灾：分身在场且障碍与分身相交 → 分身消散替挡（仅一次，beam 纯推挤不分担）
    if (G.clone && ob.kind !== 'beam') {
      const pbox = cloneBox(G.clone);
      if (ob.x < pbox.x + pbox.w && ob.x + ob.w > pbox.x) {
        if (ob.y < pbox.y + pbox.h && ob.y + ob.h > pbox.y) {
          breakClone();
          G.obstacles.splice(i, 1);
          G.collectScore += CLEAR_SCORE;
          continue;
        }
      }
    }

    if (!aabb(box, ob)) {
      // 完美闪避：障碍水平掠过玩家范围但垂直不相交（跳过/滑过）→ 加分+能量
      if (!ob.dodged && ob.kind !== 'beam') {
        const hOverlap = ob.x < box.x + box.w && ob.x + ob.w > box.x;
        if (hOverlap) {
          ob.dodged = true;
          G.energy = Math.min(ENERGY_MAX, G.energy + DODGE_ENERGY);
          G.collectScore += DODGE_SCORE;
        }
      }
      continue;
    }
    if (p.invuln > 0) continue;
    if (p.shieldT > 0) { destroyHazard(G.obstacles, i, ob); continue; }
    if (ob.kind === 'beam') { if (wallPush(ob)) return true; continue; }  // 实体墙：被顶住推挤，不掉血
    // 普通伤害物：扣血 + 短暂无敌 + 补能量（挨打换忍术）
    p.hp -= ob.dmg;
    p.invuln = HIT_INVULN_T;
    p.hpBarT = 1; // 受伤点亮血条（平时隐藏）
    p.x = Math.min(p.x, PLAYER_X - HIT_KNOCK_PX);
    G.energy = Math.min(ENERGY_MAX, G.energy + HIT_ENERGY); // 受击补能量
    // 飞镖是迎面活物，受击用水墨爆（stroke+drop 双形态更足）；其余静态障碍保持常规墨点。
    if (ob.kind === 'dart') {
      inkBurst(ob.x - G.scrollX + ob.w / 2, ob.y + ob.h / 2, 14, 1.2);
    } else {
      burst(ob.x - G.scrollX + ob.w / 2, ob.y + ob.h / 2, 12, { c: '165,58,46', sp: 190, up: 60, g: 600, s: [2, 5], l: [0.2, 0.5] });
    }
    if (p.hp <= 0) { die(); return true; }
  }
  return false;
}

export function collectPickups(box) {
  for (let i = G.collectibles.length - 1; i >= 0; i--) {
    const c = G.collectibles[i];
    if (c.taken) continue;
    if (circleRect(c.x, c.y, c.r + COLLECT_RADIUS_EXTRA, box)) {
      c.taken = true;
      G.collectibles.splice(i, 1);
      if (c.type === 'coin') {
        G.combo++;
        G.comboTimer = COMBO_TIMEOUT;
        G.collectScore += COMBO_SCORE * Math.min(G.combo, COMBO_CAP);
        G.energy = Math.min(ENERGY_MAX, G.energy + COIN_ENERGY);       // 金币也补忍术能量
        burst(c.x, c.y, 8, { c: '216,164,65', sp: 150, up: 60, g: 500, s: [1, 3], l: [0.2, 0.5] });
      } else if (c.type === 'shield') {
        G.player.shieldT = SHIELD_DUR;
        burst(c.x, c.y, 18, { c: '72,146,164', sp: 170, up: 80, g: 420, s: [1, 4], l: [0.25, 0.55] });
      } else {
        G.energy = Math.min(ENERGY_MAX, G.energy + SCROLL_ENERGY);
        G.collectScore += SCROLL_SCORE;
        burst(c.x, c.y, 14, { c: '165,58,46', sp: 180, up: 80, g: 500, s: [1, 4], l: [0.3, 0.6] });
      }
    }
  }
}