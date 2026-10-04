import { G } from './state.js';
import {
  JUMP_V, GRAV, PX_PER_M, REACT_T, DASH_JUMP_SHIFT_MAX, COIN_LOW, COIN_HIGH,
  COIN_GAP, COIN_R, SCROLL_R, SHIELD_R,
  COIN_OB_MARGIN_X, COIN_OB_MARGIN_TOP, COIN_OB_MARGIN_BOT,
  GROUND, SPAWN_EXTRA, CLEAN_MARGIN, COLLECT_SWEEP, COIN_MAX_SPAN, W,
  NINJA_W, NINJA_H,
  DMG_NINJA, DMG_PILLAR, DMG_SPIKE, DMG_DART,
  DART_W, DART_H, DART_SPEED, DART_LOW_LIFT, DART_HIGH_LIFT,
  DART_WAVE_MIN, DART_WAVE_MAX, DART_GAP_T_MIN, DART_GAP_T_MAX,
  DART_FIRST_LEAD, DART_PIT_LAND_GAP, DART_WAVE_TAIL_GAP,
  DART_PATTERN_MIX, DART_PATTERN_MIX_M, DART_PATTERN_HARD_M,
  BOULDER_W, BOULDER_H, BOULDER_SPEED,
  ROCK_W, ROCK_H, ROCK_WARN_T, DMG_ROCK,
  INK_WALL_W, INK_WALL_H, INK_WALL_ARCH, DMG_WALL,
  OB_GAP_MIN, SPIKE_SAFE_GAP, SPIKE_ROW_REACT,
} from './constants.js';
import { SPAWN_CONFIG } from './spawn-config.js';
import { segAt, segTypeAt, groundYAt, appendTerrain } from './terrain.js';
import { speedAt } from './physics.js';
import { rand, rint } from './utils.js';

