import { G, ctx } from '../state.js';
import { W, GROUND, SLIDE_H, STAND_H, PW } from '../constants.js';

export function drawDebug() {
  // 地面碰撞线
  ctx.save();
  ctx.strokeStyle = 'rgba(30,150,255,0.65)';
  ctx.lineWidth = 1;
  ctx.setLineDash([6, 4]);
  ctx.beginPath();
  ctx.moveTo(0, GROUND); ctx.lineTo(W, GROUND);
  ctx.stroke();
  ctx.setLineDash([]);
  // 深坑段标出
  ctx.fillStyle = 'rgba(30,150,255,0.5)';
  for (const seg of G.terrain) {
    if (seg.type !== 'pit') continue;
    const x0 = seg.start - G.scrollX, x1 = seg.end - G.scrollX;
    if (x1 < 0 || x0 > W) continue;
    ctx.fillRect(Math.max(0, x0), 14, Math.min(W, x1) - Math.max(0, x0), 3);
  }
  // 角色碰撞盒（世界坐标换算为屏幕偏移）
  const h = G.player.sliding ? SLIDE_H : STAND_H;
  const px = G.player.x + G.dashShift - PW / 2, py = G.player.y - h;
  ctx.strokeStyle = 'rgba(90,180,255,0.95)';
  ctx.lineWidth = 1.5;
  ctx.strokeRect(px, py, PW, h);
  ctx.fillStyle = 'rgba(90,180,255,0.9)';
  ctx.beginPath();
  ctx.arc(G.player.x + G.dashShift, G.player.y, 3, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}
