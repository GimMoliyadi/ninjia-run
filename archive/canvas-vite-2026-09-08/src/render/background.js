import { G, ctx } from '../state.js';
import { W, H, GROUND, INK, RED, ZONE_TRANSITION_T } from '../constants.js';
import { segTypeAt, groundYAt } from '../terrain.js';
import { ZONE, ZONE_CFG } from '../zone.js';
import { glow } from '../particles.js';

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

// —— 竹林区装饰：远山 + 青竹 ——
function drawBambooDecor() {
  // 远山（两层循环滚动）
  const cfg = ZONE_CFG[ZONE.BAMBOO];
  ctx.fillStyle = INK;
  G.mountains.forEach((m, i) => {
    const mw = m.w * 2.4;
    const mx = ((m.x - G.scrollX * 0.12) % (W + mw) + (W + mw)) % (W + mw) - mw * 0.6;
    // 透明度由区域配置的 mountainA 区间按山的远近插值（修复原硬编码死值）
    const t = i / Math.max(1, G.mountains.length - 1);
    ctx.globalAlpha = cfg.mountainA[0] + (cfg.mountainA[1] - cfg.mountainA[0]) * t;
    ctx.beginPath();
    ctx.moveTo(mx, GROUND + 20);
    ctx.quadraticCurveTo(mx + mw * 0.25, GROUND - m.h, mx + mw * 0.5, GROUND - m.h * 0.4);
    ctx.quadraticCurveTo(mx + mw * 0.75, GROUND - m.h * 0.9, mx + mw, GROUND + 20);
    ctx.closePath();
    ctx.fill();
  });
  ctx.globalAlpha = 1;

  // 远竹
  const leaf = ZONE_CFG[ZONE.BAMBOO].accent;   // 竹叶用区域墨绿点缀，不再死墨色
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
    ctx.globalAlpha = 0.1;
    ctx.fillStyle = leaf;
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
}

// —— 村町区装饰：屋顶剪影 + 灯笼 ——
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

