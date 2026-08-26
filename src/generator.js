import { G } from './state.js';
import {
  JUMP_V, GRAV, PX_PER_M, REACT_T, DASH_JUMP_SHIFT_MAX, SAFE_EVENT_PX, COIN_LOW, COIN_HIGH,
  COIN_GAP, COIN_R, SCROLL_R, SHIELD_R,
  COIN_OB_MARGIN_X, COIN_OB_MARGIN_TOP, COIN_OB_MARGIN_BOT,
  GROUND, SPAWN_EXTRA, CLEAN_MARGIN, COLLECT_SWEEP, COIN_MAX_SPAN, W,
  NINJA_W, NINJA_H,
  DMG_NINJA, DMG_PILLAR, DMG_SPIKE, DMG_DART,
  DART_W, DART_H, DART_SPEED, DART_LOW_LIFT, DART_HIGH_LIFT,
  DART_WAVE_MIN, DART_WAVE_MAX, DART_GAP_T_MIN, DART_GAP_T_MAX,
  DART_FIRST_LEAD, DART_PIT_LAND_GAP, DART_WAVE_TAIL_GAP,
  DART_PATTERN_MIX, DART_PATTERN_MIX_M, DART_PATTERN_HARD_M,
} from './constants.js';
import { segAt, segTypeAt } from './terrain.js';
import { speedAt } from './physics.js';
import { rand, rint } from './utils.js';

// 用一组预先编排的区段序列轮换；每个路段只放一种障碍家族，再给对应奖励。
// 金币一律以当前地面高度为基准生成，并通过可达性约束（跳跃高度/间距/障碍间距）检查。
const EVENT_TPL = [
  'coins_flat',
  'jump1', 'reward_arc',
  'jump1', 'reward_arc',
  'jump2', 'reward_arc',

  'coins_flat',
  'slide', 'reward_low',
  'slide', 'reward_low',
  'slide', 'reward_low',

  'coins_flat',
  'ninja', 'reward_dash',
  'dart_wave',        // 飞镖潮独占区段：整波一次生成，高低轨随机混合，潮前潮后有平静段
  'coins_flat',
  'ninja', 'reward_dash',
  'dart_wave',
  'coins_flat',

  'pillar', 'reward_arc',
  'pillar', 'reward_arc',
];

// 飞镖波形：给出第 i 枚（共 n 枚）是否高轨。顺序对应 DART_PATTERN_MIX 的难度阶梯。
const DART_PATTERNS = {
  hop: () => false,            // 全低轨 → 只跳
  slide: () => true,           // 全高轨 → 只滑铲
  alt: (i) => i % 2 === 1,     // 高低交替 → 跳滑跳滑
  lead: (i, n) => i === n - 1, // 末枚孤高 → 前跳后收尾滑
};

export function waveHigh(pattern, i, n) { return DART_PATTERNS[pattern](i, n); }

// 按行进米数选波形（教学锯齿）：先纯波训练单一躲法，再混入交替与收尾加强。
export function pickDartPattern(m) {
  if (m < DART_PATTERN_MIX_M) return Math.random() < 0.5 ? 'hop' : 'slide';
  if (m < DART_PATTERN_HARD_M) return DART_PATTERN_MIX[rint(0, 2)];
  return DART_PATTERN_MIX[rint(0, 3)];
}

// 障碍规格表：尺寸、地面偏移与碰撞伤害。垂板从天花板垂下，底部留出滑铲空隙（实体墙不掉血）
const OBSTACLES = {
  spike: { w: 18, h: 72, yOff: 72, dmg: DMG_SPIKE },
  pillar: { w: 46, h: 80, yOff: 80, dmg: DMG_PILLAR },
  beam: { wMin: 30, wMax: 50, gap: 52 },   // 垂板：窄木板从顶部垂下，底部离地 gap 供滑铲穿过
};

function hazardClearanceAt(x) {
  const airT = 2 * JUMP_V / GRAV;           // 滞空时间
  const pace = speedAt(x / PX_PER_M);
  return Math.max(pace * (airT + REACT_T) * 0.9, pace * airT + 110);
}

function pickGap() {
  // 生成节奏只取基础曲线，不受滑铲和滑铲起跳的瞬时加速影响
  return hazardClearanceAt(G.scrollX) + rand(30, 220);
}

