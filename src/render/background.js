import { G, ctx } from '../state.js';
import { W, H, GROUND, INK } from '../constants.js';
import { segTypeAt } from '../terrain.js';

function wrap(x, span) {
  return ((x % span) + span) % span;
}

function drawPaperGrain() {
  ctx.fillStyle = INK;
  ctx.globalAlpha = 0.028;
  for (let i = 0; i < 80; i++) {
    const x = wrap(i * 149 + 37, W);
    const y = wrap(i * 83 + 19, H);
    ctx.fillRect(x, y, 1 + (i % 3), 1);
  }
  ctx.globalAlpha = 1;
}

function drawDistantRoofs() {
  ctx.fillStyle = INK;
  for (let i = 0; i < 5; i++) {
    const roofW = 92 + (i % 2) * 38;
    const x = wrap(i * 267 + 110 - G.scrollX * 0.21, W + roofW * 2) - roofW;
    const baseY = GROUND - 54 - (i % 3) * 24;
    ctx.globalAlpha = 0.1 + (i % 2) * 0.025;
    ctx.fillRect(x + roofW * 0.18, baseY, roofW * 0.64, 34 + (i % 2) * 14);
    ctx.beginPath();
    ctx.moveTo(x, baseY);
    ctx.lineTo(x + roofW * 0.5, baseY - 28);
    ctx.lineTo(x + roofW, baseY);
    ctx.closePath();
    ctx.fill();
    ctx.fillRect(x - 8, baseY - 2, roofW + 16, 4);
  }
  ctx.globalAlpha = 1;
}

