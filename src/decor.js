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

  // 村町灯笼：固定世界坐标，随视差滚动
  G.lamps = [];
  for (let i = 0; i < 12; i++) {
    G.lamps.push({ x: i * 260 + Math.random() * 90 });
  }
  // 冥山枯树
  G.deadTrees = [];
  for (let i = 0; i < 10; i++) {
    G.deadTrees.push({ x: i * 330 + Math.random() * 120, h: 120 + Math.random() * 90, lean: (Math.random() - 0.5) * 0.3, a: 0.16 + Math.random() * 0.1 });
  }
  // 冥山鬼火
  G.ghostFires = [];
  for (let i = 0; i < 12; i++) {
    G.ghostFires.push({ x: i * 240 + Math.random() * 80, h: 70 + Math.random() * 70, ph: Math.random() * Math.PI * 2 });
  }
}
