import { G } from './state.js';
import { RASENGAN_SPEED, RASENGAN_R } from './constants.js';
import { inkBurst } from './particles.js';
import { rand } from './utils.js';


// 螺旋丸：释放后朝画面右方（世界坐标 +x）匀速前飞的旋转墨球。
// 沿途障碍由 physics 的碰撞分支击碎（可连穿多个），
// 飞行 RASENGAN_LIFE 秒后自行墨散消隐。
export function updateNinjutsu(dt) {
  const r = G.rasengan;
  if (!r) return;

  r.age += dt;
  r.x += RASENGAN_SPEED * dt;

  // 飞行尾迹：甩出细墨点（粒子为屏幕坐标，故取屏幕 x），幅度随球体半径走
  if (Math.random() < 0.75) {
    const sx = r.x - G.scrollX;
    G.particles.push({
      x: sx - RASENGAN_R * 0.6 + Math.random() * 12,
      y: r.y + (Math.random() - 0.5) * RASENGAN_R * 1.8,
      vx: -rand(40, 130), vy: (Math.random() - 0.5) * 50,
      g: 60, life: 0.3, maxLife: 0.3,
      size: 2 + Math.random() * 3,
      c: Math.random() < 0.25 ? '72,146,164' : '40,40,46',
    });
  }

  if (r.age >= r.life) {
    G.rasengan = null;
    inkBurst(r.x - G.scrollX, r.y, 18, 1.3);
  }
}
