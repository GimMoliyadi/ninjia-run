export const W = 960, H = 540;
export const GROUND = 462;            // 地面线 y
export const ABYSS = H + 40;          // 深坑坑底：掉到坑底才会死，之前可见的下坠过程
export const GRAV = 2600;             // 重力
export const JUMP_RELEASE_MULT = 2.5; // 松开跳跃键后重力倍率(可变跳跃高度)：起跳时按住跳得更高，松开提前回落
export const JUMP_V = 920;            // 一跳初速
export const JUMP2_V = 840;           // 二段跳初速
export const DIVE_V = 900;            // 俯冲初速
export const START_SPEED = 360;       // 基础速度 px/s
export const MAX_SPEED = 1000;
export const STAND_H = 66;            // 站立高
export const SLIDE_H = 32;            // 滑行高
export const SLIDE_DUR = 0.58;        // 滑铲持续时长：缩短让滑铲更干脆利落
export const DASH_SHIFT_MAX = 72;     // 滑铲时角色相对画面的最大前移量
export const SLIDE_ACCEL_T = 0.14;    // 滑铲前移平滑到位时长（再缩短，让起手更爆发）
export const SLIDE_RECOVER_T = 0.08;  // 滑铲起身间歇：缩短到 0.08s，连续滑铲更流畅
export const SLIDE_SPEED_BONUS = 180; // 滑铲峰值场景加速，和前移共用同一缓入曲线
export const DASH_HOLD_T = 0;         // 滑铲到终点后立即开始复位
export const DASH_JUMP_BOOST_DUR = 0.86; // 覆盖完整一段跳，并给二段跳保留前移窗口
export const DASH_JUMP_SPEED_BONUS = 150; // 滑铲接跳的额外场景速度，随冲刺窗口衰减
export const DASH_JUMP_SHIFT_MAX = 160; // 滑铲接跳的总前移上限（助跑起跳更远）
export const DASH_RETURN_SPEED = 260; // 回位速度：滑铲/被撞推偏后快速回到默认站位，收尾干脆不拖沓
export const SLIDE_DIST_BASE = START_SPEED * SLIDE_DUR + DASH_SHIFT_MAX;
export const AIR_CANCEL_V = 560;      // 空中打断起跳后的下落初速
export const RUN_CYCLE_FPS = 18;      // 基础跑步循环速率：runT × 此值推进 RUN_POSES（提速让动作更流畅）
export const RUN_STRIDE_MIN = 0.85;   // 步幅幅度缩放下限：慢速时步伐不至于僵直
export const RUN_STRIDE_MAX = 2.4;    // 步幅幅度缩放上限：极速时腿跨得最开
export const RUN_LEAN_RAD = 0.21;     // 冲刺躯干前倾角（弧度，约 12°），绕脚底旋转
export const COYOTE_T = 0.15;         // 土狼时间：离地后仍可跳跃
export const JUMP_BUFFER = 0.12;      // 跳跃缓冲：落地前按键自动起跳
export const PW = 46;                 // 角色宽
export const PLAYER_X = 270;          // 角色屏幕固定 x
export const BG = '#f2ecd9';          // 宣纸底
export const INK = '#2b2b31';         // 墨色
export const RED = '#a53a2e';         // 印泥红
export const GOLD = '#d8a441';        // 符咒金

export const COIN_LOW = 38;           // 金币离地最小高度
export const COIN_HIGH = 138;         // 金币离地最大高度（低于一跳极限，保证可达）
export const COIN_GAP = 88;           // 同路线金币默认水平间距（保证连续可收集）
export const SAFE_FLAT_PX = 700;     // 开局保留约 2 秒缓冲，随后立即进入随机关卡
export const REACT_T = 0.34;          // 障碍最小反应时间 s
export const OB_GAP_MIN = 250;        // 静态障碍最小间距：约一个跳跃距离，防重叠/堵死

