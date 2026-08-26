import { G, ctx } from '../state.js';
import { INK, RED } from '../constants.js';

export function drawNinjutsu() {
  const n = G.ninjutsu;
  if (!n) return;
  const x = n.x - G.scrollX;
  if (x < -160 || x > 1120) return;
  const appear = Math.min(1, n.age / 0.16);
  const fade = Math.min(1, (n.duration - n.age) / 0.28);
  const r = n.radius * appear;

  ctx.save();
  ctx.translate(x, n.y);
  ctx.globalAlpha = 0.16 * fade;
  ctx.fillStyle = INK;
  ctx.beginPath();
  ctx.moveTo(-r * 1.7, 0);
  ctx.quadraticCurveTo(-r * 0.25, -r * 0.92, r * 1.45, 0);
  ctx.quadraticCurveTo(-r * 0.1, r * 0.92, -r * 1.7, 0);
  ctx.fill();

  for (let i = 0; i < 3; i++) {
    ctx.globalAlpha = (0.82 - i * 0.2) * fade;
    ctx.strokeStyle = i === 2 ? RED : INK;
    ctx.lineWidth = 9 - i * 2.5;
    ctx.beginPath();
    ctx.arc(0, 0, r + i * 16, -0.76, 0.76);
    ctx.stroke();
  }

  ctx.globalAlpha = 0.62 * fade;
  ctx.fillStyle = INK;
  for (let i = 0; i < 6; i++) {
    const phase = n.age * (8 + i) + i * 1.9;
    const dx = -r * (0.5 + i * 0.22) + Math.sin(phase) * 9;
    const dy = Math.cos(phase * 0.7) * (12 + i * 5);
    ctx.beginPath();
    ctx.ellipse(dx, dy, 3 + (i % 3), 1.5 + (i % 2), phase, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}
