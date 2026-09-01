import { G, ctx } from '../state.js';
import { INK, CLONE_DURATION } from '../constants.js';
import { drawNinjaAvatar } from './entities.js';

// 墨影分身：半透明忍者轮廓跟随玩家，脚下拖墨渍，消散前闪烁提示
export function drawNinjutsu() {
  const c = G.clone;
  if (!c) return;
  const x = c.x - G.scrollX;
  if (x < -160 || x > 1120) return;

  const age = c.age;
  const fadeIn = Math.min(1, age / 0.18);
  const lastPulse = CLONE_DURATION - age < 0.8;
  const blink = lastPulse && Math.floor(age * 14) % 2 === 0;

  ctx.save();
  ctx.globalAlpha = fadeIn * (blink ? 0.2 : 0.45);
  // 脚下墨渍（分身拖尾）
  ctx.fillStyle = INK;
  ctx.beginPath();
  ctx.ellipse(x, c.y - 2, 22 + age * 3, 6, 0, 0, Math.PI * 2);
  ctx.fill();
  // 分身本体
  ctx.globalAlpha = fadeIn * (blink ? 0.25 : 0.5);
  drawNinjaAvatar(x, c.y);
  // 前方墨气旋（释放时的墨色旋涡感）
  ctx.globalAlpha = fadeIn * 0.18;
  ctx.strokeStyle = INK;
  ctx.lineWidth = 3;
  for (let i = 0; i < 2; i++) {
    ctx.beginPath();
    ctx.arc(x + 6, c.y - 28, 30 + i * 12 + Math.sin(age * 9 + i) * 5, age * 3 + i * Math.PI, age * 3 + i * Math.PI + 1.9);
    ctx.stroke();
  }
  ctx.restore();
}