// —— 金币可达性（统一入口）：
//   1) 只能落在非深坑段；
//   2) 离地高度 [COIN_LOW, COIN_HIGH]（单跳必可触达，恒不穿地）；
//   3) 不在任何障碍碰撞范围内；障碍顶上方放行（过山弧线）；
//   4) 生成位置远离屏幕/地形边界，杜绝半截金币。
function collectibleConflictsWithObstacle(cx, cy, ob) {
  return cx > ob.x - COIN_OB_MARGIN_X && cx < ob.x + ob.w + COIN_OB_MARGIN_X &&
    cy > ob.y - COIN_OB_MARGIN_TOP && cy < ob.y + ob.h + COIN_OB_MARGIN_BOT;
}

function addObstacle(ob) {
  G.obstacles.push(ob);
  G.collectibles = G.collectibles.filter((c) => !collectibleConflictsWithObstacle(c.x, c.y, ob));
}

function pushCoin(cx, cy) {
  if (segTypeAt(cx) === 'pit') return;
  const lift = GROUND - cy;
  if (lift < COIN_LOW || lift > COIN_HIGH) return;
  if (G.obstacles.some((ob) => collectibleConflictsWithObstacle(cx, cy, ob))) return;
  G.collectibles.push({ x: cx, y: cy, type: 'coin', r: COIN_R, taken: false });
}

function pushShield(cx) {
  const cy = GROUND - 112;
  if (segTypeAt(cx) === 'pit') return;
  if (G.obstacles.some((ob) => collectibleConflictsWithObstacle(cx, cy, ob))) return;
  G.collectibles.push({ x: cx, y: cy, type: 'shield', r: SHIELD_R, taken: false });
}

function addRewardPickup(x) {
  if (G.gameTime > 14 && Math.random() < 0.22) {
    G.collectibles.push({ x: x + rand(40, 120), y: GROUND - rint(150, 190), type: 'scroll', r: SCROLL_R, taken: false });
  }
  if (G.gameTime > 8 && Math.random() < 0.12) pushShield(x + rand(100, 180));
}

// 金币弧线：围绕跳跃轨迹的引导线，一次跳程内连续拾取
function arcCoins(x, peakH, span) {
  span = span || 250;
  const n = Math.max(5, Math.round(span / COIN_GAP));
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    pushCoin(x + t * span, GROUND - peakH * Math.sin(Math.PI * t));
  }
}
function coinLine(x, n, lift) {
  for (let i = 0; i < n; i++) pushCoin(x + i * COIN_GAP, GROUND - lift);
}
function coinsLow(x) { coinLine(x, rint(3, 5), COIN_LOW + 10); }

