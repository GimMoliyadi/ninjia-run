export const W = 960, H = 540;
export const GROUND = 462;            // 地面线 y
export const ABYSS = H + 40;          // 深坑坑底：掉到坑底才会死，之前可见的下坠过程
export const GRAV = 2600;             // 重力
export const JUMP_V = 920;            // 一跳初速
export const JUMP2_V = 840;           // 二段跳初速
export const DIVE_V = 900;            // 俯冲初速
export const START_SPEED = 360;       // 基础速度 px/s
export const MAX_SPEED = 800;
export const STAND_H = 66;            // 站立高
export const SLIDE_H = 32;            // 滑行高
export const SLIDE_DUR = 0.72;        // 滑铲兜底上限：正常情况越过垂板即起身，此值防极端场景卡低姿态过久
export const DASH_SHIFT_MAX = 72;     // 滑铲时角色相对画面的最大前移量
export const SLIDE_ACCEL_T = 0.28;    // 滑铲前移平滑到位时长（三次缓入收敛，替代线性）
export const SLIDE_SPEED_BONUS = 180; // 滑铲峰值场景加速，和前移共用同一缓入曲线
export const DASH_HOLD_T = 0.35;      // 滑铲结束后的前移惯性保持时长：连滑期间不回落，避免回退抽搐
export const DASH_JUMP_BOOST_DUR = 0.86; // 覆盖完整一段跳，并给二段跳保留前移窗口
export const DASH_JUMP_SPEED_BONUS = 150; // 滑铲接跳的额外场景速度，随冲刺窗口衰减
export const DASH_JUMP_SHIFT_MAX = 160; // 滑铲接跳的总前移上限（助跑起跳更远）
export const DASH_RETURN_SPEED = 160; // 回位速度：慢于基础跑速，落地后自然滑回原位
export const AIR_CANCEL_V = 560;      // 空中打断起跳后的下落初速
export const RUN_CYCLE_FPS = 12;      // 基础跑步循环速率：runT × 此值推进 RUN_POSES
export const RUN_STRIDE_MIN = 0.75;   // 步频缩放下限：慢速时动作不至于拖沓
export const RUN_STRIDE_MAX = 2.1;    // 步频缩放上限：极速时腿不糊成残影
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
export const SAFE_FLAT_PX = 5000;    // 前 50 米纯平地：新手先适应奔跑节奏
export const SAFE_EVENT_PX = 1000;   // 前 10 米只出金币引导，之后进入障碍与奖励交替
export const REACT_T = 0.34;          // 障碍最小反应时间 s

// ---- 忍术 / 收集 / 连击 ----
export const ENERGY_MAX = 100;         // 忍术能量上限
export const NINJUTSU_DURATION = 1.65; // 前方冲击波持续时间 s
export const NINJUTSU_SPEED = 920;     // 冲击波前进速度 px/s
export const NINJUTSU_RADIUS = 78;     // 冲击波横向命中半径
export const NINJUTSU_INVULN_T = NINJUTSU_DURATION;
export const SHIELD_DUR = 10;           // 护盾持续时间
export const SHIELD_WARN_T = 3;         // 护盾进入闪光提示的剩余时间
export const CLEAR_SCORE = 50;         // 每清一个障碍的分

// ---- 血量 / 伤害 ----
// 基础机制从"一触即死"改为血条：普通障碍撞一次扣一格数值血，血条每帧自然恢复；
// 仅存一类即死机关（无视血条与护盾）：深坑坠落；其余障碍一律按血条硬扛 + 位移反馈。
export const HP_MAX = 100;          // 血条上限
export const HP_REGEN = 2;          // 每秒自然回血：约 50 秒从空回满，挨一刀十几秒才缓过来，惩罚够重
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
export const DART_PATTERN_MIX_M = 1500;          // 教学期：此距离内只出纯波（跳/滑）
export const DART_PATTERN_HARD_M = 4000;         // 越过教学期加入交替，之后含收尾加强
export const DART_APPROACH_RANGE = 340;          // 入场墨晕作用范围：飞镖距玩家短于此才开始收敛实心
export const COMBO_SCORE = 10;         // 连击单枚金币基础分
export const COMBO_CAP = 5;            // 连击计分上限
export const COMBO_TIMEOUT = 3;        // 连击保持时间 s
export const COIN_ENERGY = 1;          // 单枚金币能量（主动收集约 15 秒攒满一次忍术）
export const SCROLL_ENERGY = 30;       // 单卷轴能量（高空大跳奖励）
export const SCROLL_SCORE = 30;        // 单卷轴分

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
