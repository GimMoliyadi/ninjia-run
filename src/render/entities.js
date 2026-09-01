import { G, ctx } from '../state.js';
import {
  INK, RED, GOLD, PW, PLAYER_X, SHIELD_WARN_T,
  COLLECT_RADIUS_EXTRA, DART_APPROACH_RANGE,
  START_SPEED, RUN_CYCLE_FPS, RUN_STRIDE_MIN, RUN_STRIDE_MAX, RUN_LEAN_RAD,
  ROCK_WARN_T, ROCK_W, ROCK_H,
  INK_WALL_H, INK_WALL_ARCH,
  GROUND,
} from '../constants.js';
import { FRAMES, getImg } from '../sprites.js';

const RUN_POSES = [
  { leg: -1, arm: 1, bob: 0 },
  { leg: -0.45, arm: 0.45, bob: 0.5 },
  { leg: 0.35, arm: -0.35, bob: 1 },
  { leg: 1, arm: -1, bob: 0 },
  { leg: 0.35, arm: -0.35, bob: 1 },
  { leg: -0.45, arm: 0.45, bob: 0.5 },
];

// 步幅幅度随场景速度缩放（频率固定）：极速时腿跨得更开、抬膝更高，但摆动节奏不变
function strideScale() {
  return Math.min(RUN_STRIDE_MAX, Math.max(RUN_STRIDE_MIN, G.speed / START_SPEED));
}

function runPoseAt(frameT) {
  const progress = frameT * RUN_CYCLE_FPS;
  const from = RUN_POSES[Math.floor(progress) % RUN_POSES.length];
  const to = RUN_POSES[(Math.floor(progress) + 1) % RUN_POSES.length];
  const t = progress - Math.floor(progress);
  return {
    leg: from.leg + (to.leg - from.leg) * t,
    arm: from.arm + (to.arm - from.arm) * t,
    bob: from.bob + (to.bob - from.bob) * t,
  };
}

function limb(x1, y1, x2, y2, x3, y3) {
  ctx.beginPath();
  ctx.moveTo(x1, y1);
  ctx.lineTo(x2, y2);
  ctx.lineTo(x3, y3);
  ctx.stroke();
}

function head(x, y) {
  ctx.beginPath();
  ctx.arc(x, y, 8, 0, Math.PI * 2);
  ctx.stroke();
}

function drawRunPose(frameT) {
  const pose = runPoseAt(frameT);
  const leg = pose.leg;
  const arm = pose.arm;
  // 冲刺姿态：高抬膝、后蹬伸直、屈肘大幅摆臂；步幅随速度放大
  const s = strideScale();
  const frontKneeY = -15 - Math.max(0, leg) * 16 * s;
  const rearKneeY = -15 - Math.max(0, -leg) * 16 * s;
  ctx.strokeStyle = INK;
  ctx.lineWidth = 3.5;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  head(0, -53);
  limb(0, -45, 0, -35, 0, -26);
  limb(-2, -27, 4 + leg * 14 * s, frontKneeY, 8 + leg * 30 * s, -2);
  limb(2, -27, -4 - leg * 14 * s, rearKneeY, -8 - leg * 30 * s, -2);
  // 屈肘摆臂：肘部贴身前后摆，前臂恒向上折叠，拳到胸高
  const elbowX = 12 * s, fistX = 6 * s, fistY = -10 * s;
  limb(-2, -42, -2 + arm * elbowX, -34, -2 + arm * elbowX + fistX, -34 + fistY);
  limb(2, -42, 2 - arm * elbowX, -34, 2 - arm * elbowX + fistX, -34 + fistY);
  ctx.strokeStyle = RED;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.moveTo(-5, -47);
  ctx.quadraticCurveTo(-15 - leg * 4, -49, -24 - leg * 5, -42);
  ctx.stroke();
}

function drawJumpPose() {
  ctx.strokeStyle = INK;
  ctx.lineWidth = 3.5;
  ctx.lineCap = 'round';
  head(7, -52);
  limb(4, -44, 5, -34, 2, -25);
  limb(2, -25, 12, -17, 24, -18);
  limb(2, -25, -4, -15, 3, -10);
  limb(4, -40, 14, -49, 23, -45);
  limb(4, -40, -4, -47, -11, -42);
  ctx.strokeStyle = RED;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.moveTo(-1, -46);
  ctx.quadraticCurveTo(-17, -50, -26, -41);
  ctx.stroke();
}

