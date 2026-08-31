import { G, ctx } from '../state.js';
import { W, H, KAI, INK, RED, ENERGY_MAX, HP_MAX, BG, SLIDE_H, STAND_H, ZONE_TRANSITION_T } from '../constants.js';
import { brushText, stamp } from './text.js';
import { zoneName } from '../zone.js';

export function drawHUD() {
  // 区域切换横幅：切换瞬间泼墨过后，区域名居中渐显渐隐
  if (G.zoneTransitionT > 0) {
    const t = G.zoneTransitionT / ZONE_TRANSITION_T;          // 1 → 0
    const a = Math.sin(Math.min(1, (1 - t) * 2.2) * Math.PI); // 淡入淡出
    ctx.save();
    ctx.globalAlpha = a * 0.9;
    brushText('——  ' + zoneName(G.zone) + '  ——', W / 2, 148, 34, INK);
    ctx.restore();
  }

  // 血条：受伤才显示（hpBarT 0~1），悬浮在角色头顶的墨水横条 + 数值，中心随角色（含滑铲前移）移动。
  // 低于 30% 变红警示，受击闪烁（无敌期间高亮）。
  const p = G.player;
  const barA = Math.max(0, p.hpBarT);
  if (barA > 0.01) {
    const hpW = 116, hpH = 10;
    const hpX = p.x + G.dashShift - hpW / 2;             // 条中心对准角色
    const top = p.y - (p.sliding ? SLIDE_H : STAND_H);   // 角色头顶 y
    const hpY = top - hpH - 12;                          // 条顶在头顶上方留出间距
    const hpFrac = Math.max(0, p.hp / HP_MAX);
    const hitFlash = p.invuln > 0 && Math.floor(G.gameTime * 12) % 2 === 0;
    ctx.save();
    ctx.globalAlpha = barA;
    ctx.fillStyle = 'rgba(43,43,49,0.1)';
    ctx.fillRect(hpX, hpY, hpW, hpH);
    ctx.fillStyle = hitFlash ? RED : (hpFrac > 0.3 ? INK : RED);
    ctx.fillRect(hpX + 1, hpY + 1, (hpW - 2) * hpFrac, hpH - 2);
    ctx.font = '10px ' + KAI;
    ctx.fillStyle = INK;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    ctx.fillText(Math.ceil(p.hp) + '/' + HP_MAX, p.x + G.dashShift, hpY + hpH + 4);
    ctx.restore();
  }

  // 分数 / 距离 —— 右上角
  brushText(String(G.score), W - 42, 42, 40, INK, 'right');
  ctx.save();
  ctx.font = '18px ' + KAI;
  ctx.fillStyle = 'rgba(43,43,49,0.55)';
  ctx.textAlign = 'right';
  ctx.textBaseline = 'middle';
  ctx.fillText(G.distM + ' 米', W - 46, 78);
  ctx.restore();

  // 忍术能量 —— 左上角圆环，中心一个忍字
  const cx = 48, cy = 44, R = 23;
  ctx.save();
  // 底环
  ctx.lineWidth = 8;
  ctx.strokeStyle = 'rgba(43,43,49,0.14)';
  ctx.beginPath();
  ctx.arc(cx, cy, R, 0, Math.PI * 2);
  ctx.stroke();
  // 进度弧
  const frac = Math.min(1, G.energy / ENERGY_MAX);
  if (frac > 0) {
    const grd = ctx.createLinearGradient(cx - R, cy - R, cx + R, cy + R);
    grd.addColorStop(0, '#d8a441');
    grd.addColorStop(1, '#c0392b');
    ctx.strokeStyle = G.energy >= ENERGY_MAX ? RED : grd;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.arc(cx, cy, R - 1, -Math.PI / 2, -Math.PI / 2 + frac * Math.PI * 2);
    ctx.stroke();
  }
  // 中心忍字
  brushText('忍', cx, cy + 1, 17, INK);
  ctx.restore();
  // 键位说明
  ctx.save();
  ctx.font = '13px ' + KAI;
  ctx.fillStyle = 'rgba(43,43,49,0.5)';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('Shift / K', cx, cy + R + 17);
  ctx.restore();
  // 能量满提示
  if (G.energy >= ENERGY_MAX) {
    brushText('忍术已满！', cx + 60, cy, 18, RED, 'left');
  }

  // 连击：固定 UI 区域，短暂淡出，不遮挡角色与前方障碍
  if (G.combo >= 2) {
    const fade = Math.min(1, G.comboTimer / 1.2);
    ctx.save();
    ctx.globalAlpha = fade;
    brushText('连击 x' + Math.min(G.combo, 5), W / 2, 108, 26, RED);
    ctx.restore();
  }
  // 调试模式提示
  if (G.debugMode) {
    ctx.font = '13px ' + KAI;
    ctx.fillStyle = 'rgba(180,40,40,0.8)';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.fillText('调试模式（F7 关闭）', 10, H - 22);
  }
}

