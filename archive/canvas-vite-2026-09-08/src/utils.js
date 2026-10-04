export function rand(a, b) { return a + Math.random() * (b - a); }
export function rint(a, b) { return Math.round(rand(a, b)); }
export function jitter(m) { return (Math.random() - 0.5) * m; }
export function aabb(a, b) {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}
export function circleRect(cx, cy, r, r2) {
  const nx = Math.max(r2.x, Math.min(cx, r2.x + r2.w));
  const ny = Math.max(r2.y, Math.min(cy, r2.y + r2.h));
  const dx = cx - nx, dy = cy - ny;
  return dx * dx + dy * dy < r * r;
}
