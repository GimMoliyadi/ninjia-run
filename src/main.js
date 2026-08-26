// ================= 主循环 =================
import { G, ST, ctx } from './state.js';
import { update } from './engine.js';
import { initDecor } from './decor.js';
import { drawParticles } from './particles.js';
import { drawBackground } from './render/background.js';
import { drawCollectibles, drawObstacles, drawPlayer } from './render/entities.js';
import { drawNinjutsu } from './render/ninjutsu.js';
import { drawHUD, drawTitle, drawDead, drawPaused } from './render/hud.js';
import { drawDebug } from './render/debug.js';
import './input.js';

function loop(t) {
  let dt = Math.min((t - G.lastT) / 1000, 0.033);
  if (G.lastT === 0) dt = 0;
  G.lastT = t;
  if (G.state === ST.DEAD) dt *= 0.35;   // 死亡慢动作
  if (G.state === ST.TITLE) G.gameTime += dt;  // 标题屏闪烁动画计时

  try {
    if (G.state !== ST.PAUSED) update(dt);

    // 绘制
    drawBackground();
    drawCollectibles();
    drawObstacles();
    drawNinjutsu();
    try {
      if (G.state !== ST.DEAD) drawPlayer();
      if (G.debugMode) drawDebug();
    } catch (e) {
      // 角色绘制异常不中断整帧，记录并回退（由 drawPlayer 内部决定）
      console.error('角色绘制异常:', e);
    }

    drawParticles();

    if (G.state === ST.RUN) drawHUD();
    else if (G.state === ST.TITLE) drawTitle();
    else if (G.state === ST.DEAD) drawDead();
    else if (G.state === ST.PAUSED) drawPaused();
  } catch (e) {
    console.error('主循环异常:', e);
  }
  requestAnimationFrame(loop);
}

// 启动
initDecor();
requestAnimationFrame(loop);