// ---- 跳跃设计参数（关卡生成用） ----
// 用于计算障碍间距，保证玩家有足够能力应对
export const JUMP_AIR_T = 2 * JUMP_V / GRAV;           // 单次跳跃滞空时间 ≈ 0.708s
export const JUMP2_AIR_T = 2 * JUMP2_V / GRAV;         // 二段跳滞空时间 ≈ 0.646s
export const JUMP_DIST_BASE = START_SPEED * JUMP_AIR_T;   // 基础速度下单跳水平距离 ≈ 255px
export const JUMP2_DIST_BASE = START_SPEED * (JUMP_AIR_T + JUMP2_AIR_T); // 基础速度下二段跳总距离 ≈ 488px
export const SPIKE_SAFE_GAP = 200;     // 地刺阵单根间距：保证基础速度单跳+余量能越过
export const SPIKE_ROW_REACT = 140;    // 地刺阵额外反应空间：每根之间留一点喘息

// ---- 忍术 / 收集 ----
export const ENERGY_MAX = 100;         // 忍术能量上限
// 螺旋丸：释放后向前发射的旋转墨球，连穿击碎沿途障碍，寿命耗尽墨散消隐。
export const RASENGAN_SPEED = 1400;    // 世界坐标前飞速度 px/s（恒高于场景极速，保证任何时段都向前飞）
export const RASENGAN_LIFE = 1.5;      // 飞行寿命 s（约 2.1 千像素射程，推出屏幕外）
export const RASENGAN_R = 38;          // 碰撞半径 px（直径 76 > 人物 46×66，视觉与判定一起随此值缩放）
export const RASENGAN_LIFT = 40;       // 出手高度：掌心离脚底的高度 px
export const RASENGAN_CAST_INVULN_T = 0.5; // 释放忍术瞬间的短暂无敌 s
// 火球术：武器技能，Q 键或点击屏幕右下按钮释放，冷却时间（不耗能量）。
// 持续 10 秒，3 枚火球水平环绕角色护体；发现活物（飞镖/滚石/剑忍）就脱轨追踪焚毁。
// 火球飞出后立即在原位补充新火球，保持 3 枚环绕直到技能结束。
// 固定建筑（尖刺/石柱/垂板/墨墙）与落石不可被破坏，火球会直接穿过。
export const FIRE_CD = 10;             // 冷却时长 s
export const FIRE_ORB_COUNT = 3;       // 同时环绕的火球数（发射后立即补充）
export const FIRE_ORBIT_R = 58;        // 环绕半径 px
export const FIRE_ORBIT_SPD = 3.2;     // 环绕角速度 rad/s
export const FIRE_SPEED = 1050;        // 追踪飞行速度 px/s
export const FIRE_TURN = 9;            // 追踪转向速率 rad/s（越大追踪越硬）
export const FIRE_R = 11;              // 火球碰撞半径 px
export const FIRE_LIFE = 10;           // 火球术持续时间 s（技能结束全部熄灭）
export const FIRE_LIFT = 40;           // 环绕中心离脚底高度 px
export const FIRE_SEEK_RANGE = 560;    // 索敌范围 px
export const FIRE_BTN = { x: W - 74, y: H - 70, r: 34 };  // 右下技能按钮（圆心 + 半径）
export const SHIELD_DUR = 10;           // 护盾持续时间 s
export const SHIELD_WARN_T = 3;         // 护盾进入闪光提示的剩余时间
export const CLEAR_SCORE = 50;         // 每清一个障碍的分

// ---- 血量 / 伤害 ----
// 基础机制从"一触即死"改为血条：普通障碍撞一次扣一格数值血，血条每帧自然恢复；
// 仅存一类即死机关（无视血条与护盾）：深坑坠落；其余障碍一律按血条硬扛 + 位移反馈。
export const HP_MAX = 50;           // 血条上限：轻伤（尖刺/飞镖）连续约 5 次见底，惩罚够重
export const HP_REGEN = 1;          // 每秒自然回血：满血恢复约 50 秒，与减半血量同节奏
export const HP_BAR_FADE = 2.0;     // 血回满后血条淡出时长：受伤才见血条，回满不常驻遮挡
export const HIT_INVULN_T = 1.0;    // 受击后无敌时长：防止连续碰撞瞬间清空血条
export const HIT_KNOCK_PX = 44;     // 受击后撤距离：撞上障碍往画面左（身后）弹开，随后平滑回到原位
export const DMG_NINJA = 30;        // 剑忍砍伤（近战最疼）
export const DMG_PILLAR = 20;       // 石柱撞伤
export const DMG_SPIKE = 12;        // 尖刺擦伤（最常见、最轻）
export const DMG_DART = DMG_SPIKE;  // 飞镖擦伤：与尖刺同级轻伤
// 垂板是实体墙（推挤机制），撞墙不掉血；仅深坑坠落即死且护盾挡不住。

