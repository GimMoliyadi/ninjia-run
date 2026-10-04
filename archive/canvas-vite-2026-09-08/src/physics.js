import { G } from './state.js';
import {
  SCORE_PER_PX, PX_PER_M, START_SPEED, MAX_SPEED, DASH_SHIFT_MAX, SLIDE_ACCEL_T,
  SLIDE_SPEED_BONUS, DASH_JUMP_SHIFT_MAX, DASH_RETURN_SPEED, DASH_HOLD_T, SLIDE_DUR, SLIDE_RECOVER_T, JUMP_V, DASH_JUMP_BOOST_DUR, DASH_JUMP_SPEED_BONUS,
  GRAV, DIVE_GRAV_MULT, JUMP_RELEASE_MULT, LAND_IMPACT_VY, PIT_FALL_VY, ABYSS, DEATH_DEPTH_MARGIN,
  COIN_SCORE, ENERGY_MAX, COIN_ENERGY, SCROLL_ENERGY, SCROLL_SCORE, SHIELD_DUR,
  CLEAR_SCORE, CLEAN_MARGIN,
  COLLECT_RADIUS_EXTRA, PW, PLAYER_X,
  HIT_INVULN_T, HIT_KNOCK_PX,
  HIT_ENERGY, DODGE_ENERGY, DODGE_SCORE,
  DART_SPEED, BOULDER_SPEED,
  ROCK_FALL_V,
  RASENGAN_R, FIRE_R,
} from './constants.js';
import { groundYAt, segTypeAt, segAt } from './terrain.js';
import { burst, inkBurst, splatBurst } from './particles.js';
import { aabb, circleRect } from './utils.js';
import { finishSlide, die, startSlide } from './player.js';
import { FIRE_TARGET_KINDS } from './fireballs.js';

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

export function updateSpeed(dt, manual = false) {
  const base = manual ? START_SPEED : speedAt(G.scrollX / PX_PER_M);
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
      const buffered = p.slideQueued;   // 先记下缓冲请求：finishSlide 会把它清掉，需恢复
      G.dashHoldT = DASH_HOLD_T;        // 起身后保留一段前移惯性：站位不会瞬间回弹
      finishSlide();                    // 结束本段滑铲，回到站立姿态
      p.slideQueued = buffered;         // 恢复缓冲标记：间歇结束后据此自动衔接下一段
      G.slideLockT = SLIDE_RECOVER_T;   // 记起身间歇：约 0.1s 内不直接续滑（"一滑一停"）
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
    // 前移惯性窗口结束，平滑回位
    G.dashShift = Math.max(0, G.dashShift - DASH_RETURN_SPEED * dt);
  }

  // —— 滑铲起身间歇衔接 ——
  // 间歇持续倒计时（与是否缓冲无关）：保证两段滑铲之间至少有 SLIDE_RECOVER_T 的停顿
  if (G.slideLockT > 0) G.slideLockT = Math.max(0, G.slideLockT - dt);
  // 间歇走完且有缓冲请求（滑铲中或间歇中按下的 ↓）时自动衔接下一段
  if (!p.sliding && p.onGround && p.slideQueued && G.slideLockT <= 0) {
    p.slideQueued = false;   // 消费本次缓冲请求
    startSlide();            // 自动衔接下一段滑铲（复用贴地起手逻辑，含前移反馈）
  }
  if (manual) {
    G.speed = START_SPEED;
    G.dashShift = 0;
    if (p.sliding || !p.onGround) p.runT += dt;
    return;
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
    } else if (ob.kind === 'scythe') {
      ob.angle += (ob.omega || 2) * dt;
      const a = ob.angle;
      const cx = ob.anchorX + Math.sin(a) * ob.ropeLen;
      const cy = ob.anchorY + Math.cos(a) * ob.ropeLen;
      ob.x = cx - ob.w / 2;
      ob.y = cy - ob.h / 2;
    }
  }
}

