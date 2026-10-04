import { G, ST } from './state.js';
import { COYOTE_T, SLIDE_H, STAND_H, PW, HP_MAX, HP_REGEN, HP_BAR_FADE } from './constants.js';
import { updateSpeed, updateGravity, updateEnemies, updateCollisions, collectPickups, updateMetrics } from './physics.js';
import { spawnLoop } from './generator.js';
import { updateParticles } from './particles.js';
import { updateNinjutsu } from './ninjutsu.js';
import { updateFireballs } from './fireballs.js';
import { updateZone } from './zone.js';

export function update(dt) {
  if (G.state === ST.TITLE) return;
  if (G.state === ST.DEAD) {
    G.deathT += dt;
    updateParticles(dt);
    return;
  }

  G.gameTime += dt;
  updateSpeed(dt);

  updateZone();
  if (G.zoneTransitionT > 0) G.zoneTransitionT = Math.max(0, G.zoneTransitionT - dt);

  // 土狼时间 / 跳跃缓冲衰减
  G.jumpBuf = Math.max(0, G.jumpBuf - dt);
  if (G.player.onGround) G.coyote = COYOTE_T;
  else G.coyote = Math.max(0, G.coyote - dt);

  updateGravity(dt);
  updateEnemies(dt);
  updateNinjutsu(dt);
  updateFireballs(dt);
  // 火球术冷却倒计时：归零后 Q / 按钮才可再次释放
  if (G.fireCd > 0) G.fireCd = Math.max(0, G.fireCd - dt);
  // 血条自然恢复：每秒回 HP_REGEN，满血封顶
  if (G.player.hp < HP_MAX) G.player.hp = Math.min(HP_MAX, G.player.hp + HP_REGEN * dt);
  // 血条显隐：不满血持续显示；回满后按 HP_BAR_FADE 淡出，受伤（physics 置 hpBarT=1）再点亮
  if (G.player.hp >= HP_MAX) G.player.hpBarT = Math.max(0, G.player.hpBarT - dt / HP_BAR_FADE);

  if (G.player.invuln > 0) G.player.invuln -= dt;
  if (G.player.shieldT > 0) G.player.shieldT = Math.max(0, G.player.shieldT - dt);

  // 连击系统已移除：金币改为固定加分，无需连击计时
  spawnLoop();
  updateParticles(dt);

  // 碰撞：角色盒（世界坐标 X = 屏幕 X + 卷轴偏移）
  const h = G.player.sliding ? SLIDE_H : STAND_H;
  const px = G.scrollX + G.player.x + G.dashShift - PW / 2;
  const ropeProgress = Math.max(0, Math.min(1, G.player.ropeOffset));
  const py = G.player.ropeMode ? G.player.y - h * (1 - ropeProgress) : G.player.y - h;
  const box = { x: px, y: py, w: PW, h };

  if (updateCollisions(box)) return;
  collectPickups(box);
  updateMetrics();
}
