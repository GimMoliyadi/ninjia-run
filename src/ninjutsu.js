import { G } from './state.js';
import { CLONE_DURATION, CLONE_OFFSET } from './constants.js';
import { inkBurst } from './particles.js';

// 墨影分身：释放后生成一个跟随玩家的半透明替身，位于玩家前方固定偏移。
// 分身被障碍击中会替玩家挡灾消散（见 physics 的碰撞分支），
// 无人替挡则存活 CLONE_DURATION 后自然消散。
export function updateNinjutsu(dt) {
  const c = G.clone;
  if (!c) return;

  c.age += dt;
  // 分身跟随玩家：世界坐标随卷轴滚动保持屏幕前方偏移
  c.x = G.scrollX + G.player.x + G.dashShift + CLONE_OFFSET;
  c.y = G.player.y;

  if (c.age >= c.duration) {
    G.clone = null;
    inkBurst(c.x - G.scrollX, c.y - 30, 16, 0.9);
  }
}