// ---- 持刀忍者 / 纸鹤 ----
// 持刀忍者：贴地近战敌人，无远程、无预警——纯近身威胁，碰到砍一刀扣 DMG_NINJA。
// 刀身带呼吸式反光闪动作为危险提示，让"活物"感与静态障碍区分。
export const NINJA_W = 26, NINJA_H = 58;     // 忍者碰撞盒（贴地）

// ---- 落石（预警障碍） ----
// 落石：从高处坠下的岩石，落地前 0.5s 地面出现扩散阴影圈预警 → 跳跃躲避。
// 预警与下落途中无碰撞，落地后按静态尖刺级轻伤处理。
export const ROCK_WARN_T = 0.5;          // 预警时长 s（阴影圈提示）
export const ROCK_FALL_V = 1500;         // 落石下落速度 px/s
export const ROCK_W = 40, ROCK_H = 40;   // 落石碰撞盒（方形贴地）
export const DMG_ROCK = DMG_SPIKE;       // 落石砸伤：与尖刺同级轻伤

// ---- 墨墙（滑铲障碍） ----
// 墨墙：从地面立起的墨色实墙，底部留拱门空隙 → 站立必撞、只能滑铲钻过。
// 与垂板互补：垂板顶天花板/下沿离地，墨墙立地面/上段实墙+下段拱门。
export const INK_WALL_W = 56;            // 墨墙宽度
export const INK_WALL_H = 120;           // 墨墙总高（从地面）
export const INK_WALL_ARCH = 52;         // 拱门空隙高（≥ 滑铲盒高+余量）
export const DMG_WALL = DMG_PILLAR;      // 墨墙撞伤：与石柱同级

// ---- 滚石（迎面动态障碍） ----
// 滚石：贴地迎面滚来的大圆石，跳跃越过；撞上扣尖刺级轻伤。
export const BOULDER_W = 40, BOULDER_H = 40; // 滚石碰撞盒（方形贴地）
export const BOULDER_SPEED = 300;            // 迎面滚动速度：恒定不随场景速度变，保肌肉记忆

