import { G, ctx } from './state.js';
import { rand } from './utils.js';

export function burst(x, y, n, o) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2;
    const sp = rand(o.sp * 0.4, o.sp);
    const life = rand(o.l[0], o.l[1]);
    G.particles.push({
      x, y,
      vx: Math.cos(a) * sp,
      vy: Math.sin(a) * sp - o.up * Math.random(),
      g: o.g,
      life, maxLife: life,
      size: rand(o.s[0], o.s[1]),
      c: o.c,
    });
  }
}

export function inkBurst(x, y, n, scale = 1) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2;
    const life = rand(0.28, 0.7);
    G.particles.push({
      x, y,
      vx: Math.cos(a) * rand(80, 260) * scale,
      vy: Math.sin(a) * rand(50, 190) * scale - rand(20, 110) * scale,
      g: 260,
      life, maxLife: life,
      size: rand(2, 6) * scale,
      c: i % 5 === 0 ? '165,58,46' : '40,40,46',
      shape: i % 3 === 0 ? 'stroke' : 'drop',
      rot: a,
      spin: rand(-7, 7),
    });
  }
}

export function updateParticles(dt) {
  for (let i = G.particles.length - 1; i >= 0; i--) {
    const p = G.particles[i];
    p.life -= dt;
    if (p.life <= 0) { G.particles.splice(i, 1); continue; }
    p.vy += p.g * dt;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    if (p.spin) p.rot += p.spin * dt;
  }
}

export function drawParticles() {
  for (const p of G.particles) {
    const alpha = Math.max(0, p.life / p.maxLife);
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.fillStyle = `rgb(${p.c})`;
    if (p.shape === 'stroke') {
      ctx.translate(p.x, p.y);
      ctx.rotate(p.rot);
      ctx.beginPath();
      ctx.ellipse(0, 0, p.size * 2.2, p.size * 0.55, 0, 0, Math.PI * 2);
      ctx.fill();
    } else {
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }
}