// 精锐 3v3 地图编排：每个路段只放一种障碍家族，再给对应奖励。
// 顺序对应参考图的节奏：低矮工业平台 → 密集机关 → 熔岩长坑与高低轨飞镖。
// 金币一律以当前地面高度为基准生成，并通过可达性约束（跳跃高度/间距/障碍间距）检查。
// （cycle 模式专用：weights 模式下事件改由 spawn-config.js 的权重随机决定）
const EVENT_TPL = [
  'coins_flat',
  'jump1', 'reward_arc',
  'slide', 'reward_low',
  'jump2', 'reward_arc',
  'spike_row', 'reward_arc',

  'coins_flat',
  'pillar', 'reward_arc',
  'slide', 'reward_low',
  'rock', 'reward_arc',

  'coins_flat',
  'ninja', 'reward_dash',
  'dart_wave', 'reward_low',
  'boulder', 'reward_arc',
  'inkwall', 'reward_low',
  'rock', 'reward_arc',

  'coins_flat',
  'jump2', 'reward_arc',
  'dart_wave', 'reward_dash',
  'spike_row', 'reward_arc',
  'ninja', 'reward_dash',
  'boulder', 'reward_arc',
  'inkwall', 'reward_low',
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
export const OBSTACLES = {
  spike: { w: 24, h: 72, yOff: 72, dmg: DMG_SPIKE },      // 加宽到 24px：更醒目，判定更宽容
  pillar: { w: 46, h: 80, yOff: 80, dmg: DMG_PILLAR },
  beam: { wMin: 30, wMax: 50, gap: 52 },   // 垂板：窄木板从顶部垂下，底部离地 gap 供滑铲穿过
};

function hazardClearanceAt(x) {
  const airT = 2 * JUMP_V / GRAV;           // 滞空时间
  const pace = speedAt(x / PX_PER_M);
  // 保守安全间距 = 跳跃飞行距离 + 反应时间窗 + 额外缓冲
  // 乘 1.15 给更多喘息空间，避免高速时太紧逼
  return Math.max(pace * (airT + REACT_T) * 1.15, pace * airT + 160);
}

// 间距检测：新障碍落点 [x, x+len] 不得与既有静态障碍重叠/过近（至少 OB_GAP_MIN 空隙）。
// dart/boulder 是迎面动态障碍（靠 lead+隔离带自排），rock 落地即固定，需纳入。
function obstacleGapOk(x, len) {
  const lo = x - OB_GAP_MIN, hi = x + len + OB_GAP_MIN;
  return !G.obstacles.some((ob) =>
    (ob.kind === 'dart' || ob.kind === 'boulder') ? false :
    ob.x < hi && ob.x + ob.w > lo
  );
}

function pickGap() {
  // 生成节奏 = 速度安全间距（随跑速自动增长）+ 配置的随机浮动区间
  return hazardClearanceAt(G.scrollX) + rand(SPAWN_CONFIG.gapMin, SPAWN_CONFIG.gapMax);
}

// —— 分布选择（spawn-config.js 驱动）——

// 判断模板是否属于"危险事件"（权重表里登记的都算危险，其余是奖励/金币）
function isDangerKind(kind) {
  return !!SPAWN_CONFIG.dangerWeights[kind];
}

// 按权重表随机挑一个模板：数值越大越常见，0/负数视为关闭
function pickWeighted(weights) {
  let sum = 0;
  for (const k in weights) if (weights[k] > 0) sum += weights[k];   // 求有效权重总和
  let r = Math.random() * sum;                                      // 在总和上落一个随机点
  for (const k in weights) {
    if (weights[k] <= 0) continue;
    r -= weights[k];
    if (r < 0) return k;                                            // 落点落在哪个区间就选谁
  }
  return Object.keys(weights).find((k) => weights[k] > 0);          // 浮点兜底：返回第一个可用项
}

// 挑危险模板：按权重随机；noRepeatDanger 开启时排除上一次的危险，防止连着刷同一种
function pickDanger() {
  const w = SPAWN_CONFIG.dangerWeights;
  let pool = Object.keys(w).filter((k) => w[k] > 0);
  if (SPAWN_CONFIG.noRepeatDanger) {
    const filtered = pool.filter((k) => k !== G.lastDangerKind);
    if (filtered.length) pool = filtered;    // 全被排除时退回全池，保证总能选出一个
  }
  const tpl = pickWeighted(
    Object.fromEntries(pool.map((k) => [k, w[k]]))   // 过滤后的子表
  );
  G.lastDangerKind = tpl;      // 记住本次危险，供下轮防重复
  return tpl;
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
  const lift = groundYAt(cx) - cy;
  if (lift < COIN_LOW || lift > COIN_HIGH) return;
  if (G.obstacles.some((ob) => collectibleConflictsWithObstacle(cx, cy, ob))) return;
  G.collectibles.push({ x: cx, y: cy, type: 'coin', r: COIN_R, taken: false });
}

function pushShield(cx) {
  const cy = groundYAt(cx) - 112;
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

  // 开局安全区：safeCoinM 米内只铺金币引导，之后进入危险/奖励交替。
  if (x < SPAWN_CONFIG.safeCoinM * PX_PER_M) { coinLine(x, rint(6, 10), COIN_LOW + 10); G.lastEventKind = 'coin'; return; }

  // 模板选择：
  //   1) 测试钩子 forceEvent 优先（强制本事件用指定模板，用完即清）；
  //   2) cycle 模式 → 按 EVENT_TPL 固定顺序轮换；
  //   3) weights 模式 → 危险/奖励严格交替：危险之后必给一个奖励喘息段，
  //      奖励之后按权重挑下一个危险，且不与上一次危险重复。
  let tpl;
  if (G.forceEvent) {
    tpl = G.forceEvent;                    // 测试钩子：直接用指定模板
    G.forceEvent = null;
  } else if (SPAWN_CONFIG.mode === 'cycle') {
    tpl = EVENT_TPL[G.tplIdx % EVENT_TPL.length];
    G.tplIdx++;
  } else if (isDangerKind(G.lastEventKind)) {
    tpl = pickWeighted(SPAWN_CONFIG.calmWeights);   // 刚出过危险 → 这次必是奖励喘息
  } else {
    tpl = pickDanger();                    // 刚是奖励/开局 → 这次出危险
  }

  switch (tpl) {
    case 'jump1': {   // 单个地面障碍 + 高跳引导弧线
      const S = OBSTACLES.spike;
      if (flatFrom(x, 360) && obstacleGapOk(x, S.w)) {
        addObstacle({ kind: 'spike', x, y: gy - S.yOff, w: S.w, h: S.h, dmg: S.dmg });
        arcCoins(x - 20, rint(110, 140), 280);   // 跳跃引导弧线：提前起跳，拉长弧线让操作更宽松
      } else coinsLow(x);
      break;
    }
    case 'jump2': {   // 双柱（连续，可跳）—— 间距保证单跳落地后有反应时间处理下一根
      const S = OBSTACLES.spike;
      const gap = SPIKE_SAFE_GAP;   // 200px 安全间距：基础速度单跳能跨越
      if (flatFrom(x, gap + 180) && flatFrom(x + gap, 80) && obstacleGapOk(x, gap + S.w)) {
        addObstacle({ kind: 'spike', x, y: gy - S.yOff, w: S.w, h: S.h, dmg: S.dmg });
        addObstacle({ kind: 'spike', x: x + gap, y: gy - S.yOff, w: S.w, h: S.h, dmg: S.dmg });
        arcCoins(x - 20, rint(110, 140), gap + 60);   // 弧线覆盖两根尖刺，引导连跳
      } else coinsLow(x);
      break;
    }
    case 'spike_row': {   // 地刺阵：3-4 根连续尖刺，逐一跳跃越过
      const S = OBSTACLES.spike;
      const n = rint(3, 4);
      const gap = SPIKE_SAFE_GAP + SPIKE_ROW_REACT;   // 340px：每根间距足够单跳+反应
      const totalLen = n * gap + 60;
      if (flatFrom(x, totalLen) && obstacleGapOk(x, totalLen - 60)) {
        for (let i = 0; i < n; i++) {
          addObstacle({ kind: 'spike', x: x + i * gap, y: gy - S.yOff, w: S.w, h: S.h, dmg: S.dmg });
        }
        // 整条弧线覆盖地刺阵，引导节奏跳跃
        arcCoins(x - 30, rint(120, 150), totalLen - 80);
      } else coinsLow(x);
      break;
    }
    case 'pillar': {  // 石柱：跳跃越过
      const P = OBSTACLES.pillar;
      if (flatFrom(x, 360) && obstacleGapOk(x, P.w)) {
        addObstacle({ kind: 'pillar', x, y: gy - P.yOff, w: P.w, h: P.h, dmg: P.dmg });
        arcCoins(x - 20, rint(100, 130), 300);   // 跳跃引导弧线
      } else coinsLow(x);
      break;
    }
    case 'slide': {   // 垂板：从天花板垂下，底部留空隙，滑铲通过
      const B = OBSTACLES.beam;
      const bw = rint(B.wMin, B.wMax);
      if (flatFrom(x, bw + 120) && obstacleGapOk(x, bw)) {
        addObstacle({ kind: 'beam', x, y: 0, w: bw, h: gy - B.gap });
        coinLine(x - 40, 5, COIN_LOW + 6);   // 前置低空金币引导滑铲
      } else coinsLow(x);
      break;
    }
    case 'ninja': {   // 剑忍：贴地近战，碰到砍一刀扣 DMG_NINJA（最大伤害），跳跃越过
      if (flatFrom(x, 320) && obstacleGapOk(x, NINJA_W)) {
        addObstacle({ kind: 'ninja', x, y: gy - NINJA_H, w: NINJA_W, h: NINJA_H, dmg: DMG_NINJA });
        arcCoins(x - 30, rint(110, 140), 280);   // 跳跃引导弧线
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
    case 'boulder': {   // 滚石：贴地迎面滚来的单体动态障碍，跳跃越过
      if (flatFrom(x, 380)) {
        const lead = x + BOULDER_SPEED * REACT_T * 1.4 + 150;  // 预警距离加长，反应时间更充裕
        addObstacle({ kind: 'boulder', x: lead, y: gy - BOULDER_H, w: BOULDER_W, h: BOULDER_H, dmg: DMG_SPIKE });
        G.nextSpawnX = Math.max(G.nextSpawnX, lead + 180);   // 滚石后多留空间
      } else coinsLow(x);
      break;
    }
    case 'rock': {   // 落石预警：从高空砸下，落地前 0.5s 地面出现扩散阴影圈 → 跳跃躲避
      if (flatFrom(x, 280) && obstacleGapOk(x, ROCK_W)) {
        addObstacle({ kind: 'rock', x, y: -ROCK_H, landY: gy - ROCK_H, w: ROCK_W, h: ROCK_H, dmg: DMG_ROCK, warnT: ROCK_WARN_T });
      } else coinsLow(x);
      break;
    }
    case 'inkwall': {   // 墨墙：从地面立起的实墙，底部拱门空隙，滑铲钻过
      if (flatFrom(x, 260) && obstacleGapOk(x, INK_WALL_W)) {
        const y = gy - INK_WALL_H, h = INK_WALL_H - INK_WALL_ARCH;
        addObstacle({ kind: 'inkwall', x, y, w: INK_WALL_W, h, dmg: DMG_WALL });
        coinLine(x - 40, 5, COIN_LOW + 6);   // 前置低空金币引导滑铲
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
  if (SPAWN_CONFIG.mode === 'infinite') return spawnInfiniteLoop();
  const camX = G.scrollX;
  while (G.nextSpawnX < camX + W + SPAWN_EXTRA) {
    makeEvent(G.nextSpawnX);
    const calm = G.lastEventKind.startsWith('reward') || G.lastEventKind === 'coins_flat' || G.lastEventKind === 'coin';
    G.nextSpawnX += pickGap() + (calm ? 0 : SPAWN_CONFIG.dangerGapBonus);   // 危险之后多留反应余地
  }
  // 清理出屏：右界放宽一个金币事件跨度，避免刚生成的带型金币被误清
  G.obstacles = G.obstacles.filter((o) => {
    if (o.x + o.w > camX - CLEAN_MARGIN) return true;
    // Keep hazards owned by the rope route until the player exits that route.
    // The camera can pass far ahead of the fixed player while traversing it.
    if (G.player.ropeMode && o.routeStart === G.player.ropeRouteStart) return true;
    return false;
  });
  G.collectibles = G.collectibles.filter((c) => c.x + COLLECT_SWEEP > camX - CLEAN_MARGIN && c.x - COLLECT_SWEEP < camX + W + CLEAN_MARGIN + COIN_MAX_SPAN);
}

// Infinite modular route. Each module owns its terrain and encounters; a short flat
// connector at both ends keeps random joins readable and prevents forced collisions.
export const MODULES = [
  { name: 'spikes', parts: [{ type: 'flat', width: 980 }], build(x) {
    for (const dx of [360, 650, 820]) addObstacle({ kind: 'spike', x: x + dx, y: groundYAt(x + dx) - 72, w: 24, h: 72, dmg: DMG_SPIKE });
    arcCoins(x + 310, 125, 420);
  } },
  { name: 'slope', parts: [{ type: 'slope', width: 520, y0: GROUND, y1: GROUND - 72 }, { type: 'slope', width: 520, y0: GROUND - 72, y1: GROUND }], build(x) {
    for (const dx of [300, 700]) { const gy = groundYAt(x + dx); addObstacle({ kind: 'spike', x: x + dx, y: gy - 72, w: 24, h: 72, dmg: DMG_SPIKE }); }
    arcCoins(x + 220, 118, 520);
  } },
  { name: 'platform', parts: [{ type: 'flat', width: 260 }, { type: 'pit', width: 180 }, { type: 'flat', width: 150 }, { type: 'platform', width: 520, y: GROUND - 118 }, { type: 'flat', width: 220 }], build(x) {
    addObstacle({ kind: 'portal', x: x + 165, y: GROUND - 86, w: 34, h: 86, dmg: 0, targetX: x + 520, targetY: GROUND - 118 - 66 });
    addObstacle({ kind: 'spike', x: x + 690, y: GROUND - 118 - 72, w: 24, h: 72, dmg: DMG_SPIKE });
    coinLine(x + 470, 6, 118); arcCoins(x + 620, 105, 300);
  } },
  { name: 'rope', parts: [
      { type: 'flat', width: 300 },
      { type: 'slope', width: 180, y0: GROUND, y1: GROUND - 112 },
      // 绳索是一整段独立路线：进入后持续附着，直到出口斜面。
      { type: 'rope', width: 2600, y: GROUND - 112, ropeMin: GROUND - 188, ropeMax: GROUND - 72, route: true },
      { type: 'slope', width: 180, y0: GROUND - 112, y1: GROUND },
      { type: 'flat', width: 300 },
    ], build(x) {
    const ropeStart = x + 300 + 180;
    const ropeY = GROUND - 112;
    // 障碍全部落在绳索主体内部，按“看见摆动、上下翻越、再看见出口”的节奏排布。
    for (const [dx, angle] of [[320, 0.35], [920, -0.55], [1540, 0.7], [2140, -0.4]]) {
      const ax = ropeStart + dx;
      addObstacle({
        kind: 'scythe', x: ax, anchorX: ax, anchorY: ropeY - 148,
        ropeLen: 126, angle, omega: 2.2, w: 42, h: 42, dmg: DMG_PILLAR,
        routeStart: ropeStart, routeEnd: ropeStart + 2600,
      });
    }
    // 高低交替的悬挂尖刺，迫使玩家在绳索上用上下翻调整路线。
    for (const [dx, lift] of [[620, 108], [1220, 72], [1840, 108]]) {
      addObstacle({ kind: 'spike', x: ropeStart + dx, y: ropeY - lift - 72, w: 24, h: 72, dmg: DMG_SPIKE,
        routeStart: ropeStart, routeEnd: ropeStart + 2600 });
    }
    for (let i = 0; i < 18; i++) {
      const t = i / 17;
      const cx = ropeStart + 120 + t * 2280;
      const cy = ropeY - (i % 2 ? 104 : 42);
      G.collectibles.push({ x: cx, y: cy, type: 'coin', r: COIN_R, taken: false });
    }
  } },
  { name: 'mixed', parts: [{ type: 'flat', width: 1180 }], build(x) {
    addObstacle({ kind: 'beam', x: x + 420, y: 0, w: 44, h: GROUND - 54 });
    addObstacle({ kind: 'pillar', x: x + 760, y: GROUND - 80, w: 46, h: 80, dmg: DMG_PILLAR });
    coinLine(x + 370, 6, 44); arcCoins(x + 710, 128, 300);
  } },
];

function appendModule() {
  const last = G.moduleName;
  const pool = MODULES.filter((m) => m.name !== last);
  const mod = pool[Math.floor(Math.random() * pool.length)];
  const connector = 260;
  const start = G.nextChunkX;
  appendTerrain([{ type: 'flat', width: connector }, ...mod.parts, { type: 'flat', width: connector }], start);
  mod.build(start + connector);
  G.moduleName = mod.name;
  G.chunkIndex = (G.chunkIndex || 0) + 1;
}

export function spawnInfiniteLoop() {
  const camX = G.scrollX;
  while (G.nextChunkX < camX + W + SPAWN_EXTRA) appendModule();
  G.obstacles = G.obstacles.filter((o) => {
    if (o.x + (o.w || 0) > camX - CLEAN_MARGIN) return true;
    if (G.player.ropeMode && o.routeStart === G.player.ropeRouteStart) return true;
    return false;
  });
  G.collectibles = G.collectibles.filter((c) => c.x + COLLECT_SWEEP > camX - CLEAN_MARGIN && c.x < camX + W + COIN_MAX_SPAN);
}