function drawFlipPose() {
  ctx.strokeStyle = INK;
  ctx.lineWidth = 3.5;
  ctx.lineCap = 'round';
  head(10, -35);
  limb(4, -28, -4, -25, -7, -18);
  limb(-7, -18, 3, -12, 16, -20);
  limb(-7, -18, 1, -8, 14, -14);
  limb(3, -28, 12, -27, 17, -22);
  limb(2, -29, 9, -24, 15, -21);
  ctx.strokeStyle = RED;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.moveTo(3, -30);
  ctx.quadraticCurveTo(-13, -36, -23, -27);
  ctx.stroke();
}

function drawSlidePose() {
  ctx.strokeStyle = INK;
  ctx.lineWidth = 3.5;
  ctx.lineCap = 'round';
  head(13, -35);
  limb(7, -29, -2, -20, -10, -12);
  limb(-10, -12, -1, -6, 11, -3);
  limb(-10, -12, -18, -5, -29, -2);
  limb(7, -28, 18, -18, 29, -4);
  limb(5, -28, -4, -23, -12, -20);
  ctx.strokeStyle = RED;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.moveTo(5, -29);
  ctx.quadraticCurveTo(-13, -35, -26, -27);
  ctx.stroke();
}

function drawSpeedTrail(x, y) {
  const p = G.player;
  if (!p.sliding && p.dashBoostT <= 0) return;
  const strength = p.sliding ? 1 : Math.min(1, p.dashBoostT / 0.86);
  ctx.save();
  ctx.strokeStyle = INK;
  ctx.lineCap = 'round';
  for (let i = 0; i < 3; i++) {
    const offset = 8 + i * 8 + ((Math.floor(p.runT * 20) + i * 5) % 7);
    ctx.globalAlpha = strength * (0.32 - i * 0.07);
    ctx.lineWidth = 2 - i * 0.3;
    ctx.beginPath();
    ctx.moveTo(x - 10 - i * 3, y - 4 - i * 3);
    ctx.quadraticCurveTo(x - offset * 0.55, y - 4 - i * 3, x - offset - i * 7, y - 3 - i * 3);
    ctx.stroke();
  }
  ctx.restore();
}

function drawSpriteFrame(frame, x, y) {
  const img = getImg();
  if (!img.complete || img.naturalWidth === 0) return false;
  ctx.drawImage(img, frame.x, frame.y, frame.w, frame.h, x - 64, y - 128, 128, 128);
  return true;
}

function drawPlayerNinja(x, y) {
  const p = G.player;
  drawSpeedTrail(x, y);
  ctx.save();
  if (p.onGround && p.sliding) {
    const frame = FRAMES.slide[Math.floor(p.runT * 12) % FRAMES.slide.length];
    if (drawSpriteFrame(frame, x, y)) {
      ctx.restore();
      return;
    }
    ctx.translate(x, y);
    ctx.rotate(0.06);
    drawSlidePose();
  } else if (!p.onGround) {
    if (p.jumps === 1) {
      const frame = p.vy < 0 ? FRAMES.jump1[0] : FRAMES.jump2[0];
      if (drawSpriteFrame(frame, x, y)) {
        ctx.restore();
        return;
      }
      ctx.translate(x, y);
      ctx.rotate(p.vy < 0 ? -0.1 : 0.08);
      drawJumpPose();
    } else if (p.jumps === 2) {
      ctx.translate(x, y - 26);
      ctx.rotate(Math.min(1, p.jumpT / 0.38) * Math.PI * 4);
      ctx.translate(0, 26);
      drawFlipPose();
    } else {
      ctx.translate(x, y);
      ctx.rotate(p.vy < 0 ? -0.1 : 0.08);
      drawJumpPose();
    }
  } else {
    const frame = FRAMES.run[Math.floor(p.runT * 12) % FRAMES.run.length];
    if (!drawSpriteFrame(frame, x, y)) {
      const pose = runPoseAt(p.runT);
      ctx.translate(x, y - pose.bob);
      ctx.rotate(RUN_LEAN_RAD);   // 冲刺躯干前倾，绕脚底旋转保持脚贴地
      drawRunPose(p.runT);
    }
  }
  ctx.restore();
}

