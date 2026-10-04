import { G } from './state.js';
import {
  FIRE_ORBIT_R, FIRE_ORBIT_SPD, FIRE_SPEED, FIRE_TURN, FIRE_R,
  FIRE_LIFT, FIRE_LIFE, FIRE_SEEK_RANGE,
} from './constants.js';
import { burst, inkBurst } from './particles.js';

// 可被火球瞄准/焚毁的"活物"名单：迎面飞镖、滚石、持刀剑忍。
// 固定建筑（尖刺/石柱/垂板/墨墙）与落石不在此列——火球不会瞄准它们，
// 碰撞判定（physics.js）也只对这份名单生效，火球会直接穿过。
export const FIRE_TARGET_KINDS = { dart: 1, boulder: 1, ninja: 1 };

// 索敌：返回距离火球最近的合法活物（没有则 null）
function nearestTarget(x, y) {
  let best = null;
  let bestD = FIRE_SEEK_RANGE * FIRE_SEEK_RANGE;      // 平方距离比较，省开方
  for (const ob of G.obstacles) {
    if (!FIRE_TARGET_KINDS[ob.kind] || ob.dead) continue;   // 只瞄活物，跳过已毁目标
    const dx = ob.x + ob.w / 2 - x, dy = ob.y + ob.h / 2 - y;
    const d = dx * dx + dy * dy;
    if (d < bestD) { bestD = d; best = ob; }
  }
  return best;
}

// 火球组每帧更新：环绕待机 → 索敌锁定 → 脱轨追踪；命中判定在 physics.js
// 火球飞出后立即在原位补充新火球，始终保持 FIRE_ORB_COUNT 枚环绕
export function updateFireballs(dt) {
  const fb = G.fireballs;
  if (!fb) return;
  fb.age += dt;                                        // 火球组存活计时
  const p = G.player;
  const cx = G.scrollX + p.x + G.dashShift;            // 环轨中心（世界坐标）跟随角色
  const cy = p.y - FIRE_LIFT;

  // 寿命到期：剩余火球原地墨散熄灭
  if (fb.age >= fb.life) {
    for (const o of fb.orbs) {
      if (o.mode === 'orbit') inkBurst(o.x - G.scrollX, o.y, 5, 0.7);
    }
    G.fireballs = null;
    return;
  }

  // 统计环绕中的火球数，发射后立即补充
  const orbiting = fb.orbs.filter(o => o.mode === 'orbit');
  const seeking = fb.orbs.filter(o => o.mode === 'seek');

  // 只遍历本帧开始时的火球；锁定目标时追加的补位火球留到下一帧处理，
  // 避免 for...of 在遍历过程中不断消费新元素。
  const activeCount = fb.orbs.length;
  for (let index = 0; index < activeCount; index++) {
    const o = fb.orbs[index];
    o.age += dt;                                       // 火苗跳动动画计时

    if (o.mode === 'orbit') {
      // 环绕：绕角色匀速旋转，切向速度作为脱轨时的初速方向
      o.ang += FIRE_ORBIT_SPD * dt;
      o.x = cx + Math.cos(o.ang) * FIRE_ORBIT_R;
      o.y = cy + Math.sin(o.ang) * FIRE_ORBIT_R;
      o.vx = -Math.sin(o.ang) * FIRE_SPEED;
      o.vy = Math.cos(o.ang) * FIRE_SPEED;
      // 索敌：范围内出现合法活物 → 脱轨转入追踪
      const t = nearestTarget(o.x, o.y);
      if (t) {
        o.mode = 'seek';
        o.tx = t;
        // 火球脱轨瞬间：在原位补充新火球，保持 3 枚环绕
        fb.orbs.push({
          ang: o.ang,                                  // 继承脱轨火球的相位
          x: o.x,
          y: o.y,
          vx: 0, vy: 0,
          mode: 'orbit',
          tx: null,
          age: 0,
        });
      }
    } else {
      // 追踪：目标被其他技能抢先毁掉 → 失去目标改为直飞
      if (o.tx && o.tx.dead) o.tx = null;
      if (o.tx) {
        // 限速转向：以 FIRE_TURN 的角速度把速度矢量转向目标，形成弧线追踪
        const want = Math.atan2(o.tx.y + o.tx.h / 2 - o.y, o.tx.x + o.tx.w / 2 - o.x);
        const cur = Math.atan2(o.vy, o.vx);
        let d = want - cur;
        while (d > Math.PI) d -= Math.PI * 2;          // 角度差归一到 [-π, π]
        while (d < -Math.PI) d += Math.PI * 2;
        const a = cur + Math.max(-FIRE_TURN * dt, Math.min(FIRE_TURN * dt, d));
        o.vx = Math.cos(a) * FIRE_SPEED;
        o.vy = Math.sin(a) * FIRE_SPEED;
      }
      o.x += o.vx * dt;
      o.y += o.vy * dt;
      // 追踪尾迹：向后甩出暖色火星（火星轻微上飘，g 为负）
      if (Math.random() < 0.5) {
        G.particles.push({
          x: o.x - G.scrollX, y: o.y,
          vx: -o.vx * 0.08 + (Math.random() - 0.5) * 30,
          vy: -o.vy * 0.08 + (Math.random() - 0.5) * 30,
          g: -60,
          life: 0.3, maxLife: 0.3,
          size: 1.5 + Math.random() * 2,
          c: Math.random() < 0.3 ? '216,164,65' : '230,120,50',
        });
      }
    }
  }
}