// ================= 标题屏 =================
export function drawTitle() {
  // 淡墨罩
  ctx.fillStyle = 'rgba(43,43,49,0.03)';
  ctx.fillRect(0, 0, W, H);

  brushText('水 墨 忍 者', W / 2, 130, 84, INK);
  brushText('横板跑酷 · 平地 / 深坑 / 疾驰', W / 2, 205, 26, 'rgba(43,43,49,0.6)');
  stamp('忍', W / 2, 295, 64, -0.08);

  // 操作说明
  ctx.save();
  ctx.font = '19px ' + KAI;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = 'rgba(43,43,49,0.78)';
  const lines = [
    '空格 / ↑ ：跳跃 · 二段跳（点一下就跳）',
    '↓：滑铲前移 · 接跳可跳更远',
    '空中按↓ = 中断跳跃落下 · 连按两次↓ = 俯冲滑铲',
    '深坑：跳跃越过，掉下去就会死',
    'Shift / K：忍术（清屏）  ·  R：重开  ·  F7：调试',
    'P / Esc：暂停',
  ];
  lines.forEach((t, i) => ctx.fillText(t, W / 2, 340 + i * 30));

  if (G.best > 0) ctx.fillText('最佳成绩  ' + G.best, W / 2, 470);
  ctx.restore();

  // 开始提示（闪烁）
  const blink = Math.floor(G.gameTime * 2) % 2 === 0;
  if (blink) brushText('按 空格 开始', W / 2, 500, 30, INK);
  stamp('忍', 70, H - 60, 40, 0.2);
  stamp('忍', W - 70, 64, 46, -0.15);
}

// ================= 结算屏 =================
export function drawDead() {
  // 慢动作墨罩渐显
  const a = Math.min(1, G.deathT * 3);
  ctx.fillStyle = 'rgba(43,43,49,' + (0.18 * a) + ')';
  ctx.fillRect(0, 0, W, H);

  ctx.save();
  ctx.globalAlpha = a;
  stamp('滅', W / 2, 150, 90, -0.12);
  brushText(String(G.score), W / 2, 240, 60, INK);
  ctx.font = '18px ' + KAI;
  ctx.textAlign = 'center';
  ctx.fillStyle = 'rgba(43,43,49,0.7)';
  ctx.fillText('距离 ' + G.distM + ' 米', W / 2, 285);
  if (G.newBest) {
    ctx.fillStyle = RED;
    ctx.font = 'bold 24px ' + KAI;
    ctx.fillText('新纪录！', W / 2, 320);
  } else {
    ctx.fillText('最佳 ' + G.best, W / 2, 320);
  }
  ctx.restore();

  if (Math.floor(G.deathT * 2) % 2 === 0) {
    brushText('按 空格 再玩 · R 重开', W / 2, 460, 26, INK);
  }
}

export function drawPaused() {
  ctx.save();
  ctx.globalAlpha = 0.55;
  ctx.fillStyle = BG;
  ctx.fillRect(0, 0, W, H);
  ctx.restore();
  brushText('已暂停', W / 2, H / 2 - 30, 52, INK);
  brushText('P / Esc 继续 · R 重开', W / 2, H / 2 + 16, 22, INK);
}