// ---- 飞镖潮（迎面动态障碍） ----
// 飞镖迎面朝玩家水平飞（世界坐标 x 递减），撞上按 DMG_SPIKE 扣血（普通伤害，护盾可挡、忍术可清）。
// 双轨高度按忍者身高（站立盒 [396,462] 高 66、滑铲盒 [430,462] 高 32、头线 396）设计，高低各司其职：
//   低轨 DART_LOW_LIFT=50 → [412,448]：盖住中下段身体，站立/滑铲都相交 → 只能跳；一跳 0.1s 即越过头顶，干净越过；
//   高轨 DART_HIGH_LIFT=90 → [372,408]：顶到头顶以上，站立必中、滑铲盒底 430 之上净空 22px 恒安全；
//     起跳上升段 0.117s 内必撞（身体从 [396,462] 升过飞镖区间），下落段再扫回来 → 跳不过，只能滑铲钻过。
// 枚间距用足够反应的时间窗（0.55-0.70s）：跳完一枚落地后还有缓冲再处理下一枚，不紧逼。
export const DART_W = 34, DART_H = 36;           // 四刃手里剑碰撞盒（更高更醒目）
export const DART_SPEED = 380;                   // 迎面飞行速度：恒定不随场景速度变，保肌肉记忆
export const DART_LOW_LIFT = 50;                 // 低轨离地高度（盖住中下段身体）→ 只能跳跃躲
export const DART_HIGH_LIFT = 90;                // 高轨离地高度（顶到头顶以上）→ 只能滑铲钻过
export const DART_WAVE_MIN = 3;                  // 一波飞镖最少枚数
export const DART_WAVE_MAX = 5;                  // 一波飞镖最多枚数（成簇来袭，不铺开）
export const DART_GAP_T_MIN = 0.55;              // 枚间距时间窗下限 s（反应时间充裕）
export const DART_GAP_T_MAX = 0.70;              // 枚间距时间窗上限 s
export const DART_FIRST_LEAD = 360;              // 首枚入屏预警距离：≥2×REACT_T 反应时间
export const DART_PIT_LAND_GAP = 150;            // 深坑避让：从坑尾再退回到可着陆平地
export const DART_WAVE_TAIL_GAP = 400;           // 波尾隔离：后续静态障碍不插进飞镖潮到达时间窗
// 波形编排：每波由单个 pattern 决定高低轨序列（而非每枚独立随机），按距离从纯波教学渐进到混合波。
// 顺序即难度阶梯：hop(全跳)→slide(全滑)→alt(交替)→lead(末枚孤高收尾)。
export const DART_PATTERN_MIX = ['hop', 'slide', 'alt', 'lead'];
export const DART_PATTERN_MIX_M = 1500;           // 教学期：此距离内只出纯波（跳/滑）
export const DART_PATTERN_HARD_M = 4000;         // 越过教学期加入交替，之后含收尾加强
export const DART_APPROACH_RANGE = 340;          // 入场墨晕作用范围：飞镖距玩家短于此才开始收敛实心
export const COIN_SCORE = 10;          // 单枚金币固定加分（连击系统已移除）
export const COIN_ENERGY = 2;          // 单枚金币能量（主动收集约 30-60 秒攒满一次忍术）
export const SCROLL_ENERGY = 25;       // 单卷轴能量（高空大跳奖励）
export const SCROLL_SCORE = 30;        // 单卷轴分
export const HIT_ENERGY = 15;          // 受击一次补充能量：挨打换忍术
export const DODGE_ENERGY = 10;        // 完美闪避补充能量：贴脸躲过障碍
export const DODGE_SCORE = 40;         // 完美闪避加分

// ---- 物理 / 判定 ----
export const DIVE_GRAV_MULT = 1.8;     // 俯冲时重力倍率
export const LAND_IMPACT_VY = 900;     // 触发落地墨爆的下落速度阈值
export const PIT_FALL_VY = 120;        // 踏入深坑初始下落速度
export const DEATH_DEPTH_MARGIN = 6;   // 下坠距坑底多近判死
export const DOUBLE_TAP_MS = 250;      // 空中连按↓判定俯冲的时间窗

// ---- 收集物 ----
export const COIN_R = 14;              // 金币碰撞半径
export const SCROLL_R = 15;            // 卷轴碰撞半径
export const SHIELD_R = 16;            // 护盾符印碰撞半径
export const COLLECT_RADIUS_EXTRA = 4; // 收集判定比贴图半径多出

// ---- 计分 / 距离 ----
export const SCORE_PER_PX = 10;        // 每前进 10px 得 1 分
export const PX_PER_M = 100;           // 每 100px 计 1 米

// ---- 场景区域（Zone） ----
export const ZONE_VILLAGE_AT = 200;   // 到达此米数切入"黄昏村"
export const ZONE_MOUNTAIN_AT = 500;  // 到达此米数切入"夜冥山"
export const ZONE_TRANSITION_T = 0.55; // 区域切换泼墨过渡时长 s

// ---- 生成 / 回收 ----
export const SPAWN_EXTRA = 160;        // 事件生成前瞻：视野右缘额外预留
export const CLEAN_MARGIN = 200;       // 出屏回收边距
export const COLLECT_SWEEP = 30;       // 收集物回收半径上界（> 最大贴图半径）
export const COIN_MAX_SPAN = 10 * COIN_GAP;  // 单个金币事件最大横向跨度（清理右界按此放宽）
export const COIN_OB_MARGIN_X = 20;    // 金币避开障碍的水平边距
export const COIN_OB_MARGIN_TOP = 6;   // 金币避开障碍的顶部边距
export const COIN_OB_MARGIN_BOT = 24;  // 金币避开障碍的底部边距

// ---- 文本 / 界面 ----
export const KAI = '"KaiTi","STKaiti","楷体","DFKai-SB","FangSong","serif"';
