import { G, ctx } from '../state.js';
import { INK, W, RASENGAN_R } from '../constants.js';
import { glow } from '../particles.js';

// 螺旋丸：高速自旋的墨球。三层表现——
//   外圈查克拉气环（青蓝，同护盾色系）+ 三条旋臂 + 实心墨核与纸色亮心；
// 出手瞬间从小放大，消散前整体淡出；飞行方向后方拖两道墨痕表现前冲。
// 线宽与尾迹长度随 R 缩放：球体越大，各层细节按比例加粗，避免显得单薄。
export function drawNinjutsu() {
  const r = G.rasengan;
  if (!r) return;
  const x = r.x - G.scrollX, y = r.y;
  if (x < -80 || x > W + 120) return;

  const spawn = Math.min(1, r.age / 0.12);            // 出手放大进度：0→1
  const fade = Math.min(1, (r.life - r.age) / 0.2);   // 寿命将尽淡出进度：1→0
  const a = spawn * fade;                             // 综合透明度（先放大后淡出）
  const R = RASENGAN_R * (0.45 + 0.55 * spawn);       // 当前半径：出手从小弹大到全尺寸
  const spin = r.age * 26;                            // 自旋角速度：随时间高速旋转

  ctx.save();
  ctx.translate(x, y);

  // 后拖墨痕：两道向后的水平扫笔，表现向前轰出的冲势（长度随 R 放大）
  ctx.strokeStyle = INK;
  ctx.lineCap = 'round';
  for (let i = 0; i < 2; i++) {
    ctx.globalAlpha = a * (0.3 - i * 0.12);           // 两道一近一远，越远越淡
    ctx.lineWidth = Math.max(3, 5 - i * 2 + R * 0.05);   // 线宽随球体变大略加粗
    const len = (26 + i * 16) * (R / RASENGAN_R) + Math.sin(r.age * 31 + i * 2) * 6;   // 尾迹长度随 R 等比放大
    ctx.beginPath();
    ctx.moveTo(-R * 0.4, -3 + i * 6);
    ctx.quadraticCurveTo(-len * 0.55, -5 + i * 8, -len, -2 + i * 10);
    ctx.stroke();
  }

  // 外圈查克拉气环（青蓝 = 护盾同色系，区别于普通墨色障碍）
  ctx.globalAlpha = a * 0.85;
  ctx.strokeStyle = '#4892a4';
  ctx.lineWidth = Math.max(3, R * 0.09);              // 气环线宽随 R 加粗
  ctx.beginPath();
  ctx.arc(0, 0, R + 4 + Math.sin(r.age * 30) * 1.5, 0, Math.PI * 2);
  ctx.stroke();
  // 气环辉光：径向渐变晕开，让螺旋丸有"墨中透光"的层次
  glow(0, 0, R * 1.1, 'rgba(72,146,164,1)', a * 0.25);

  // 三条旋臂：相位错开 120°，高速旋转出螺旋感
  ctx.strokeStyle = INK;
  ctx.lineWidth = Math.max(3.5, R * 0.11);            // 旋臂线宽随 R 加粗
  for (let i = 0; i < 3; i++) {
    const p0 = spin + (i * Math.PI * 2) / 3;          // 每条臂起始相位相隔 120°
    ctx.beginPath();
    ctx.arc(0, 0, R * 0.72, p0, p0 + 1.9);            // 沿圆周画一段弧当作旋臂
    ctx.stroke();
  }

  // 实心墨核 + 纸色亮心：内圈旋转的实心团
  ctx.globalAlpha = a;
  ctx.fillStyle = INK;
  ctx.beginPath();
  ctx.arc(0, 0, R * 0.5, 0, Math.PI * 2);             // 实心墨核：占半径一半
  ctx.fill();
  ctx.fillStyle = '#f2ecd9';
  ctx.beginPath();
  ctx.arc(Math.cos(spin * 1.4) * 2, Math.sin(spin * 1.4) * 2, R * 0.2, 0, Math.PI * 2);   // 纸色亮心：随旋转移位
  ctx.fill();

  ctx.restore();
}