export function makeEvent(x) {
  if (segTypeAt(x) === 'pit') { G.lastEventKind = 'pit'; return; }   // 深坑：纯跳跃区，不放障碍/金币
  const gy = GROUND;
  // 障碍前方和坑尾恢复区必须是平地，避免跨坑落地立刻撞上障碍。
  const flatFrom = (x0, len) => {
    const clearance = hazardClearanceAt(x0) + DASH_JUMP_SHIFT_MAX;
    const start = x0 - clearance;
    const end = x0 + len;
    return !G.terrain.some((seg) => seg.type === 'pit' && seg.start < end && seg.end > start);
  };

  // 开局安全区：前 10 米只铺金币引导，之后严格进入危险/奖励交替。
  if (x < SAFE_EVENT_PX) { coinLine(x, rint(6, 10), COIN_LOW + 10); G.lastEventKind = 'coin'; return; }

  const tpl = EVENT_TPL[G.tplIdx % EVENT_TPL.length];
  G.tplIdx++;

  switch (tpl) {
    case 'jump1': {   // 单个地面障碍 + 高跳引导弧线
      const S = OBSTACLES.spike;
      if (flatFrom(x, 320)) {
        addObstacle({ kind: 'spike', x, y: gy - S.yOff, w: S.w, h: S.h, dmg: S.dmg });
      } else coinsLow(x);
      break;
    }
    case 'jump2': {   // 双柱（连续，可跳）
      const S = OBSTACLES.spike;
      if (flatFrom(x, 330) && flatFrom(x + 150, 60)) {
        addObstacle({ kind: 'spike', x, y: gy - S.yOff, w: S.w, h: S.h, dmg: S.dmg });
        addObstacle({ kind: 'spike', x: x + 150, y: gy - S.yOff, w: S.w, h: S.h, dmg: S.dmg });
      } else coinsLow(x);
      break;
    }
    case 'pillar': {  // 石柱：跳跃越过
      const P = OBSTACLES.pillar;
      if (flatFrom(x, 300)) {
        addObstacle({ kind: 'pillar', x, y: gy - P.yOff, w: P.w, h: P.h, dmg: P.dmg });
      } else coinsLow(x);
      break;
    }
    case 'slide': {   // 垂板：从天花板垂下，底部留空隙，滑铲通过
      const B = OBSTACLES.beam;
      const bw = rint(B.wMin, B.wMax);
      if (flatFrom(x, bw + 60)) {
        addObstacle({ kind: 'beam', x, y: 0, w: bw, h: gy - B.gap });
      } else coinsLow(x);
      break;
    }
    case 'ninja': {   // 剑忍：贴地近战，碰到砍一刀扣 DMG_NINJA（最大伤害），跳跃越过
      if (flatFrom(x, 260)) {
        addObstacle({ kind: 'ninja', x, y: gy - NINJA_H, w: NINJA_W, h: NINJA_H, dmg: DMG_NINJA });
      } else coinsLow(x);
      break;
    }
    case 'dart_wave': {   // 飞镖潮：整波一次生成，迎面飞来的动态障碍
      // 枚间距按"时间窗 × 接近速度"在生成时冻结成像素距离：节奏稳定不随速度漂移
      const pace = speedAt(x / PX_PER_M);
      const pattern = pickDartPattern(x / PX_PER_M);   // 整波一个波形语义（教学锯齿选波）
      const step = (px, gapT) => px + (pace + DART_SPEED) * gapT;
      const count = rint(DART_WAVE_MIN, DART_WAVE_MAX);
      let cursor = x + DART_FIRST_LEAD;   // 首枚留足入屏预警距离
      const wave = [];
      for (let i = 0; i < count; i++) {
        // 深坑避让：坑内低轨逼跳会和坑跳叠加成不公平难题，整体推到坑尾后的平地再落
        const seg = segAt(cursor);
        if (seg && seg.type === 'pit') cursor = seg.end + DART_PIT_LAND_GAP;
        const high = waveHigh(pattern, i, count);       // 高低轨由波形决定，不再每枚随机
        wave.push({
          kind: 'dart', x: cursor, y: gy - (high ? DART_HIGH_LIFT : DART_LOW_LIFT),
          w: DART_W, h: DART_H, dmg: DMG_DART, high, pattern,
        });
        cursor = step(cursor, rand(DART_GAP_T_MIN, DART_GAP_T_MAX));
      }
      if (wave.length) {
        for (const ob of wave) addObstacle(ob);
        // 波尾隔离：把全局生成游标推到波尾之后，静态障碍不会插进飞镖潮的到达时间窗
        G.nextSpawnX = Math.max(G.nextSpawnX, cursor + DART_WAVE_TAIL_GAP);
      } else coinsLow(x);
      break;
    }
    case 'reward_arc': {
      arcCoins(x, rint(102, 132), 260);
      addRewardPickup(x);
      break;
    }
    case 'reward_low':
      coinLine(x, 6, COIN_LOW + 16);
      addRewardPickup(x);
      break;
    case 'reward_dash':
      coinLine(x, 7, COIN_LOW + 6);
      addRewardPickup(x);
      break;
    case 'coins_flat':
      coinLine(x, rint(6, 9), COIN_LOW + 12);
      break;
    default:
      // 模板枚举新增而未配 case 时快速暴露，避免静默吞掉事件
      throw new Error('未知事件模板: ' + tpl);
  }

  G.lastEventKind = tpl;
}

export function spawnLoop() {
  const camX = G.scrollX;
  while (G.nextSpawnX < camX + W + SPAWN_EXTRA) {
    makeEvent(G.nextSpawnX);
    const calm = G.lastEventKind.startsWith('reward') || G.lastEventKind === 'coins_flat' || G.lastEventKind === 'coin';
    G.nextSpawnX += pickGap() + (calm ? 0 : 60);
  }
  // 清理出屏：右界放宽一个金币事件跨度，避免刚生成的带型金币被误清
  G.obstacles = G.obstacles.filter((o) => o.x + o.w > camX - CLEAN_MARGIN);
  G.collectibles = G.collectibles.filter((c) => c.x + COLLECT_SWEEP > camX - CLEAN_MARGIN && c.x - COLLECT_SWEEP < camX + W + CLEAN_MARGIN + COIN_MAX_SPAN);
}
