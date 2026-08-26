import { G } from './state.js';
import { W } from './constants.js';

export function initDecor() {
  G.bamboos = [];
  for (let x = 40; x < 200000; x += 180 + Math.random() * 220) {
    G.bamboos.push({ x, h: 70 + Math.random() * 90, lean: (Math.random() - 0.5) * 0.25 });
  }
  G.mountains = [];
  for (let i = 0; i < 12; i++) {
    G.mountains.push({
      x: i * 220 + Math.random() * 70,
      w: 220 + Math.random() * 260,
      h: 90 + Math.random() * 120,
      alpha: 0.045 + Math.random() * 0.07,
    });
  }
  G.clouds = [];
  for (let i = 0; i < 7; i++) {
    G.clouds.push({ x: Math.random() * W * 2, y: 40 + Math.random() * 130, s: 0.7 + Math.random() * 0.9, a: 0.02 + Math.random() * 0.05 });
  }
}