function drawForegroundBranches() {
  ctx.save();
  ctx.globalAlpha = 0.16;
  ctx.strokeStyle = INK;
  ctx.fillStyle = INK;
  ctx.lineWidth = 5;
  for (let i = 0; i < 3; i++) {
    const x = i % 2 ? W - 70 - i * 20 : 46 + i * 18;
    const direction = i % 2 ? -1 : 1;
    ctx.beginPath();
    ctx.moveTo(x, -20);
    ctx.quadraticCurveTo(x + direction * 28, 76, x + direction * 70, 132);
    ctx.stroke();
    for (let j = 0; j < 4; j++) {
      const y = 26 + j * 27;
      ctx.beginPath();
      ctx.ellipse(x + direction * (17 + j * 10), y, 16, 4, direction * 0.5, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  ctx.restore();
}

export function drawBackground() {
  // 宣纸底
  const g = ctx.createLinearGradient(0, 0, 0, H);
  g.addColorStop(0, '#f7f2e3');
  g.addColorStop(1, '#ece4cf');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, W, H);
  drawPaperGrain();

  // 远山（两层循环滚动）
  ctx.fillStyle = INK;
  for (const m of G.mountains) {
    const mw = m.w * 2.4;
    const mx = ((m.x - G.scrollX * 0.12) % (W + mw) + (W + mw)) % (W + mw) - mw * 0.6;
    ctx.globalAlpha = m.alpha;
    ctx.beginPath();
    ctx.moveTo(mx, GROUND + 20);
    ctx.quadraticCurveTo(mx + mw * 0.25, GROUND - m.h, mx + mw * 0.5, GROUND - m.h * 0.4);
    ctx.quadraticCurveTo(mx + mw * 0.75, GROUND - m.h * 0.9, mx + mw, GROUND + 20);
    ctx.closePath();
    ctx.fill();
  }
  ctx.globalAlpha = 1;
  drawDistantRoofs();

  // 云
  for (const c of G.clouds) {
    const cx = ((c.x - G.scrollX * 0.3) % (W * 2) + (W * 2)) % (W * 2) - 100;
    ctx.globalAlpha = c.a;
    ctx.fillStyle = INK;
    for (let i = 0; i < 4; i++) {
      ctx.beginPath();
      ctx.arc(cx + i * 16 * c.s, c.y + Math.sin(i) * 6, (9 + Math.sin(i * 2.1)) * c.s, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  ctx.globalAlpha = 1;

  // 远竹
  for (const b of G.bamboos) {
    const bx = ((b.x - G.scrollX * 0.55) % 40000 + 40000) % 40000;
    if (bx < -40 || bx > W + 40) continue;
    ctx.globalAlpha = 0.09;
    ctx.strokeStyle = INK;
    ctx.fillStyle = INK;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(bx, GROUND + 10);
    ctx.quadraticCurveTo(bx + b.lean * b.h, GROUND - b.h * 0.6, bx + b.lean * b.h * 1.2, GROUND - b.h);
    ctx.stroke();
    for (let i = 0; i < 3; i++) {
      const leafY = GROUND - b.h * (0.38 + i * 0.2);
      const leafX = bx + b.lean * b.h * (0.48 + i * 0.2);
      ctx.beginPath();
      ctx.ellipse(leafX - 9, leafY, 14, 3, -0.42, 0, Math.PI * 2);
      ctx.ellipse(leafX + 9, leafY - 6, 14, 3, 0.42, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  // 地形：平地段铺实心地面，深坑处镂空（挖空效果，非叠黑块）
  ctx.fillStyle = 'rgba(58,54,48,0.52)';
  for (const seg of G.terrain) {
    if (seg.type !== 'flat') continue;
    const x0 = seg.start - G.scrollX, x1 = seg.end - G.scrollX;
    if (x1 < -12 || x0 > W + 12) continue;
    const gx0 = Math.max(0, x0), gx1 = Math.min(W, x1), w = gx1 - gx0;
    if (w > 0) ctx.fillRect(gx0, GROUND - 1, w, H - GROUND + 41);
  }
  // 地面顶部墨线：恒定 GROUND，穿过深坑时断开
  ctx.strokeStyle = INK;
  ctx.lineWidth = 4;
  ctx.beginPath();
  let topPen = false;
  for (let sx = 0; sx <= W; sx += 8) {
    if (segTypeAt(G.scrollX + sx) === 'pit') { topPen = false; continue; }
    if (!topPen) { ctx.moveTo(sx, GROUND); topPen = true; } else ctx.lineTo(sx, GROUND);
  }
  ctx.stroke();
  // 地面下缘柔墨带（分层，不抖，穿过深坑断开）
  ctx.strokeStyle = 'rgba(28,28,34,0.28)';
  ctx.lineWidth = 12;
  ctx.beginPath();
  let botPen = false;
  for (let sx = 0; sx <= W; sx += 8) {
    if (segTypeAt(G.scrollX + sx) === 'pit') { botPen = false; continue; }
    if (!botPen) { ctx.moveTo(sx, GROUND + 1); botPen = true; } else ctx.lineTo(sx, GROUND + 1);
  }
  ctx.stroke();

  // 深坑：地面上挖空的深渊，坑口断壁、向下渐暗，望不见底
  for (const seg of G.terrain) {
    if (seg.type !== 'pit') continue;
    const x0 = seg.start - G.scrollX, x1 = seg.end - G.scrollX;
    if (x1 < -12 || x0 > W + 12) continue;
    const gx0 = Math.max(0, x0), gx1 = Math.min(W, x1), wx = gx1 - gx0;
    if (wx <= 0) continue;
    const pitGrad = ctx.createLinearGradient(0, GROUND, 0, H);
    pitGrad.addColorStop(0, '#2e2923');
    pitGrad.addColorStop(0.45, '#17130e');
    pitGrad.addColorStop(1, '#0a0806');
    ctx.fillStyle = pitGrad;
    ctx.fillRect(gx0, GROUND, wx, H - GROUND);
    // 坑口向内压暗，强调塌陷的深度
    const mouthGrad = ctx.createLinearGradient(0, GROUND, 0, GROUND + 42);
    mouthGrad.addColorStop(0, 'rgba(0,0,0,0.3)');
    mouthGrad.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = mouthGrad;
    ctx.fillRect(gx0, GROUND, wx, 42);
    // 坑口两角墨痕：斜削断壁，表现被挖断的土石边缘
    ctx.fillStyle = 'rgba(28,26,23,0.92)';
    ctx.beginPath();
    ctx.moveTo(gx0, GROUND); ctx.lineTo(gx0 - 7, GROUND - 2); ctx.lineTo(gx0 + 3, GROUND + 13); ctx.closePath(); ctx.fill();
    ctx.beginPath();
    ctx.moveTo(gx1, GROUND); ctx.lineTo(gx1 + 7, GROUND - 2); ctx.lineTo(gx1 - 3, GROUND + 13); ctx.closePath(); ctx.fill();
  }

  // 前景草（只在平地段，淡、稀疏，避免干扰视线）
  ctx.globalAlpha = 0.16;
  ctx.strokeStyle = '#3a3730';
  ctx.lineWidth = 2;
  for (let i = 0; i < 20; i++) {
    const gx = ((i * 173 + 60 - G.scrollX) % (W * 2) + (W * 2)) % (W * 2) - 40;
    if (segTypeAt(G.scrollX + gx) !== 'flat') continue;
    const gh = 7 + (i % 4) * 3;
    ctx.beginPath();
    ctx.moveTo(gx, GROUND);
    ctx.quadraticCurveTo(gx + 3, GROUND - gh, gx + (i % 2 ? 7 : -7), GROUND - gh - 2);
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
  drawForegroundBranches();
}
