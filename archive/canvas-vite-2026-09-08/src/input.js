import { G, ST, canvas } from './state.js';
import { W, H, FIRE_BTN } from './constants.js';
import { startGame, doJump, startSlide, moveOnRope, castNinjutsu, castFireballs } from './player.js';

// 长按 ↓ 的防连按：滑铲是"按一下冲刺一段"，长按只触发一次
document.addEventListener('keydown', (e) => {
  const code = e.code;
  if (e.target.closest?.('input, select, textarea, [contenteditable="true"]')) return;
  // 调试模式开关（F7）
  if (code === 'F7') {
    e.preventDefault();
    G.debugMode = !G.debugMode;
    localStorage.setItem('inkNinjaDebug', G.debugMode ? '1' : '0');
    return;
  }
  // 暂停 / 恢复
  if (code === 'KeyP' || code === 'Escape') {
    e.preventDefault();
    if (G.state === ST.RUN) G.state = ST.PAUSED;
    else if (G.state === ST.PAUSED) G.state = ST.RUN;
    return;
  }
  // 暂停状态下仅允许重开，屏蔽跑酷按键
  if (G.state === ST.PAUSED) {
    if (code === 'KeyR') startGame();
    return;
  }
  // 重开：任何非标题状态（含死亡屏）按 R 重新开始——必须先于下方的死亡早退
  if (code === 'KeyR' && G.state !== ST.TITLE) { startGame(); return; }
  if (code === 'Space' || code === 'ArrowUp' || code === 'KeyW') {
    e.preventDefault();
    if (e.repeat) return;             // 按住不连跳
    G.jumpHeld = true;
    if (G.state === ST.TITLE || G.state === ST.DEAD) { startGame(); return; }
    if (G.state === ST.RUN) { G.player.ropeMode ? moveOnRope(-1) : doJump(); return; }
  }
  if (G.state === ST.TITLE || G.state === ST.DEAD) return;
  if (code === 'ArrowDown' || code === 'KeyS') {
    e.preventDefault();
    if (e.repeat) return;             // 长按住只算一次，避免把单按误判成连按俯冲
    if (G.state === ST.RUN) G.player.ropeMode ? moveOnRope(1) : startSlide();
    return;
  }
  if ((code === 'ShiftLeft' || code === 'ShiftRight' || code === 'KeyK') && G.state === ST.RUN) {
    e.preventDefault();
    castNinjutsu();
    return;
  }
  // 武器技能：火球术（冷却由 castFireballs 内部把关，冷却中按键无效果）
  if (code === 'KeyQ' && G.state === ST.RUN) {
    castFireballs();
    return;
  }
});

// 屏幕右下"火球术"按钮：鼠标/触屏点击施放（画布被 CSS 拉伸过，需换算回画布逻辑坐标）
canvas.addEventListener('pointerdown', (e) => {
  if (G.state !== ST.RUN) return;              // 仅跑酷中可点
  const rect = canvas.getBoundingClientRect();
  const scale = Math.min(rect.width / W, rect.height / H);   // object-fit: contain 的等比缩放
  const ox = (rect.width - W * scale) / 2;                    // 左右留边宽度
  const oy = (rect.height - H * scale) / 2;                   // 上下留边高度
  const x = (e.clientX - rect.left - ox) / scale;             // 换算回画布逻辑坐标
  const y = (e.clientY - rect.top - oy) / scale;
  const b = FIRE_BTN;
  const dx = x - b.x, dy = y - b.y;
  if (dx * dx + dy * dy <= (b.r + 8) * (b.r + 8)) castFireballs();   // 命中按钮圆（外扩 8px 容差）
});

document.addEventListener('keyup', (e) => {
  const code = e.code;
  if (code === 'Space' || code === 'ArrowUp' || code === 'KeyW') G.jumpHeld = false;
});

window.addEventListener('blur', () => {
  G.jumpHeld = false;
});