export function updateGravity(dt) {
  const p = G.player;
  const wx = G.scrollX + p.x + G.dashShift;
  const currentSeg = segAt(wx);

  // 绳索是独立的附着状态。沿绳索移动时停用重力，避免角色掉出绳体。
  if (p.ropeMode) {
    // 绑定到进入时的整段绳索路线，避免摄像机滚动/滑铲前移在段边界造成瞬间脱附。
    const routeSeg = p.ropeRouteStart == null
      ? currentSeg
      : G.terrain.find((s) => s.type === 'rope' && s.start === p.ropeRouteStart);
    const routeEnd = p.ropeRouteEnd ?? routeSeg?.end ?? -Infinity;
    if (!routeSeg || wx > routeEnd + 12) {
      p.ropeMode = false;
      p.ropeOffset = 0;
      p.ropeFlipT = 0;
      p.ropeRouteStart = null;
      p.ropeRouteEnd = null;
      p.y = groundYAt(wx);
      p.vy = 0;
      p.onGround = true;
    } else {
      if (p.ropeFlipT > 0) {
        const total = 0.24;
        p.ropeFlipT = Math.max(0, p.ropeFlipT - dt);
        const elapsed = total - p.ropeFlipT;
        const t = Math.min(1, Math.max(0, elapsed / total));
        const ease = t * t * (3 - 2 * t);
        p.ropeOffset = p.ropeFlipFrom + (p.ropeFlipTo - p.ropeFlipFrom) * ease;
      } else p.ropeOffset = p.ropeFlipTo;
      p.ropeOffset = Math.max(0, Math.min(1, p.ropeOffset));
      p.y = routeSeg.y;
      p.vy = 0;
      p.onGround = true;
      p.jumps = 0;
      p.sliding = false;
      p.slideT = 0;
      p.jumpT = 0;
      return;
    }
  }

  if (!p.onGround) {
    const previousY = p.y;
    if (p.dropThroughT > 0) p.dropThroughT = Math.max(0, p.dropThroughT - dt);
    p.jumpT += dt;
    let g = GRAV;
    if (p.sliding) g = GRAV * DIVE_GRAV_MULT;   // 俯冲加重
    // 可变跳跃高度：起跳按住过、上升中松开跳跃键 → 重力加倍提前切断上升（轻点短跳、长按高跳）
    else if (!G.jumpHeld && p.heldJump && p.vy < 0) g = GRAV * JUMP_RELEASE_MULT;
    p.vy += g * dt;
    p.y += p.vy * dt;
    const gy = groundYAt(wx);
    const seg = currentSeg;
    // 斜面进入绳索时不要求“刚好从绳体上方穿过”。只要落点进入绳索捕获带，
    // 就吸附到这段独立路线，避免一个离散帧错过绳索后直接掉到 ABYSS。
    if (seg?.type === 'rope' && p.y >= seg.y - 220 && p.y <= seg.y + 80 && p.vy >= 0) {
      p.ropeMode = true;
      p.ropeOffset = 0;
      p.ropeFlipFrom = 0;
      p.ropeFlipTo = 0;
      p.ropeFlipT = 0;
      p.ropeRouteStart = seg.start;
      p.ropeRouteEnd = seg.end;
      p.y = seg.y;
      p.vy = 0;
      p.onGround = true;
      p.jumps = 0;
      return;
    }
    const canLand = seg?.type !== 'platform' || previousY <= gy + 2;
    if (p.y >= gy && canLand) {
      if (p.vy > LAND_IMPACT_VY) {
        burst(p.x + G.dashShift, gy, 16, { c: '90,90,100', sp: 220, up: 40, g: 800, s: [2, 5], l: [0.2, 0.5] });
        splatBurst(p.x + G.dashShift, gy - 4, 2, 0.55, 0.7);   // 重落地：地面墨渍晕开
      }
      if (G.jumpBuf > 0) {
        // 落地缓冲：落地瞬间自动起跳
        G.jumpBuf = 0; G.coyote = 0; p.y = gy;
        p.vy = -JUMP_V; p.onGround = false; p.jumps = 1; p.jumpT = 0;
        p.heldJump = G.jumpHeld;   // 缓冲跳：若按键仍按住则全程上升，否则算轻点
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
        p.heldJump = false;   // 落地复位：下一次起跳时重新按当前按键状态记录
        p.dashBoostT = 0;
        p.dashCarrying = false;
        p.dropThroughT = 0;
        // 俯冲落地后延续滑铲姿态；非俯冲落地则起身
        if (p.sliding) { p.slideT = 0; } else { p.sliding = false; }
      }
    }
  } else {
    // 站地：跟随脚下地形起伏
    if (segTypeAt(wx) === 'pit') {
      // 踏入深坑：失去站立，开始自由坠落（可见的下坠过程）
      finishSlide();
      p.onGround = false;
      p.vy = Math.max(p.vy, PIT_FALL_VY);
    } else {
      const seg = currentSeg;
      if (seg?.type === 'rope') {
        p.ropeMode = true;
        p.ropeOffset = 0;
        p.ropeFlipFrom = p.ropeOffset;
        p.ropeFlipTo = p.ropeOffset;
        p.ropeFlipT = 0;
        p.ropeRouteStart = seg.start;
        p.ropeRouteEnd = seg.end;
        p.y = seg.y;
        p.vy = 0;
        return;
      }
      const gy = groundYAt(wx);
      if (seg?.type === 'platform' && p.y > gy + 4) {
        p.onGround = false;
        p.vy = Math.max(p.vy, 120);
      } else {
        p.y = gy;
      }
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

// 火球焚毁 + 通用清障：标记已毁（追踪火球据此感知目标消失）、移除、加分、墨渍四溅
export function destroyHazard(list, index, hazard) {
  hazard.dead = true;   // 标记已毁：追踪火球据此感知目标消失
  list.splice(index, 1);
  G.collectScore += CLEAR_SCORE;
  burst(hazard.x - G.scrollX + hazard.w / 2, hazard.y + hazard.h / 2, 14, { c: '72,146,164', sp: 190, up: 80, g: 480, s: [1, 4], l: [0.2, 0.5] });
  splatBurst(hazard.x - G.scrollX + hazard.w / 2, hazard.y + hazard.h / 2, 2, 0.8, 0.9);   // 护盾/忍术清障：墨渍四溅
}

// 螺旋丸碰撞盒（圆形近似为方盒，出手即横扫 waist 高度的一切）
function rasenganBox(r) {
  return { x: r.x - RASENGAN_R, y: r.y - RASENGAN_R, w: RASENGAN_R * 2, h: RASENGAN_R * 2 };
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
    if (ob.kind === 'portal' && !ob.used && aabb(box, ob)) {
      G.scrollX = Math.max(G.scrollX, ob.targetX - PLAYER_X - 80);
      p.y = ob.targetY;
      p.vy = -760;
      p.onGround = false;
      p.jumps = 1;
      p.invuln = 0.35;
      ob.used = true;
      continue;
    }
    // 落石预警/下落途中无碰撞：只有落地形成实体才参与判定
    if (ob.kind === 'rock' && (ob.warnT > 0 || ob.y < ob.landY)) continue;

    // 螺旋丸击碎：障碍与墨球相交 → 击碎清障加分，墨球连穿不消失（含垂板：一发轰穿）
    if (G.rasengan && aabb(rasenganBox(G.rasengan), ob)) {
      const r = G.rasengan;
      inkBurst(Math.min(r.x, ob.x + ob.w / 2) - G.scrollX, ob.y + ob.h / 2, 16, 1.3);
      destroyHazard(G.obstacles, i, ob);
      continue;
    }

    // 火球焚毁：只烧"活物"（飞镖/滚石/剑忍）；固定建筑与落石不可破坏，火球直接穿过
    // 火球命中后会被移除，但立即在环绕轨道补充新火球（补充逻辑在 fireballs.js）
    if (G.fireballs && FIRE_TARGET_KINDS[ob.kind]) {
      const orbs = G.fireballs.orbs;
      let burned = false;
      for (let k = orbs.length - 1; k >= 0; k--) {
        const o = orbs[k];
        // 追踪中的火球可命中；环绕火球若与目标直接重叠也算贴身命中。
        if ((o.mode === 'seek' || o.mode === 'orbit') && circleRect(o.x, o.y, FIRE_R, ob)) {
          burst(ob.x + ob.w / 2 - G.scrollX, ob.y + ob.h / 2, 18, { c: '230,120,50', sp: 240, up: 90, g: 350, s: [2, 6], l: [0.25, 0.55] });   // 焚毁火光
          destroyHazard(G.obstacles, i, ob);
          orbs.splice(k, 1);       // 移除命中的追踪火球（环绕位已在 fireballs.js 补充）
          burned = true;
          break;
        }
      }
      if (burned) continue;        // 障碍已碎，跳过后面的闪避/受伤判定
      // 没烧到：照常走下方的闪避/受伤判定
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
      splatBurst(ob.x - G.scrollX + ob.w / 2, ob.y + ob.h / 2, 2, 0.7, 0.85);
    } else {
      burst(ob.x - G.scrollX + ob.w / 2, ob.y + ob.h / 2, 12, { c: '165,58,46', sp: 190, up: 60, g: 600, s: [2, 5], l: [0.2, 0.5] });
      splatBurst(ob.x - G.scrollX + ob.w / 2, ob.y + ob.h / 2, 2, 0.7, 0.85);
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
        G.collectScore += COIN_SCORE;                                   // 金币固定加分（连击系统已移除）
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