// 导出：分身/预览等复用同一套忍者姿态绘制（跟随 G.player 状态）
export function drawNinjaAvatar(x, y) { drawPlayerNinja(x, y); }

export function drawPlayer() {
  const p = G.player;
  const x = p.x + G.dashShift, y = p.y;

  // 忍术光环
  if (p.invuln > 0) {
    ctx.save();
    ctx.strokeStyle = GOLD;
    ctx.globalAlpha = 0.5 + 0.4 * Math.sin(p.runT * 20);
    for (let i = 0; i < 3; i++) {
      ctx.lineWidth = 3 - i;
      ctx.beginPath();
      ctx.arc(x, y - 30, 34 + i * 8 + Math.sin(p.runT * 8) * 4, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.restore();
  }

  drawPlayerNinja(x, y);

  if (p.shieldT > 0) {
    const warning = p.shieldT <= SHIELD_WARN_T;
    const flashRate = p.shieldT <= 1 ? 20 : 9;
    const visible = !warning || Math.sin(p.runT * flashRate) > -0.15;
    if (visible) {
      ctx.save();
      ctx.globalAlpha = warning ? 0.62 : 0.3;
      ctx.strokeStyle = '#4892a4';
      ctx.lineWidth = 2.5;
      for (let i = 0; i < 2; i++) {
        ctx.beginPath();
        ctx.arc(x, y - 31, 31 + i * 6 + Math.sin(p.runT * 7 + i) * 2, 0, Math.PI * 2);
        ctx.stroke();
      }
      ctx.restore();
    }
  }
}

// ================= 障碍 =================
// 贴地红痕：标识障碍碰撞底部
function groundMark(x, gy, w) {
  ctx.globalAlpha = 0.5;
  ctx.fillStyle = RED;
  ctx.fillRect(x - 3, gy - 3, w + 6, 3);
  ctx.globalAlpha = 1;
}

function drawSpike(ob, x) {
  const gy = ob.y + ob.h;   // 底部=主地面，统一贴地
  // 两根墨竹尖交叉
  ctx.strokeStyle = INK;
  ctx.lineWidth = 5;
  ctx.beginPath();
  ctx.moveTo(x, gy);
  ctx.quadraticCurveTo(x - 4, gy - 36, x - 10, gy - ob.h - 4);
  ctx.stroke();
  ctx.lineWidth = 4;
  ctx.beginPath();
  ctx.moveTo(x + ob.w, gy);
  ctx.quadraticCurveTo(x + ob.w + 5, gy - 38, x + ob.w + 12, gy - ob.h - 6);
  ctx.stroke();
  // 横竹节
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(x - 4, gy - 30);
  ctx.lineTo(x + ob.w + 5, gy - 30);
  ctx.stroke();
  // 红色警示尖带（强调"危险"，与背景区分）
  ctx.strokeStyle = RED;
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(x + ob.w / 2 - 5, gy - ob.h - 10);
  ctx.lineTo(x + ob.w / 2 + 5, gy - ob.h - 10);
  ctx.stroke();
  groundMark(x, gy, ob.w);
  // 淡影
  ctx.globalAlpha = 0.15;
  ctx.fillStyle = INK;
  ctx.beginPath();
  ctx.moveTo(x - 4, gy);
  ctx.lineTo(x + ob.w + 4, gy);
  ctx.lineTo(x + ob.w - 10, gy - ob.h);
  ctx.closePath();
  ctx.fill();
  ctx.globalAlpha = 1;
}

function drawPillar(ob, x) {
  const gy = ob.y + ob.h;
  // 石柱主体（更深、更醒目）
  ctx.fillStyle = 'rgba(36,36,43,0.96)';
  ctx.beginPath();
  ctx.moveTo(x + 4, gy);
  ctx.lineTo(x, gy - ob.h);
  ctx.lineTo(x + ob.w, gy - ob.h);
  ctx.lineTo(x + ob.w - 4, gy);
  ctx.closePath();
  ctx.fill();
  // 顶横石（上缘压红警示条）
  ctx.fillStyle = '#20202a';
  ctx.fillRect(x - 5, gy - ob.h - 9, ob.w + 10, 9);
  ctx.fillStyle = RED;
  ctx.fillRect(x - 5, gy - ob.h - 9, ob.w + 10, 4);
  // 裂纹
  ctx.strokeStyle = 'rgba(20,20,24,0.85)';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(x + ob.w * 0.3, gy);
  ctx.lineTo(x + ob.w * 0.45, gy - ob.h * 0.4);
  ctx.lineTo(x + ob.w * 0.3, gy - ob.h * 0.7);
  ctx.stroke();
  groundMark(x, gy, ob.w);
}

function drawBeam(ob, x, y) {
  // 垂板：从天花板垂下的深色木板，底部离地留出滑铲空隙
  ctx.fillStyle = 'rgba(30,30,36,0.96)';
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.lineTo(x + ob.w, y);
  ctx.lineTo(x + ob.w, y + ob.h);
  ctx.lineTo(x, y + ob.h);
  ctx.closePath();
  ctx.fill();
  // 竖向墨纹
  ctx.strokeStyle = 'rgba(20,20,24,0.7)';
  ctx.lineWidth = 2;
  for (let i = 1; i < 4; i++) {
    const lx = x + ob.w * i / 4;
    ctx.beginPath();
    ctx.moveTo(lx, y + 6);
    ctx.lineTo(lx, y + ob.h - 6);
    ctx.stroke();
  }
  // 顶部挂梁：贴天花板的一段横枋
  ctx.fillStyle = INK;
  ctx.fillRect(x - 6, y - 6, ob.w + 12, 8);
  // 底部红色警示条：标出空隙上沿，提示下方可滑铲通过
  ctx.fillStyle = RED;
  ctx.fillRect(x - 6, y + ob.h - 4, ob.w + 12, 4);
  // 空隙标识红痕
  ctx.globalAlpha = 0.5;
  ctx.fillStyle = RED;
  ctx.fillRect(x - 3, y + ob.h + 4, ob.w + 6, 3);
  ctx.globalAlpha = 1;
}

export function drawObstacles() {
  for (const ob of G.obstacles) {
    const x = ob.x - G.scrollX, y = ob.y;
    ctx.save();
    if (ob.kind === 'spike') drawSpike(ob, x);
    else if (ob.kind === 'pillar') drawPillar(ob, x);
    else if (ob.kind === 'beam') drawBeam(ob, x, y);
    else if (ob.kind === 'ninja') drawNinja(ob, x);
    else if (ob.kind === 'dart') drawDart(ob, x);
    else if (ob.kind === 'boulder') drawBoulder(ob, x);
    else if (ob.kind === 'rock') drawRock(ob, x);
    else if (ob.kind === 'inkwall') drawInkWall(ob, x);
    // 调试：显示障碍碰撞盒（F7 切换）
    if (G.debugMode) {
      ctx.strokeStyle = 'rgba(200,40,40,0.9)';
      ctx.lineWidth = 1;
      ctx.strokeRect(x, y, ob.w, ob.h);
    }
    ctx.restore();
  }
}

// 滚石：贴地迎面滚来的大圆石。墨晕团身 + 两道旋转墨纹表达滚动，
// 随滚动带起贴地尘粒，迎面靠近时是明确的"跳过去"信号。
function drawBoulder(ob, x) {
  const gy = ob.y + ob.h;
  const r = ob.w / 2 + 2;
  const cx = x + ob.w / 2, cy = gy - r;
  const rot = G.gameTime * 6;
  ctx.save();
  // 淡影
  ctx.globalAlpha = 0.15;
  ctx.fillStyle = INK;
  ctx.beginPath();
  ctx.ellipse(cx, gy - 1, r * 0.92, r * 0.32, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.globalAlpha = 1;
  // 团身（略压扁的圆，带不规则边缘模拟石头）
  ctx.fillStyle = 'rgba(36,36,43,0.96)';
  ctx.beginPath();
  ctx.moveTo(cx - r, cy);
  ctx.quadraticCurveTo(cx - r * 0.9, cy - r * 1.15, cx, cy - r * 1.05);
  ctx.quadraticCurveTo(cx + r * 0.95, cy - r * 1.15, cx + r, cy);
  ctx.quadraticCurveTo(cx + r * 0.9, cy + r * 0.92, cx, cy + r);
  ctx.quadraticCurveTo(cx - r * 0.92, cy + r * 0.95, cx - r, cy);
  ctx.closePath();
  ctx.fill();
  // 旋转墨纹（表现滚动）
  ctx.strokeStyle = 'rgba(255,255,255,0.28)';
  ctx.lineWidth = 3;
  for (let i = 0; i < 2; i++) {
    const a0 = rot + i * Math.PI;
    ctx.beginPath();
    ctx.arc(cx, cy, r * 0.72, a0, a0 + 1.6);
    ctx.stroke();
  }
  ctx.restore();
  // 贴地滚动尘粒
  ctx.save();
  ctx.globalAlpha = 0.3;
  ctx.fillStyle = INK;
  for (let i = 0; i < 3; i++) {
    const dx = -((G.gameTime * 90 + i * 23) % 40);
    const dy = -((G.gameTime * 130 + i * 31) % 26);
    ctx.beginPath();
    ctx.arc(cx - r + dx * 0.4, gy - 2 - dy * 0.3, 2.5 - i * 0.5, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
  groundMark(x, gy, ob.w);
}

// 落石：预警期（warnT>0）在地面画扩散阴影圈 + 红色警示环，随时间扩大强度；
// 预警结束后画下落的墨晕团身岩石，落地后与 boulder 相似的墨纹旋转效果。
function drawRock(ob, x) {
  const gy = ob.landY + ob.h;  // 落点底部 = 地面
  if (ob.warnT > 0) {
    // 预警阶段：阴影圈从地面扩散，红色警示环同时闪烁 > 提示玩家"这里要落石"
    const pul = 1 - ob.warnT / ROCK_WARN_T;        // 预警进度 0→1
    const cx = x + ob.w / 2, r = (ob.w / 2 + 6) * (1 + pul * 0.4);
    ctx.save();
    // 墨色阴影随进度扩大
    ctx.globalAlpha = 0.16 + pul * 0.22;
    ctx.fillStyle = INK;
    ctx.beginPath();
    ctx.ellipse(cx, gy, r, r * 0.34, 0, 0, Math.PI * 2);
    ctx.fill();
    // 红色警示环（边缘闪烁）
    ctx.strokeStyle = RED;
    ctx.globalAlpha = 0.4 + pul * 0.5;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.ellipse(cx, gy, r + 5, r * 0.34 + 3, 0, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
    groundMark(x, gy, ob.w);
    return;
  }
  // 落地后：墨晕团身圆石 + 旋转白色墨纹，与 boulder 视觉一致
  const r = ob.w / 2 + 2, cx = x + ob.w / 2, cy = ob.y + r;
  const rot = G.gameTime * 6;
  ctx.save();
  ctx.fillStyle = 'rgba(36,36,43,0.96)';
  ctx.beginPath();
  ctx.moveTo(cx - r, cy);
  ctx.quadraticCurveTo(cx - r * 0.9, cy - r * 1.15, cx, cy - r * 1.05);
  ctx.quadraticCurveTo(cx + r * 0.95, cy - r * 1.15, cx + r, cy);
  ctx.quadraticCurveTo(cx + r * 0.9, cy + r * 0.92, cx, cy + r);
  ctx.quadraticCurveTo(cx - r * 0.92, cy + r * 0.95, cx - r, cy);
  ctx.closePath();
  ctx.fill();
  ctx.strokeStyle = 'rgba(255,255,255,0.28)';
  ctx.lineWidth = 3;
  for (let i = 0; i < 2; i++) {
    const a0 = rot + i * Math.PI;
    ctx.beginPath();
    ctx.arc(cx, cy, r * 0.72, a0, a0 + 1.6);
    ctx.stroke();
  }
  ctx.restore();
  groundMark(x, gy, ob.w);
}

// 墨墙：从地面立起的墨色实墙，底部留拱门空隙供滑铲钻过。
// 碰撞盒只覆盖上段（实墙），拱门区域无碰撞；
// 渲染画到地面（含拱门视觉），让玩家看到拱门就知道可滑铲通过。
function drawInkWall(ob, x) {
  const gy = GROUND;  // 地面 y
  const topY = gy - INK_WALL_H;          // 墙顶（离地 120px）
  const archY = gy - INK_WALL_ARCH;       // 拱门顶部（离地 52px，滑铲通过的上沿）
  ctx.save();
  // 上段实墙：从顶部到拱门顶
  ctx.fillStyle = 'rgba(36,36,43,0.96)';
  ctx.fillRect(x, topY, ob.w, INK_WALL_H - INK_WALL_ARCH);
  // 两侧墙脚柱子（拱门两边支撑）
  const legW = 10;
  ctx.fillRect(x + 2, archY, legW, INK_WALL_ARCH);
  ctx.fillRect(x + ob.w - legW - 2, archY, legW, INK_WALL_ARCH);
  // 波浪墨纹装饰：墙身上的白色波纹
  ctx.strokeStyle = 'rgba(255,255,255,0.18)';
  ctx.lineWidth = 2;
  for (let i = 0; i < 2; i++) {
    const wx = x + ob.w * (0.35 + i * 0.3);
    ctx.beginPath();
    ctx.moveTo(wx, topY + 8);
    ctx.quadraticCurveTo(wx + 4, topY + (INK_WALL_H - INK_WALL_ARCH) / 2, wx - 2, archY - 6);
    ctx.stroke();
  }
  // 拱门空隙上沿红色警示条：提示玩家"这里可滑铲"
  ctx.fillStyle = RED;
  ctx.fillRect(x + 2, archY, ob.w - 4, 4);
  // 空隙标识红痕（地面标识）
  ctx.globalAlpha = 0.5;
  ctx.fillStyle = RED;
  ctx.fillRect(x - 3, archY + 8, ob.w + 6, 3);
  ctx.globalAlpha = 1;
  ctx.restore();
  groundMark(x, gy, ob.w);
}

// ================= 活体障碍 =================
// 持刀忍者：贴地墨线人形，持刀前伸（刀刃朝左对玩家），刀身呼吸式反光闪动作危险提示
function drawNinja(ob, x) {
  const gy = ob.y + ob.h;
  const sway = Math.sin(G.gameTime * 8 + ob.x) * 2;               // 轻微呼吸起伏
  const bladeFlash = Math.sin(G.gameTime * 6 + ob.x) > 0.4;       // 刀刃反光闪动
  ctx.save();
  ctx.strokeStyle = INK;
  ctx.lineWidth = 3.5;
  ctx.lineCap = 'round';
  head(x + 6, gy - 46 + sway);                          // 头
  limb(x + 4, gy - 38 + sway, x + 2, gy - 24, x - 6, gy - 14);   // 躯干
  limb(x - 6, gy - 14, x - 14, gy - 5, x - 18, gy);              // 前腿（面左）
  limb(x + 2, gy - 24, x + 12, gy - 12, x + 14, gy);             // 后腿
  // 持刀前臂（前伸朝左）
  limb(x + 2, gy - 26 + sway, x - 12, gy - 30 + sway, x - 20, gy - 26 + sway);
  // 刀：刀刃向左，寒光闪动
  ctx.strokeStyle = bladeFlash ? '#e8e2d0' : INK;
  ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.moveTo(x - 20, gy - 26 + sway);
  ctx.lineTo(x - 40, gy - 18 + sway);
  ctx.stroke();
  ctx.strokeStyle = RED;
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(x - 20, gy - 26 + sway);
  ctx.lineTo(x - 24, gy - 30 + sway);
  ctx.stroke();
  ctx.restore();
  groundMark(x, gy, ob.w);
}

// 四刃手里剑：纯绘制一个刃体（四刃绕质心），当前 transform 由调用方摆好。
function blade(r) {
  ctx.fillStyle = INK;
  for (let i = 0; i < 4; i++) {
    ctx.save();
    ctx.rotate(i * Math.PI / 2);
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(r - 3, -2);
    ctx.lineTo(r, 0);
    ctx.lineTo(r - 3, 2);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }
}

// 飞镖：水墨四刃手里剑绕质心高速自转。入屏带淡墨扩散晕（远淡近实，预读躲法），
// 飞行反方向拖三条刀光残影；自转/晕/拖尾仅表现，不影响碰撞判定。
function drawDart(ob, x) {
  const r = ob.w / 2 + 3; // 刃尖略超出碰撞盒：刀刃感醒目，判定盒仍偏仁慈
  const cx = x + r, cy = ob.y + ob.h / 2;
  const angle = G.gameTime * 14;

  // 入场墨晕：刚入屏（x 接近右缘 W）时散开，随飞镖前移收敛为实心刃体
  const approach = Math.max(0, (x - PLAYER_X - DART_APPROACH_RANGE) / DART_APPROACH_RANGE);
  if (approach > 0) {
    ctx.save();
    ctx.globalAlpha = approach * 0.35;
    ctx.fillStyle = INK;
    ctx.beginPath();
    ctx.arc(cx, cy, r + approach * 26, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  // 刀光拖尾：屏幕左三个递减透明副本，旋转角滞后，像切开水墨的残影
  for (let i = 3; i >= 1; i--) {
    ctx.save();
    ctx.globalAlpha = 0.26 - i * 0.07;
    ctx.translate(cx - i * 7, cy);
    ctx.rotate(angle - i * 0.35);
    blade(r);
    ctx.restore();
  }

  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate(angle);
  blade(r);
  ctx.fillStyle = RED;
  ctx.beginPath();
  ctx.arc(0, 0, 2.5, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

// ================= 收集 =================
export function drawCollectibles() {
  for (const c of G.collectibles) {
    ctx.save();
    ctx.translate(c.x - G.scrollX, c.y);
    const spin = Math.sin(G.gameTime * 5 + c.x) * 0.3;
    ctx.rotate(spin);
    if (c.type === 'coin') {
      // 金色符咒（菱形）：白色晕边提升对比度
      ctx.fillStyle = 'rgba(255,255,255,0.55)';
      ctx.beginPath();
      ctx.moveTo(0, -16);
      ctx.lineTo(10, 0);
      ctx.lineTo(0, 16);
      ctx.lineTo(-10, 0);
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = GOLD;
      ctx.beginPath();
      ctx.moveTo(0, -13);
      ctx.lineTo(8, 0);
      ctx.lineTo(0, 13);
      ctx.lineTo(-8, 0);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = 'rgba(120,80,20,0.8)';
      ctx.lineWidth = 1.5;
      ctx.stroke();
      // 调试：金币拾取范围
      if (G.debugMode) {
        ctx.strokeStyle = 'rgba(40,200,80,0.7)';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(0, 0, c.r + COLLECT_RADIUS_EXTRA, 0, Math.PI * 2);
        ctx.stroke();
      }
    } else if (c.type === 'shield') {
      ctx.fillStyle = 'rgba(226,246,247,0.78)';
      ctx.beginPath();
      ctx.moveTo(0, -16);
      ctx.lineTo(12, -8);
      ctx.lineTo(9, 10);
      ctx.lineTo(0, 17);
      ctx.lineTo(-9, 10);
      ctx.lineTo(-12, -8);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = '#377d91';
      ctx.lineWidth = 2.5;
      ctx.stroke();
      ctx.strokeStyle = '#377d91';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(0, 0, 5, 0, Math.PI * 2);
      ctx.stroke();
    } else {
      // 红卷轴
      ctx.fillStyle = RED;
      ctx.fillRect(-7, -12, 14, 24);
      ctx.fillStyle = '#f2ecd9';
      ctx.fillRect(-2, -12, 4, 24);
      ctx.strokeStyle = 'rgba(90,30,20,0.7)';
      ctx.lineWidth = 1.5;
      ctx.strokeRect(-7, -12, 14, 24);
    }
    ctx.restore();
  }
}
