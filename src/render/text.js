import { ctx } from '../state.js';
import { KAI, INK, RED } from '../constants.js';
import { jitter } from '../utils.js';

export function brushText(str, x, y, size, color, align) {
  ctx.save();
  ctx.font = 'bold ' + size + 'px ' + KAI;
  ctx.textAlign = align || 'center';
  ctx.textBaseline = 'middle';
  const c = color || INK;
  ctx.fillStyle = c;
  const j = Math.max(0.8, size * 0.018);
  ctx.globalAlpha = 0.28;
  for (let i = 0; i < 4; i++) {
    ctx.fillText(str, x + jitter(j * 2), y + jitter(j * 2));
  }
  ctx.globalAlpha = 1;
  ctx.fillText(str, x, y);
  ctx.restore();
}

export function stamp(txt, x, y, s, rot) {
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(rot || 0);
  ctx.strokeStyle = RED;
  ctx.lineWidth = Math.max(2, s * 0.09);
  ctx.strokeRect(-s / 2, -s / 2, s, s);
  ctx.font = 'bold ' + s * 0.55 + 'px ' + KAI;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = RED;
  ctx.fillText(txt, 0, s * 0.04);
  ctx.restore();
}
