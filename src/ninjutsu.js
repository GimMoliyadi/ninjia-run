import { G } from './state.js';
import { CLEAR_SCORE, NINJUTSU_SPEED } from './constants.js';
import { inkBurst } from './particles.js';

export function updateNinjutsu(dt) {
  const n = G.ninjutsu;
  if (!n) return;

  n.age += dt;
  const previousX = n.x;
  n.x += NINJUTSU_SPEED * dt;
  for (let i = G.obstacles.length - 1; i >= 0; i--) {
    const ob = G.obstacles[i];
    if (ob.x > n.x + n.radius || ob.x + ob.w < previousX - n.radius) continue;
    G.obstacles.splice(i, 1);
    G.collectScore += CLEAR_SCORE;
    inkBurst(ob.x - G.scrollX + ob.w / 2, Math.min(ob.y + ob.h / 2, n.y), 18, 1.1);
  }

  if (n.age >= n.duration) G.ninjutsu = null;
}
