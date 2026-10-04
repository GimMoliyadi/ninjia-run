import { G, ctx } from '../state.js';
import { FIRE_R } from '../constants.js';
import { glow } from '../particles.js';

// 火球：暖橙辉光 + 沿飞行方向拉长的火舌 + 墨色内核 + 金色细环。
// 环绕态与追踪态同款绘制，朝向跟随速度矢量；火苗随时间轻微跳动。
// 只绘制环绕态火球和追踪态火球，忽略已命中待清理的
export function drawFireballs() {
  const fb = G.fireballs;
  if (!fb) return;
  for (const o of fb.orbs) {
    // 只绘制环绕态 orbit 和追踪态 seek，跳过已清理的
    if (!o.mode) continue;
    const x = o.x - G.scrollX, y = o.y;
    if (x < -60 || x > 1020 || y < -60 || y > 620) continue;   // 屏外跳过
    const ang = Math.atan2(o.vy, o.vx);                        // 朝向 = 速度方向
    const flick = 1 + Math.sin(o.age * 24) * 0.12;             // 火苗跳动系数

    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(ang);
    // 辉光：暖橙径向晕开，让火球有"燃烧"的体积感
    glow(0, 0, FIRE_R * 2.6, 'rgba(230,120,50,1)', 0.5);
    // 火舌：沿飞行方向拉长的椭圆，颜色深橙
    ctx.globalAlpha = 0.85;
    ctx.fillStyle = 'rgba(200,80,30,0.9)';
    ctx.beginPath();
    ctx.ellipse(-FIRE_R * 0.3, 0, FIRE_R * 1.5 * flick, FIRE_R * 0.85, 0, 0, Math.PI * 2);
    ctx.fill();
    // 墨色内核
    ctx.fillStyle = '#2b2b31';
    ctx.beginPath();
    ctx.arc(0, 0, FIRE_R * 0.55, 0, Math.PI * 2);
    ctx.fill();
    // 纸色亮心：内核里的高光点
    ctx.fillStyle = '#ffd27a';
    ctx.beginPath();
    ctx.arc(0, 0, FIRE_R * 0.26, 0, Math.PI * 2);
    ctx.fill();
    // 金色细环：勾一圈轮廓呼应符咒金
    ctx.strokeStyle = '#d8a441';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(0, 0, FIRE_R * 0.85, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }
}
