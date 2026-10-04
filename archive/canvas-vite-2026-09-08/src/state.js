// 共享可变状态：ES Modules 的 import 绑定只读，可变状态全部收敛到此单例对象，
// 各模块通过 G.xxx 读写，保证单一数据源、无全局裸奔。
export const G = {
  debugMode: localStorage.getItem('inkNinjaDebug') === '1',

  // 游戏流程
  state: 'title',
  scrollX: 0, speed: 0, gameTime: 0,
  score: 0, collectScore: 0, distM: 0,
  best: +(localStorage.getItem('inkNinjaBest') || 0),
  energy: 0,
  deathT: 0, deadAt: 0, newBest: false,
  nextSpawnX: 0, coyote: 0, jumpBuf: 0,
  nextChunkX: 0, chunkIndex: 0, moduleName: null,

  // 滑铲前移（角色相对画面的水平位移）
  dashShift: 0,
  // 滑铲结束后的前移惯性保持时长：起身后短暂保留前移，避免站位瞬间回弹
  dashHoldT: 0,
  // 滑铲起身间歇倒计时：每段滑铲之间有约 0.1s 停顿，防止无缝连滑手感黏滞
  slideLockT: 0,

  // 本帧是否被竖板墙顶住（用于站位恢复）
  wallPushed: false,

  // 场景区域
  zone: 'bamboo',
  zoneTransitionT: 0,   // 区域切换泼墨过渡剩余时间 s

  // 玩家状态
  player: {
    x: 0, y: 0, vy: 0,
    onGround: true, jumps: 0,
    sliding: false, slideT: 0, slideQueued: false,
    jumpT: 0,
    dashBoostT: 0, dashCarrying: false,
    invuln: 0, shieldT: 0, runT: 0,
    hp: 100,   // 血条，满值由 resetGame 从 HP_MAX 同步
    dropThroughT: 0,
    ropeMode: false,
    ropeOffset: 0,
    ropeFlipT: 0,
    ropeFlipFrom: 0,
    ropeFlipTo: 0,
    ropeRouteStart: null,
    ropeRouteEnd: null,
    hpBarT: 0, // 血条显示强度 0~1：受伤置 1 显示，回满后淡出归零
    heldJump: false,   // 起跳瞬间跳跃键是否按住（可变跳跃高度：按住=全程上升，松开=提前切断）
  },

  // 世界实体
  obstacles: [], collectibles: [], particles: [],
  rasengan: null,            // 螺旋丸（忍术）：向前发射的旋转墨球，见 ninjutsu.js
  fireballs: null,           // 火球术（武器技能）：环绕护体的火球组，见 fireballs.js
  fireCd: 0,                 // 火球术冷却倒计时（s）：归零后方可再次释放
  lastDangerKind: null,      // 上一次的危险模板名：配合 noRepeatDanger 防止单调
  forceEvent: null,          // 测试钩子：强制下一个事件使用此模板（正常游玩恒为 null）
  lastEventKind: 'rest',

  // 远处装饰
  bamboos: [], mountains: [], clouds: [],
  // 区专属装饰：村町灯笼 / 冥山枯树与鬼火
  lamps: [], deadTrees: [], ghostFires: [],

  // 地形
  terrain: [],

  // 输入
  jumpHeld: false,
  airDownT: -1e9,

  // 生成器状态（见 spawn-config.js 与 lastDangerKind/forceEvent 字段说明）


  // 主循环时间戳
  lastT: 0,

};

// 状态枚举（不可变，独立导出）
export const ST = { TITLE: 'title', RUN: 'run', PAUSED: 'paused', DEAD: 'dead' };

// 画布与上下文
export const canvas = document.getElementById('c');
export const ctx = canvas.getContext('2d');

// 调试/自动化访问点：浏览器 evaluate 经 window.G 读同一实例，
// 避免 Vite 动态 import 产生第二份模块图
if (typeof window !== 'undefined') window.G = G;
