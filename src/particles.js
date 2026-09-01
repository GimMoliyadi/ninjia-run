import { G, ctx } from './state.js';
import { rand } from './utils.js';
import { splats, splatsReady } from './assets.js';

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

// 墨渍爆散：在指定点叠加若干张 Kenney 墨渍（随机旋转/缩放/透明度），
// 形成"泼墨四溅"的一次性效果。素材未就绪时降级为普通墨点，保证任何时刻都能播。
export function splatBurst(x, y, count, alpha = 1, sizeScale = 1) {
  const n = count || 3;
  for (let i = 0; i < n; i++) {
    if (splatsReady() && splats.length) {
      G.particles.push({
        kind: 'splat',          // 标记为墨渍粒子，绘制走图片分支
        x, y,
        vx: rand(-60, 60),      // 轻微漂移，模拟墨渍飞溅
        vy: rand(-40, 20),
        g: 60,
        life: rand(0.4, 0.8), maxLife: 0.8,
        img: splats[Math.floor(Math.random() * splats.length)],
        size: rand(34, 72) * sizeScale,   // 墨渍显示尺寸（原图 256 太大，缩到几十像素）
        rot: Math.random() * Math.PI * 2, // 随机朝向，让多张叠起来不呆板
        spin: 0,
      });
    } else {
      // 降级：素材没加载完时先铺一层普通墨点，视觉不至于空缺
      burst(x, y, 6, { c: '40,40,46', sp: 160, up: 40, g: 500, s: [2, 5], l: [0.3, 0.7] });
    }
  }
}

export function drawParticles() {
  for (const p of G.particles) {
    const alpha = Math.max(0, p.life / p.maxLife);
    ctx.save();
    if (p.kind === 'splat' && p.img) {
      // 墨渍图片：半透明 + 随机旋转，叠出泼墨感
      ctx.globalAlpha = alpha * 0.8;
      ctx.translate(p.x, p.y);
      ctx.rotate(p.rot);
      ctx.drawImage(p.img, -p.size / 2, -p.size / 2, p.size, p.size);
      ctx.restore();
      continue;
    }
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