function drawVillageLamps() {
  const a = ZONE_CFG[ZONE.VILLAGE].accent;
  for (let i = 0; i < G.lamps.length; i++) {
    const lx = wrap(G.lamps[i].x - G.scrollX * 0.4, W + 90) - 45;
    const ly = GROUND - 58 - (i % 3) * 26;
    ctx.save();
    ctx.globalAlpha = 0.7 + 0.3 * Math.sin(G.gameTime * 2 + i * 1.7);
    ctx.strokeStyle = a;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(lx, ly - 14);
    ctx.lineTo(lx, ly + 10);
    ctx.stroke();
    // 灯笼光晕：径向渐变替代平涂圆
    glow(lx, ly, 28, a, 0.35);
    ctx.globalAlpha = 0.65;
    ctx.fillStyle = a;
    ctx.beginPath();
    ctx.arc(lx, ly, 8, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }
  ctx.globalAlpha = 1;
}

function drawVillageSmoke() {
  ctx.save();
  ctx.globalAlpha = 0.09;
  ctx.fillStyle = INK;
  for (let i = 0; i < 4; i++) {
    const x = wrap(i * 197 + 140 - G.scrollX * 0.31, W + 60) - 30;
    const t = (G.gameTime * 0.5 + i * 1.3) % 3;
    ctx.beginPath();
    ctx.arc(x + t * 18, GROUND - 118 - t * 34, 6 + t * 5, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

// —— 冥山区装饰：枯树剪影 + 鬼火 + 雾 ——
function drawDeadTrees() {
  ctx.strokeStyle = INK;
  ctx.lineWidth = 4;
  ctx.lineCap = 'round';
  for (const t of G.deadTrees) {
    const tx = wrap(t.x - G.scrollX * 0.5, W + 160) - 80;
    if (tx < -80 || tx > W + 80) continue;
    ctx.globalAlpha = t.a;
    const baseY = GROUND - 6;
    ctx.beginPath();
    ctx.moveTo(tx, baseY);
    ctx.quadraticCurveTo(tx + t.lean * 20, baseY - t.h * 0.55, tx + t.lean * 30, baseY - t.h);
    ctx.stroke();
    for (let j = 0; j < 3; j++) {
      ctx.beginPath();
      ctx.moveTo(tx + t.lean * 30 * (j + 1) / 3, baseY - t.h * (0.7 - j * 0.14));
      ctx.quadraticCurveTo(tx + t.lean * 30 * (j + 1) / 3 + 14, baseY - t.h * (0.78 - j * 0.14), tx + t.lean * 30 * (j + 1) / 3 + 30, baseY - t.h * (0.72 - j * 0.14));
      ctx.stroke();
    }
  }
  ctx.globalAlpha = 1;
}

function drawGhostFire() {
  const a = ZONE_CFG[ZONE.MOUNTAIN].accent;
  for (const f of G.ghostFires) {
    const fx = wrap(f.x - G.scrollX * 0.6, W + 80) - 40;
    const fy = GROUND - f.h + Math.sin(G.gameTime * 1.6 + f.ph) * 6;
    ctx.save();
    const flicker = 0.5 + 0.25 * Math.sin(G.gameTime * 3 + f.ph);
    // 鬼火辉光：径向渐变晕开，比平涂椭圆有"幽冥火"的透亮感
    glow(fx, fy, 22, a, 0.28 + flicker * 0.1);
    ctx.globalAlpha = flicker;
    ctx.fillStyle = a;
    ctx.beginPath();
    ctx.ellipse(fx, fy, 6, 10, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }
  ctx.globalAlpha = 1;
}

function drawMountainMist() {
  const g = ctx.createLinearGradient(0, GROUND - 60, 0, GROUND + 20);
  g.addColorStop(0, 'rgba(180,198,214,0)');
  g.addColorStop(0.5, 'rgba(180,198,214,0.28)');
  g.addColorStop(1, 'rgba(180,198,214,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, GROUND - 60, W, 80);
}

// 区域天空渐变：三段色标（顶/中/底）纵向渐变，让天空有空间层次
function drawSky(cfg) {
  const g = ctx.createLinearGradient(0, 0, 0, H);
  g.addColorStop(0, cfg.sky[0]);
  g.addColorStop(0.55, cfg.sky[1] || cfg.sky[0]);
  g.addColorStop(1, cfg.sky[2] || cfg.sky[1] || cfg.sky[0]);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, W, H);
}

// 天空天体：太阳/月亮 + 一圈径向辉光，给每个区域一个天空焦点
function drawHeaven(cfg) {
  const hv = cfg.heaven;
  if (!hv) return;
  const hx = hv.x * W, hy = hv.y * H;
  // 辉光：大范围径向渐变，模拟光线晕开
  const g = ctx.createRadialGradient(hx, hy, 0, hx, hy, hv.r * 5);
  g.addColorStop(0, hv.glow);
  g.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.save();
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(hx, hy, hv.r * 5, 0, Math.PI * 2);
  ctx.fill();
  // 天体本体
  ctx.globalAlpha = 1;
  ctx.fillStyle = hv.color;
  ctx.beginPath();
  ctx.arc(hx, hy, hv.r, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function drawForegroundBranches() {
  ctx.save();
  ctx.globalAlpha = 0.16;
  ctx.strokeStyle = INK;
  ctx.fillStyle = INK;
  ctx.lineWidth = 5;
  // 按区域换前景素材：竹林=竹叶, 村=瓦檐/灯笼线, 山=枯枝
  if (G.zone === ZONE.VILLAGE) {
    // 村町：屋檐横线 + 瓦当剪影，随滚动缓缓移动
    const vy = 0.6;
    for (let i = 0; i < 4; i++) {
      const x = wrap(i * 310 + 120 - G.scrollX * vy, W * 2) - 100;
      ctx.globalAlpha = 0.12;
      ctx.strokeStyle = INK;
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.moveTo(x, 60 + i * 30);
      ctx.lineTo(x + 80, 60 + i * 30);
      ctx.stroke();
      ctx.fillStyle = INK;
      ctx.beginPath();
      ctx.arc(x + 10, 60 + i * 30, 6, 0, Math.PI * 2);
      ctx.fill();
      ctx.arc(x + 70, 60 + i * 30, 6, 0, Math.PI * 2);
      ctx.fill();
    }
  } else if (G.zone === ZONE.MOUNTAIN) {
    // 冥山：枯枝剪影，s 形斜出
    const vy = 0.5;
    for (let i = 0; i < 3; i++) {
      const x = wrap(i * 340 + 80 - G.scrollX * vy, W * 1.8) - 60;
      ctx.globalAlpha = 0.14;
      ctx.strokeStyle = INK;
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.moveTo(x, -10);
      ctx.quadraticCurveTo(x + 30, 60, x + 10, 90);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(x + 10, 40);
      ctx.quadraticCurveTo(x + 40, 50, x + 50, 30);
      ctx.stroke();
    }
  } else {
    // 竹林：竹叶前景（原版全局素材，改为随滚动变化）
    const vy = 0.4;
    for (let i = 0; i < 3; i++) {
      const x = wrap(i * 320 + 70 - G.scrollX * vy, W * 2) - 80;
      const direction = i % 2 ? -1 : 1;
      ctx.globalAlpha = 0.16;
      ctx.strokeStyle = INK;
      ctx.fillStyle = ZONE_CFG[ZONE.BAMBOO].accent;
      ctx.lineWidth = 5;
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
  }
  ctx.restore();
}

export function drawBackground() {
  const cfg = ZONE_CFG[G.zone] || ZONE_CFG[ZONE.BAMBOO];
  drawSky(cfg);
  drawHeaven(cfg);
  drawPaperGrain();

  // 云（所有区共有）
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

  // 区域装饰
  if (G.zone === ZONE.VILLAGE) {
    drawDistantRoofs();
    drawVillageSmoke();
  } else if (G.zone === ZONE.MOUNTAIN) {
    drawDeadTrees();
    drawGhostFire();
    drawMountainMist();
  } else {
    drawBambooDecor();
  }

  // 地形流：平地、斜面、空中横板与绳索都从同一段数据绘制。
  ctx.fillStyle = cfg.ground;
  for (const seg of G.terrain) {
    if (seg.type === 'pit' || seg.type === 'rope') continue;
    const x0 = seg.start - G.scrollX, x1 = seg.end - G.scrollX;
    if (x1 < -12 || x0 > W + 12) continue;
    const gx0 = Math.max(0, x0), gx1 = Math.min(W, x1), w = gx1 - gx0;
    if (w <= 0) continue;
    const y0 = seg.type === 'slope' ? seg.y0 : (seg.y ?? GROUND);
    const y1 = seg.type === 'slope' ? seg.y1 : y0;
    if (seg.type === 'platform') {
      ctx.fillRect(gx0, y0, w, 12);
      ctx.strokeStyle = INK; ctx.lineWidth = 3; ctx.strokeRect(gx0, y0, w, 12);
    } else if (seg.type === 'slope') {
      ctx.beginPath(); ctx.moveTo(gx0, y0); ctx.lineTo(gx1, y1); ctx.lineTo(gx1, H); ctx.lineTo(gx0, H); ctx.closePath(); ctx.fill();
    } else ctx.fillRect(gx0, y0 - 1, w, H - y0 + 41);
  }
  // 地面顶部墨线：恒定 GROUND，穿过深坑时断开
  ctx.strokeStyle = INK;
  ctx.lineWidth = 4;
  ctx.beginPath();
  let topPen = false;
  for (let sx = 0; sx <= W; sx += 8) {
    if (segTypeAt(G.scrollX + sx) === 'pit' || segTypeAt(G.scrollX + sx) === 'rope') { topPen = false; continue; }
    const gy = groundYAt(G.scrollX + sx);
    if (!topPen) { ctx.moveTo(sx, gy); topPen = true; } else ctx.lineTo(sx, gy);
  }
  ctx.stroke();
  // 地面下缘柔墨带（分层，不抖，穿过深坑断开）
  ctx.strokeStyle = 'rgba(28,28,34,0.28)';
  ctx.lineWidth = 12;
  ctx.beginPath();
  let botPen = false;
  for (let sx = 0; sx <= W; sx += 8) {
    if (segTypeAt(G.scrollX + sx) === 'pit' || segTypeAt(G.scrollX + sx) === 'rope') { botPen = false; continue; }
    const gy = groundYAt(G.scrollX + sx);
    if (!botPen) { ctx.moveTo(sx, gy + 1); botPen = true; } else ctx.lineTo(sx, gy + 1);
  }

  // 绳索：粗绳体、端部连接和抓握节点，明确提示可抓取/翻越的高度。
  for (const seg of G.terrain) {
    if (seg.type !== 'rope') continue;
    const x0 = seg.start - G.scrollX, x1 = seg.end - G.scrollX;
    if (x1 < 0 || x0 > W) continue;
    const leftSlope = G.terrain.find(s => s.type === 'slope' && Math.abs(s.end - seg.start) < 1);
    const rightSlope = G.terrain.find(s => s.type === 'slope' && Math.abs(s.start - seg.end) < 1);
    ctx.save();
    ctx.lineCap = 'round';
    ctx.strokeStyle = 'rgba(28,28,34,0.22)'; ctx.lineWidth = 14;
    ctx.beginPath(); ctx.moveTo(x0, seg.y + 2); ctx.lineTo(x1, seg.y + 2); ctx.stroke();
    ctx.strokeStyle = INK; ctx.lineWidth = 8;
    ctx.beginPath(); ctx.moveTo(x0, seg.y); ctx.lineTo(x1, seg.y); ctx.stroke();
    ctx.strokeStyle = 'rgba(216,164,65,0.72)'; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.moveTo(x0 + 5, seg.y - 1); ctx.lineTo(x1 - 5, seg.y - 1); ctx.stroke();
    // 路线边界绷带：让绳索段在长距离滚动时仍保持清晰的入口/出口方向。
    ctx.strokeStyle = 'rgba(165,58,46,0.6)'; ctx.lineWidth = 2;
    for (const edge of [x0, x1]) {
      ctx.beginPath(); ctx.moveTo(edge, seg.y - 18); ctx.lineTo(edge, seg.y + 18); ctx.stroke();
    }
    ctx.fillStyle = RED;
    for (let x = Math.max(0, x0 + 18); x < Math.min(W, x1 - 8); x += 44) {
      ctx.beginPath(); ctx.arc(x, seg.y, 5, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = INK; ctx.lineWidth = 2; ctx.stroke();
    }
    if (leftSlope) {
      const sy = leftSlope.y1 ?? seg.y;
      ctx.strokeStyle = INK; ctx.lineWidth = 5;
      ctx.beginPath(); ctx.moveTo(x0 - 18, sy + 2); ctx.quadraticCurveTo(x0 - 7, seg.y + 1, x0, seg.y); ctx.stroke();
    }
    if (rightSlope) {
      const sy = rightSlope.y0 ?? seg.y;
      ctx.strokeStyle = INK; ctx.lineWidth = 5;
      ctx.beginPath(); ctx.moveTo(x1, seg.y); ctx.quadraticCurveTo(x1 + 7, seg.y + 1, x1 + 18, sy + 2); ctx.stroke();
    }
    ctx.restore();
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

  // 区域切换泼墨过渡：全屏墨色淡入淡出
  if (G.zoneTransitionT > 0) {
    const a = Math.min(1, G.zoneTransitionT / ZONE_TRANSITION_T);
    ctx.fillStyle = 'rgba(43,43,49,' + (0.78 * a).toFixed(3) + ')';
    ctx.fillRect(0, 0, W, H);
  }
}
