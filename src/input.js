import { G, ST } from './state.js';
import { startGame, doJump, startSlide, castNinjutsu } from './player.js';

// 长按 ↓ 的防连按：滑铲是"按一下冲刺一段"，长按只触发一次
document.addEventListener('keydown', (e) => {
  const code = e.code;
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
    if (G.state === ST.RUN) { doJump(); return; }
  }
  if (G.state === ST.TITLE || G.state === ST.DEAD) return;
  if (code === 'ArrowDown' || code === 'KeyS') {
    e.preventDefault();
    if (e.repeat) return;             // 长按住只算一次，避免把单按误判成连按俯冲
    if (G.state === ST.RUN) startSlide();
    return;
  }
  if ((code === 'ShiftLeft' || code === 'ShiftRight' || code === 'KeyK') && G.state === ST.RUN) {
    e.preventDefault();
    castNinjutsu();
    return;
  }
});

document.addEventListener('keyup', (e) => {
  const code = e.code;
  if (code === 'Space' || code === 'ArrowUp' || code === 'KeyW') G.jumpHeld = false;
});
