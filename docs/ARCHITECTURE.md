# ARCHITECTURE.md — 当前架构快照

> **这是"当前架构快照"。**
>
> 每次 Route / Segment / Section / Pattern 调用关系发生实质变化时，同步更新本文件。
>
> 长期稳定的工作规则、真值来源、设计原则在
> `.codebuddy/skills/ninja-run-level-design/SKILL.md`；
> 关卡设计细则在 `docs/LEVEL_DESIGN.md`。
> 本文件只描述**现在代码实际长什么样**。

最后更新：2026-10-02。默认正式路线恢复为五种完整地图及原有节奏挑战，不再由三种短组合循环替代。

### 当前正式路线（优先于下文历史快照）

`game.gd` 仍通过 `RhythmRouteGenerator.build_cycle()` 和原 `CHUNK_SCENES` 索引生成场景。每圈共13段：SAFE热身后接三张换序完整地图、REST，再接其余两张完整地图和一个旧挑战、REST，最后接三个旧挑战和FINISH收尾。

- `DARTS`、`JUMP_MAP`、`ROPE_MAP`、`PLATFORM_DART_MAP`、`NINJA_MAP`每圈各出现一次，位于索引1、2、3、5、6；前两图为跳跃/飞镖，第三图为绳索，后两图为平台/忍者，同层按种子换序。
- 末段只使用MIXED、SLALOM、ROPE_SWITCH、COMBO综合挑战；两处REST保留，但缩为720px，不在每个挑战后追加SHORT_RECOVERY。
- `ChunkKind` 和21项场景索引不变。短组合及SHORT_RECOVERY资源仍保留为练习内容，但不再进入默认候选池。
- `MapModuleChunk._ready()`同步建图、真实Entry/Exit衔接、固定种子重开和换圈逻辑均不变，地图内部现有修正不回滚。
- 路线恢复阶段保留人物相关实现与原地图资源；后续机关扩展见下一节。按用户要求，本阶段不运行自动测试，体验由用户亲自试玩确认。

### 障碍编排扩展（2026-10-02）

- 保留上述13段正式路线与五张完整地图，修改只发生在地图内部与障碍组件；Player物理、角色跑姿、高清纹理和残影不回滚。
- `SlideBeam` 使用 `BASE_SIZE = (BODY_SIZE.x × 2, SLIDE_HEIGHT)` 统一绘图和碰撞，原五处手工实例底边仍为408；`PatternLayouts.ceiling()`按该尺寸定位。吊链无碰撞，滑铲不再靠状态免伤，而靠真实净空。
- `BladeWheel`继承`dart.gd`，半径来自`SLIDE_HEIGHT × 0.75`；默认飞镖仍为11px半径。相遇计时复用移动事件，刃轮采用独立预览类型，不混入平地飞镖ACT统计。
- `FallingBlade`通过`initialize/advance/player_contact`接入Runner，可见预告后快速下落、短暂停留并释放；圆形扫掠只结算一次伤害，最低底边保留`SLIDE_HEIGHT+8`净空。
- `JumpPillar`新增默认关闭的`crumble_delay/crumble_over_pit`。只有真实顶面接触才触发；禁用实体碰撞后绘制短时碎屑，不留下隐形支撑。拼接重算地面时保留碎台下方坑并合并区间。
- `ACTION_PHRASE`增加`roller/falling_blade/crumble_platform`，`JUMP_WAVE`的柱类phrase可携带碎台参数。Jump图第一段接入刃轮，第二段接入碎台与落刃，第三段使用高低碎桥。
- 平台飞镖第2/6/8波改为`vault/landing_slide/vault_slide`组合；忍者第6波加入台上守位。普通飞镖新增`CROWN/HOOK/LIFTED_PAIR`，只改安全高度，原ACT时间线不变。
- `PatternEvent.PreviewKind`仅追加`PLATFORM=4/BLADE_WHEEL=5/FALLING_BLADE=6`，原0～3不变。预览按实际几何显示；后续恢复自动测试时，旧测试中用OTHER识别平台的断言需要同步。
- 镜头保持原比例和垂直跟随，前视距离增为240px，为高速读招留空间。
- 本轮按用户要求不运行测试、引擎导入或自动试玩；保留`needs_manual_playtest`，几何、预告、碰撞与实际手感均待用户试玩确认。

### 本轮节奏编排

- 五类完整地图和13段骨架保留。生成器先在跳跃/飞镖基础图中换序，接绳索换线，再在平台/忍者综合图中换序；尾部仅抽取MIXED、SLALOM、ROPE_SWITCH、COMBO，跨REST不立即重复同一种挑战。
- SAFE、REST、FINISH统一720px；地面图形、实体宽度、Exit和金币位置同步，720px在峰值620下仍覆盖一次完整跳跃的收势。
- 飞镖仍为八波43枚，改为跨波动作句与高潮呼应，连续ACT簇及干净分簇的静态间距保留在库规则范围内；资源声明总长约6318px，不当作实跑时长。
- 平台图保留八波、三Section，40台缩为31台。教学为三台短句，中段三四台变化，后段五台回旋与六台综合；Recovery只在段落收势处。
- 绳索图三Section改为单侧读招、上下短串接力、同侧刺镖合拍和短答收势；编排飞镖90减为44，不用同形长列堆密度。翻面仍由原运动规则负责。
- 跳跃图固定教学顺序，较宽刺带按3.0身宽而非4.2身宽编排；忍者图收紧多余进出空白，最终使用高台、短刺、地面守卫和低台的两轮呼应。
- 玩家物理、人物、技能、金币轨迹算法、新机关类型均不变。遵照用户要求未运行测试/引擎，所有手感与可通过性仍待人工试玩。

### 金币轨迹采样

`PlayerMotionProfile.sample_jump_path()`按当前物理步长执行先更新速度、再积分位置，支持首跳顶点补二跳、起跳帧保留boost及空中衰减；返回相对脚底路径，下降到目标台高时插值截断。原有解析跳高和跨度接口保持不变。

`CoinTrajectory`先求能越过地刺或落入目标台面的起跳区间，再沿采样路径放置身体高度的金币；不拉伸抛物线、不局部抬高硬凑拱形。带台尾低身镖的跨台段采用滑铲动量参考；有坑中镖的间隙继续保留原不铺跨坑金币的策略。`jump_coin_arc.gd`让五个手工段的10组既有金币在加载时复用同一计算，不移动障碍。休息段和绳索引导不变。

按用户要求只改实现，未运行测试/引擎验证；不同操作时机下的收集体验待人工试玩。

下文保留原地图层说明；涉及枚举数量和默认候选池时，以本节及现行生成器为准：

最后更新：2026-09-22（绳索地图障碍排布重排为「波浪飞镖 → 波浪+上绳地刺 → 横排飞镖+地刺」三段递进；
绳索段布局层新增 `spacing` / `heights` 两个可选数据字段，`count` 上限 5 → 8；
未改动通用飞镖生成器、玩家机制与绳索机制。上一版：2026-09-16 飞镖衔接模型修掉两个盲区）

---

## 0. Map Module 层

正式关卡层级现为：

```
Arena / Route → Map Module → Section → Wave → Pattern → Obstacle
```

- `patterns/map_module_data.gd`：`MapModuleData` 数据资源，拥有 `module_id`、
  `display_name`、`theme`、`variant`、`difficulty` 和有序 `sections`。
- `components/map_module_chunk.gd`：同步构建全部 Section。Section 1 从 Module Entry
  开始，后续 Section 从上一 Section 的真实 Exit 开始；Module Exit 等于最后一个
  Section Exit，总长度为各 Section 实际长度之和。
- `patterns/library/Dart_Map_A.tres`：第一张正式 Map Module，包含
  `单双镖与斜线阶段 → 延迟二跳与上下门阶段 → 综合阶段` 三个 Section。
- `scenes/segment_darts.tscn` 仍占用旧 `ChunkKind.DARTS` 路由槽位，
  但现在只是 Map Module 的场景入口；Arena 继续按 Entry / Exit 接下一块内容。

`Dart_Map_A` 当前实测总长 `8035 px`，基础跑速 400 px/s 时约 `20.1s`；
三段长度为 3120 / 1995 / 2920 px，共 8 个 `Dart_Seg*` 段、43 枚飞镖。

---

### 0.1 飞镖 Wave 的正式调度

`Dart_Map_A` 现为 8,035 px：三个 Section（3120 / 1995 / 2920）、八个 `Dart_Seg*`，
43 枚飞镖，其中 24 枚 ACT。基础跑速 400 时 20.1 秒，持续 620 时 13.0 秒。

- `ObstaclePatternData.template = DART_WAVE` 代表一波有序的飞镖组合；
  `parameters.patterns` 中每一项是一个「动作句」，由
  `dart_pattern_library.gd` 展开成若干拍。
- `dart_pattern_library.gd` 是高度与节奏的唯一出处。高度从一段跳高度 `H1 = 184.5`
  等比推出：`LOW = 0.25 H1 = 46.1`、`MID = 0.50 H1 = 92.2`、
  `HIGH = 0.78 H1 = 143.9`、`TOP = 0.95 H1 = 175.2`，另有滑铲专用线
  `slide_height() = 66`。整条飞镖潮的垂直跨度收在 175 px 以内。
  9 种动作句：`LOW_PAIR` / `RISE` / `FALL` / `LOW_HIGH` / `HIGH_MID_LOW` /
  `DELAYED` / `SLIDE_ROW` / `RISE_THREE` / `HIGH_PAIR`。
  水平间距一律以 **px** 写在数据里（`INNER_GAP 110` / `ROW_GAP 102` /
  `TIGHT_LINK 115` / `NORMAL_LINK 150` / `BREATH 285` / `SWITCH_GAP 115` /
  `DELAYED_GAP 130` / `DELAYED_TAIL 100` / `FIRST_BEAT_PX 320`），
  由 `px_to_beat()` 换算；`ROW_GAP` 比 `INNER_GAP` 紧，是因为横排三枚要靠同一个滑铲盖住。
- `arrange()` 的间距语义是「上一 Pattern **实际末枚**的相遇 X → 本 Pattern 首枚的相遇 X」：
  `next_first_beat = prev_first_beat + span_of(prev) + px_to_beat(gap_px)`。
  用实际末枚而不是 Pattern 原点，Pattern 自身宽度的差异被完全吸收，
  「写进数据的空白」和「屏幕上的空白」是同一个数。
- `parameters.volleys`（每拍直接给 `beat` + `height`，或 `gap/gap_size` 墙口）
  继续支持，与 `patterns` 可以混用；飞镖墙的编译与校验逻辑保留未删。
- `pattern_compiler.gd` 将这种模板交给 `dart_wave_layout.gd`。
  编译器同步确定所有出生位置、发射时刻与速度；`beat × RUN_SPEED` 是固定相遇位置。
  同一拍上的多枚飞镖用 `heights` 数组表达（上下门），仍然只算一次遭遇。
  若编排的末拍超出声明的 `duration`，`effective_duration` 会自动延长
  （`EXIT_CLEARANCE + DURATION_EPSILON`，后者用于避开浮点边界），
  并把 `plan["length"]` 一起改写 —— 否则后续每一波都会左移。
- 复用 `PatternLayouts.dart` 产生飞镖事件，不复制飞镖障碍行为，
  不在 `game.gd` 添加地图特例。
- `PatternSection.advance` 对距离型 Wave 提前调用 `PatternRunner.advance_distance`；
  `elapsed = 玩家相对 Wave 的 X / RUN_SPEED`，支持入口之前的负发射时间。
- 飞镖在屏外自然进入，飞行随前进距离连续推进；加速不会让波次落后于玩家，
  不重新瞄准、不重定位，不画生成红圈。实际碰撞仍使用角色前后帧位置做扫掠检测。
- Wave 长度按显式 duration 编排，与屏外出生坐标无关；过尾后等待飞镖自然清理。
  旧 P01/P30 等时间型模板仍由原编译路径处理。

#### 衔接规则：ACT / SAFE 与两个合法带

本轮（2026-09-18）只调整 Pattern 的**出现间隔 / 高低衔接 / 连续组合**，
没有增删 Pattern，没有改飞镖 Scene、碰撞或伤害，也没有改角色物理，不引入随机。

飞镖按「玩家要不要做动作」分两类，只由高度决定：

- **SAFE** —— `h >= 站立身高 + 飞镖半径 = 77`，站着就能过。
  `MID(92.2)` / `HIGH(143.9)` / `TOP(175.2)` 都是 SAFE。
- **ACT** —— `h < 77`，站立会中招，玩家必须在它到达的那一刻处于
  「滑铲中」或「脚底离地 57px 以上」。`LOW(46.1)` 与 `SLIDE(66)` 是 ACT。

两个必须先量对的量：

- **一个滑铲覆盖多少地面**：`SLIDE_DURATION × SLIDE_BURST_SPEED = 0.58 × 620 = 359.6px`。
  不是 `0.58 × 400 = 232px` —— `player.gd::start_slide()` 会把 `boost_speed`
  设成 `SLIDE_BOOST = 220`，滑铲期间玩家实际以 620 px/s 前进。
- **一枚飞镖占多宽的身位**：`dart.gd` 用 `swept_shape` 做边缘到边缘检测，
  所以相遇点在 X 的飞镖实际占住 `[X - 34, X + 34]`，
  `contact_pad_px() = DART_RADIUS + PLAYER_WIDTH / 2 = 11 + 23 = 34px`。

于是「一簇 ACT 能不能被一个滑铲盖住」的判据是
`(X_last + PAD) - (X_first - PAD) <= cover`，即 `X_last - X_first <= cover - 2×PAD`。

| 带 | 判据 | 含义 |
|---|---|---|
| `CONTINUOUS` | ≤ `seam_continuous_max_px()` = 359.6 - 68 - 24 = **268px** | 一个滑铲同时盖住整簇，上一个动作的轨迹直接送进下一个 Pattern |
| `CLEAN` | ≥ `seam_clean_min_px()` = max(359.6 + 24, 282 + 80) = **384px** | 完整落地、重新判断、再做下一个动作 |
| 死区 | 268 ~ 384px | 两条路都不成立，接缝必须改间距或改顺序 |

`SEAM_SAFETY_PX = 24` 给两个带各留余量；`TAKEOFF_LEAD_PX = 80` 是起跳预备。
`act_gap_band()` 做分类，`cluster_violations()` 逐波检查，
`map_act_report()` 做全图体检（返回 `issues` / `notes` / `acts` / `tightest`）。

三层验证：

| 层 | 位置 | 行为 |
|---|---|---|
| 逐波 | `dart_wave_layout.gd::_measure_seams()` | 每个 Wave 的接缝分类，死区进 `plan.notes` |
| 全图 | `components/map_module_chunk.gd::_check_act_continuity()` | 汇总所有 Section 的飞镖，`push_error` 报 issue、`push_warning` 报 note；结果落在 `act_report` |
| 回归 | `tests/godot/dart_map_module_regression.gd` | 断言 `act_report.issues` 与 `notes` 均为空 |

当前全图实测：`43 枚飞镖 / 24 枚 ACT / issues=0 / notes=0`。

配套的角色改动只有一处：`player.gd::consume_buffered_jump()` 增加了
`elif jumps_used == 0: start_jump(JUMP_SPEED)` 分支。玩家没有按过跳跃键却被
被迫进入空中时（走下高台、被击退、土狼时间过期），以前会彻底失去空中控制权；
现在仍然给一次完整起跳，之后还能接二段跳。跳跃常量、跑速与其余角色逻辑未改。

当前验证入口（2026-09-18 更新）：

| 工具 | 用途 | 当前状态 |
|---|---|---|
| `tests/godot/dart_pattern_linkage_check.gd` | 相邻 Pattern 的实际间隔与衔接报告 | 通过（7 处接缝，最紧 RISE → LOW_PAIR） |
| `tests/godot/dart_map_module_regression.gd` | 模块接线、长度/时长、全图 ACT 衔接断言 | 通过（8035 px / 20.1s，issues=0 notes=0） |
| `tests/godot/dart_map_reachability.gd` | **不依赖试玩 AI** 的解析式可解性扫描 | 通过：存在一条不受伤的轨迹 |
| `tests/godot/dart_map_solvability_probe.gd` | 逐帧最小姿态修正求解器（用真实命中判据） | 通过：`SOLVABLE: 无伤通过`（damage=0） |
| `tests/godot/dart_map_playtest.gd` | 正式角色输入实跑（反应式驱动器） | **仍受伤 5 次，属驱动器能力问题** |

> **交付判据（重要）**：`dart_map_playtest.gd` 是**反应式**驱动器 —— 它只看眼前的
> 飞镖决定动作，不做离线规划，因此会踩中「该提前起跳 / 该连滑」的题。
> 三个独立的**求解器**（reachability 解析扫描、solvability probe 逐帧求解、
> 回归里的 ACT 覆盖带断言）都判定关卡可无伤通过，所以实跑失败**不能**作为
> 关卡交付判据。完整的调查过程、我在这一轮自己犯的错、以及建议的驱动器
> 改造方向（反应式 → 离线规划式）见 `docs/DART_MAP_PLAYTEST_FINDINGS.md`。
>
> 另注：该驱动器的 `SLIDES` 一行曾印 `actual=0` 造成误读 —— `slide_count`
> 只在 `try_boost()` 里累加，而 `try_boost()` 受 `boost_enabled`（默认 `false`）
> 控制，所以 boost 路线关闭时它恒为 0。已改为打印 `inputs` 与 `boost_path` 两个量。

结果、速度条件和截图见 `tests/DART_MAP_VALIDATION.md`。下文旧单 Section / Dart_Introduction 细节仅适用于旧模板路径。
### 0.2 跳跃地图的正式调度

`Jump_Map_A` 是完整地图“踏石 · 棘林”，由三段跳跃内容组成。
`ChunkKind.JUMP_MAP` 对应 `CHUNK_SCENES[13]` 与 `scenes/segment_jump_map.tscn`，
直接复用 `MapModuleChunk`。每轮五张完整地图按种子换序，跳跃图的路由位置随之变化。

`JUMP_WAVE` 由 `jump_wave_layout.gd` 编译：有序 `parameters.phrases` 支持单刺、双刺、
单柱、连柱、刺柱组合五种 Pattern，产生静态 `SpikeStrip` / `JumpPillar` 事件。
宽度、柱高、间距来自 `PlayerMotionProfile`；所有 Wave 同步预编排，距离型 Runner
提前约 979 px 生成障碍，结束后回收。柱顶可站立，柱侧阻挡，地刺沿用原伤害与可破坏机制。
当前 NORMAL / difficulty 1，不改变角色物理，也不把旧 `Jump_A` 的短 Section 搬成整图。

复用规则见 `docs/JUMP_MAP_TEMPLATE.md`；验证入口为 `jump_map_module_check.gd` 和
`jump_map_playtest.gd`。`tests/jump_map/JumpMapPractice.tscn` 只覆盖路线选择，复用正式驱动。

### 0.3 绳索地图的正式调度（2026-09-22 重排障碍排布）

`Rope_Map_A`「悬丝 · 回风」是第三张正式地图，挂在 `ChunkKind.ROPE_MAP` →
`scenes/segment_rope_map.tscn` → `components/rope_map_chunk.gd`，同样复用
`MapModuleChunk`。`route[3]` 是绳索地图（SAFE → DARTS → JUMP_MAP → ROPE_MAP）。

玩家挂在一条横绳上，可翻到绳上侧或下侧；绳索段的设计主题是
**用飞镖与地刺引导玩家在上下两侧持续切换**。当前重排为三段递进：

| Section | 内容 | 绳索 |
|---|---|---|
| 一 · 起波翻面 | 波浪飞镖，一次 / 反向 / 连续两次切换 | Rope 1–3 |
| 二 · 棘影长弦 | 波浪飞镖 + 上绳地刺（先短后长），末尾短呼吸 | Rope 4–6 |
| 三 · 横排封锁 | 横排飞镖（封锁整条路线）与地刺连续错位，金币收尾 | Rope 7–11 |

`ROPE_WAVE` 由 `patterns/rope_wave_layout.gd` 编译，`parameters.gates` 是有序动作组：

```text
kind        darts / spikes / mixed_flip / jump
beat        秒；世界 X = beat × RUN_SPEED
safe_side   0 = 玩家留在绳上侧，1 = 留在绳下侧（飞镖与地刺落在 1 - safe_side 一侧）
count       连镖枚数（0~8）
spacing     连镖之间的秒数（0.06~0.40，默认 BURST_INTERVAL）
rows        1 / 2 层
heights     每一枚飞镖的高度比例，取绝对值，正负跟随被封锁侧 —— 波浪用
width_ratio 地刺宽度倍率
```

`spacing` 与 `heights` 是 2026-09-22 新增的**绳索段布局层数据**，
用来表达两种设计语言，**没有改动通用飞镖生成器 `dart_pattern_library.gd`**：

- **横排飞镖** —— 同一高度、`spacing` 收紧到 0.11s，连镖读成一整条，语义是
  「这条路线现在不能走」。
- **波浪飞镖** —— `heights` 给每一枚飞镖各一个高度，`spacing` 放到 0.22s，
  连镖读成一条斜线；斜线跨过绳线的那一刻就是玩家翻面的时刻，
  语义是「这一侧正在被占满，切到另一侧」。

高度比例 1.0 = 一个玩家身高（66px）。绳线两侧各只有 ±66px 是有效威胁带：
`|h| > 77` 的飞镖在任何一侧都碰不到玩家（只是装饰），`h ≈ 0` 会同时命中两侧
（不是可读的题），所以波浪只在这个带内取值，不穿过绳线放置飞镖。

`rope_map_chunk.gd` 负责在地图两端之间建一条连续绳索，并在建图时用
`RopeWave.validate_route()` 跨 Wave 复核「相邻上下威胁之间是否留出了完整翻绳窗口」。
`validate_route` 的判据是 `(current.danger_start - previous.danger_end) / SLIDE_BURST_SPEED
>= rope_flip_window()`，`danger_start/end` 由动作组的 `beat`、`count`、`spacing`
与地刺宽度共同决定 —— 改 `spacing` 或 `count` 时必须同时复核这个窗口。

验证入口：`tests/godot/rope_map_playtest.gd`（正式角色实跑，SAFE → ROPE_MAP → FINISH）。
当前实测：`20640 px / 51.6s / 92 枚障碍 / 18 次翻绳 / damage=0 / screen_spawns=0`。

## 1. 正式关卡调用链

### 完整地图库的新增模块

- `Platform_Dart_Map_A` → `segment_platform_dart_map.tscn` → `PLATFORM_DART_WAVE`：
  `platform_dart_wave_layout.gd` 将可落脚跳台、台间坑和相对台面高度的飞镖编成连续动作。
  使用现有 `MapModuleChunk` 跨 Wave 挖坑，落点和飞镖交会点固定在地图坐标上。
- `Ninja_Map_A` → `segment_ninja_map.tscn` → `NINJA_WAVE`：
  `ninja_wave_layout.gd` 将不同高度的忍者跃入和地刺编成有序动作；运行时继续由距离推进。
  `leaping_ninja.gd` 负责从屏幕右侧进入、落地站定及玩家靠近后的单次挥刀。
- `PatternRunner` 在设置事件位置与参数后调用障碍的可选 `initialize(player)`，
  再发出 `event_spawned`。忍者在这一步确定右侧入口和固定落点。
  后续运动、碰撞和清理仍走障碍自己的 `advance`。
- `RhythmRouteGenerator` 将飞镖、跳跃、绳索、跳台飞镖和忍者五张地图按种子换序，
  分布在前两组的五个位置。`CONTENT_PROFILES` 保存对应完整模块 ID，供后续内容选择使用。
  没有新增无限竞技场排列算法。

两个独立练习场景位于 `tests/platform_dart_map/` 和 `tests/ninja_map/`，均复用正式角色、
HUD 和游戏驱动。`expanded_maps_chain_playtest.gd` 检查两张新地图双向直接拼接。

```
project.godot  (run/main_scene = res://test_world.tscn)
  └─ test_world.tscn : TestWorld(Node2D, game.gd)
        ├─ Background
        ├─ Player (player.tscn @ 140,460)
        ├─ DynamicCamera (dynamic_camera.gd)
        └─ HUD (旧版 Panel/Title/HudText/Help/Message/Skills…)
              └─ _ready() 中 hide_old_test_hud() 隐藏除 Message 外的全部旧 HUD

game.gd  ← 唯一的正式关卡驱动器
  ├─ const ROUTE_GENERATOR_SCRIPT = preload("res://components/rhythm_route_generator.gd")
  ├─ const Combat = preload("res://components/player_combat.gd")
  ├─ const CHUNK_SCENES : Array[PackedScene]     # 14 项，索引即协议
  │
  ├─ _ready()
  │     ├─ ensure_hud()
  │     ├─ setup_combat()        # 连接 ninjutsu_requested / fireball_requested / died
  │     ├─ setup_hud() / setup_sword_visual()
  │     ├─ reset_route_generator()   # seed = route_seed 或 Time.get_ticks_usec()
  │     └─ spawn_chunks_ahead(CHUNK_AHEAD)
  │
  ├─ next_chunk_kind()          # route_steps 用尽时 → route_generator.build_cycle(route_cycle)
  ├─ spawn_chunk()
  │     ├─ CHUNK_SCENES[index].instantiate()
  │     ├─ 对齐：新 chunk 的 Entry 落在 next_chunk_entry
  │     ├─ next_chunk_entry = exit.global_position
  │     ├─ connect player_contact / coin_collected
  │     └─ 隐藏该 chunk 的 Hint
  ├─ cleanup_chunks()           # 玩家身后回收
  └─ _physics_process()
        ├─ spawn_chunks_ahead(player.x + CHUNK_AHEAD)
        ├─ cleanup_chunks()
        ├─ combat.advance(delta)
        └─ 每个 chunk 若存在 advance(delta, player) 则调用
```

关键常量（`game.gd`）：

| 常量 | 值 | 含义 |
|---|---|---|
| `START_POSITION` | `Vector2(140, 460)` | 出生点 |
| `CHUNK_AHEAD` | `2200.0` | 向前预生成距离 |
| `CHUNK_CLEAN_BEHIND` | `700.0` | 向后回收距离 |
| `ENERGY_MAX` | `100.0` | 忍术能量上限 |
| `DEFAULT_COIN_ENERGY` | `10.0` | 旧金币未定义 `coin_energy` 时的兜底值 |
| `FALL_DEATH_Y` | `900.0` | 坠落死亡线 |
| `DESTRUCTION_SCORE` | `15` | 摧毁可破坏物得分 |

---

## 2. 路线生成器 `components/rhythm_route_generator.gd`

```gdscript
class_name RhythmRouteGenerator extends RefCounted
```

- `enum ChunkKind`（14 项）：
  `SAFE, SINGLE_JUMP, DOUBLE_JUMP, SLIDE_INTRO, REST, ROPE, MIXED,
   TRIPLE_JUMP, SLALOM, ROPE_SWITCH, COMBO, FINISH, DARTS, JUMP_MAP`
- `enum Rhythm { REGULAR, RANDOM, SWING }`
- `GROUP_COUNT = 3`，`ENCOUNTERS_PER_GROUP = 3`
- 遭遇池：
  - `REGULAR_ENCOUNTERS = [SINGLE_JUMP, DOUBLE_JUMP, SLIDE_INTRO]`
  - `SWING_ENCOUNTERS = [SINGLE_JUMP, COMBO, SLIDE_INTRO]`
  - `RANDOM_ENCOUNTERS = [DOUBLE_JUMP, MIXED, TRIPLE_JUMP, SLALOM, ROPE, ROPE_SWITCH, COMBO]`

### 2.1 `build_cycle(cycle_index)`

```
route = [SAFE]
map_order = 按种子打乱 [DARTS, JUMP_MAP, ROPE_MAP, PLATFORM_DART_MAP, NINJA_MAP]
for group_index in GROUP_COUNT:            # 3 组
    append_rhythm_group(route, 随机 rhythm, random)
    if group_index == 0:
        route[1:4] = map_order[0:3]
    if group_index == 1:
        route[5:7] = map_order[3:5]
    route.append(FINISH if 最后一组 else REST)
```

**每个 cycle 的骨架永远是：**

```
SAFE → 3×换序完整地图 → REST → 2×换序完整地图 → 1×挑战 → REST → 3×挑战 → FINISH
```

### 2.2 组生成规则

| 函数 | 行为 |
|---|---|
| `append_regular_group` | 在 `REGULAR_ENCOUNTERS` 上取随机起点，循环取 3 个（可重复） |
| `append_random_group` | `RANDOM_ENCOUNTERS.duplicate()` 后不重复地弹出 3 个 |
| `Rhythm.SWING` 分支 | 直接 `append_array(SWING_ENCOUNTERS)`，固定顺序 |

### 2.3 种子

`game.gd` 的 `reset_route_generator()`：`seed = route_seed`（非零时）否则
`Time.get_ticks_usec()`。因此默认每次启动 / 按 R 重开换新路线；
把 `route_seed` 设为非零整数即可复现。

---

## 3. `CHUNK_SCENES` 14 项映射（`game.gd`）

| index | ChunkKind | 场景 | 长度 / 练习内容 |
|---|---|---|---|
| 0 | SAFE | `scenes/segment_safe.tscn` | 1200px，无障碍热身（含金币） |
| 1 | SINGLE_JUMP | `scenes/segment_single_jump.tscn` | `SectionChunk` + `Jump_A.tres`，四波单跳节奏与中场喘息 |
| 2 | DOUBLE_JUMP | `scenes/segment_double_jump.tscn` | 两次落地跳（非空中二段跳） |
| 3 | SLIDE_INTRO | `scenes/segment_slide_intro.tscn` | 滑铲通过横梁 |
| 4 | REST | `scenes/segment_rest.tscn` | 无障碍恢复 |
| 5 | ROPE | `scenes/segment_rope.tscn` | 2600px，绳下跟金币，出口自动上翻 |
| 6 | MIXED | `scenes/segment_mixed.tscn` | 跳跃 + 落地 + 滑铲 |
| 7 | TRIPLE_JUMP | `scenes/segment_triple_jump.tscn` | 1600px，三次落地跳，间距 360px |
| 8 | SLALOM | `scenes/segment_slalom.tscn` | 1800px，跳 → 铲 → 跳 |
| 9 | ROPE_SWITCH | `scenes/segment_rope_switch.tscn` | 2600px，下 → 上 → 下 → 上 |
| 10 | COMBO | `scenes/segment_combo.tscn` | 1800px，跳越相邻双障碍 + 铲 + 跳 |
| 11 | FINISH | `scenes/segment_finish.tscn` | 1200px，收尾休息 |
| 12 | DARTS | `scenes/segment_darts.tscn` | `Dart_Map_A` Map Module，3 个 Section，29280px |
| 13 | JUMP_MAP | `scenes/segment_jump_map.tscn` | `Jump_Map_A` Map Module，3 个 Section / 8 波，28800px |

> **索引越界守卫**：`game.gd` 约 786 行处，
> `kind < 0 or kind >= CHUNK_SCENES.size()` 会 `push_error` 并拒绝生成。

### 3.1 未参与默认路线的场景（残留）

| 场景 | 状态 |
|---|---|
| `scenes/segment_spikes.tscn` | 保留，不参与默认路线 |
| `scenes/segment_slide.tscn` | 保留，不参与默认路线 |

`scenes/` 下另有独立组件场景：`Coin.tscn`、`Spike.tscn`、`SlideBeam.tscn`。

---

## 4. Segment 运行时契约

### 4.1 结构契约

每个 `scenes/segment_*.tscn`：

- 根节点是 `Node2D`，挂 `components/chunk.gd`（`class_name Chunk`）
- 必须包含 `Entry` 与 `Exit` 两个 `Marker2D`
- 对齐完全靠这两个标记的**全局位置**，不靠场景长度

### 4.2 信号契约（`components/chunk.gd`）

```gdscript
class_name Chunk extends Node2D

signal player_contact(player: Node2D, damage: float)
signal coin_collected(score: int, energy: float)

func _ready() -> void:
    for node in find_children("*", "", true, false):
        if node.has_signal("player_contact"):
            node.connect("player_contact", relay_player_contact)
        if node.has_signal("collected"):
            node.connect("collected", relay_coin_collected)
```

`_ready()` **递归连接全部后代**的 `player_contact` 与 `collected`，
统一转发为 `player_contact(player, damage)` / `coin_collected(score, energy)`。

`components/dart_encounter.gd` 通过 `extends "res://components/chunk.gd"`
使自己**本身就是一个 Chunk**。

### 4.3 段内常规节点

| 节点 | 约定 |
|---|---|
| `Spike` | 地面 Y = 460 |
| `SlideBeam` | Y = 0 |
| `Coin` | 发 `collected` |
| `Area2D`（group `rope`） | 绳索；子 `Spike` 的 Y = 0，绳下侧用 `scale = Vector2(1, -1)` |
| `Hint` | 中文提示 Label，正式运行时被隐藏，F1 调试面板显示 |

---

## 5. 障碍与交互组件

| 文件 | 类 | 关键行为 |
|---|---|---|
| `components/spike.gd` | `Spike` | damage 12；group `hazard` + `destructible` |
| `components/slide_beam.gd` | `SlideBeam` | damage 8；仅当 `not body.is_sliding()` 才结算 |
| `components/coin.gd` | `Coin` | score 10，energy 2，发 `collected` |
| `components/dart.gd` | — | 飞镖本体：沿移动路径检测碰撞，避免高速穿透 |
| `components/section_chunk.gd` | `SectionChunk extends chunk.gd` | 通用数据驱动 Segment Shell；同步构建 `PatternSection`、重定位 Exit、转发 advance，并提供 Theme/Variant/Wave/Pattern/Difficulty 调试信息 |
| `components/dart_encounter.gd` | `extends map_module_chunk.gd` | 为 Map Module Shell 配置 `Dart_Map_A.tres` |
| `components/single_jump_encounter.gd` | `extends section_chunk.gd` | 为通用 Shell 配置 `Jump_A.tres` / `Jump_A`；SINGLE_JUMP 不再手摆障碍 |
| `components/combat_target.gd` | — | 静态工具 `available/center/swept_hit/swept_shape/destroy` |
| `components/player_combat.gd` | — | 技能编排（冷却、斩击、**环绕火球槽位**、生成投射物） |
| `components/ability_projectile.gd` | — | **已发射的**投射物飞行 / 追踪 / 命中 / 回收；`Kind { RASENGAN, FIREBALL }`；`initial_target` 让武器技能发射出的火球一出生就进入飞行态 |
| `components/orbit_fireball.gd` | — | **环绕火球槽位**（`OrbitFireball`）：挂在角色周围、常驻、负责旋转与绘制；开火时机由 `PlayerCombat` 统一控制，槽位被轮到时射出一颗独立投射物，发射后自己继续留在原位 |

### 5.0 武器主动技能：三颗环绕火球 + 每轮一颗（2026-09-11 修正，2026-09-12 调整射速）

正式设计要求是「角色周围**始终维持三个环绕火球槽位**；其中一颗向目标发射后，
发射出的火球脱离角色成为独立攻击弹，原位立刻补上新的环绕火球」。

两次修正分别解决两个不同的问题：

**修正一（2026-09-11）——环绕数衰减。**
`cast_fireballs()` 直接生成 3 个 `AbilityProjectile`，每个只环绕 `ORBIT_TIME`（0.55s）
就自我发射一次，**发射后不会补充**。于是环绕数 3→0 衰减，
屏幕上「总共只有三颗火球」。

**修正二（2026-09-12）——射速放大成弹幕。**
修正一之后，开火节奏是「**每个槽位各自** 0.18s 冷却」，
三个槽位互不同步地同时倾泻：
`3 槽位 ÷ 0.18s ≈ 16.7 发/秒`，同屏攻击火球峰值达到 13 颗，
6 秒技能期内发射 15 颗只用了 2 秒 —— 试玩观感是「一次性发射大量弹幕火球」。
现在改为**全队共享一个开火节奏**：`FIREBALL_LAUNCH_INTERVAL = 0.42s`，
每轮由**轮转到的那个槽位**射出**一颗**火球（`fire_round()` / `fireball_launch_cursor`）。

修正后的结构：

| 概念 | 类型 | 行为 |
|---|---|---|
| 环绕火球（槽位） | `orbit_fireball.gd` | 常驻 3 个，`orbiting_fireball_count()` 恒为 3；只负责旋转、绘制与「被轮到时发射一颗」 |
| 攻击火球（投射物） | `ability_projectile.gd` | 发射后独立飞行 / 追踪 / 命中 / 生命周期 / 世界清理 |
| 开火节奏 | `player_combat.gd` | 全队共享的 `fireball_launch_cooldown`，与环绕数量无关 |

**射速约定（长期）**：实际射速 = `1 / FIREBALL_LAUNCH_INTERVAL`，**不是** `FIREBALL_COUNT / 间隔`。
要调射速只改 `FIREBALL_LAUNCH_INTERVAL`；不要把冷却放回槽位内部，
否则会再次退化为 `FIREBALL_COUNT` 倍弹幕。

不变量（由 `tests/godot/fireball_skill_regression.gd` 断言）：

```
技能激活后 orbit = 3
发射一次后 orbit = 3
连续发射多次后 orbit = 3
每轮只射出一颗（2s 窗口内约 2 / FIREBALL_LAUNCH_INTERVAL 颗，±2 帧误差）
射速不随环绕数量放大（上限断言，防止退回弹幕行为）
同屏 projectile 峰值有界（<= 6）
技能结束后停止发射并清空环绕视觉
已发射的 projectile 按自己的生命周期走完并被回收
restart 后 orbit / projectile / launched / cooldown 全部清零
```

技能持续 6.0s（`FIREBALL_DURATION`），冷却 8.0s（`FIREBALL_COOLDOWN`）。
按 `FIREBALL_LAUNCH_INTERVAL = 0.42s` 计算，单次技能期共射出约 **14 颗**火球。

**实测（2026-09-12，目标持续补充的探针环境）**：

```
6s 内共射出 13 颗（理论 14）
相邻两颗间隔 0.43s（个别 0.48–0.50s，来自目标瞬时不足的重试）
orbit 区间 [3, 3]（技能期内恒为 3）
同屏攻击火球峰值 4
```

两个实现细节（本轮同时修掉）：

- **爆炸收尾用 `exploding` 布尔量**，不用 `explosion_remaining > 0` 判断——
  倒计时恰好落到 0.0 的那一帧会有状态歧义。
- **目标认领跳过「爆炸中的弹」**：`_is_claimed()` 只统计仍在飞行的弹，
  否则几轮之后射程内的目标全被在途弹「占位」，开火会莫名停摆。
  同时保留兜底：没有空闲目标时打最近的——开火节奏优先于目标独占。

### 5.1 `dart_encounter.gd` 参数

该文件**已不再是手写波次系统**（旧版 `Pattern { GAP, FAN, STAGGER, AIMED }` /
`WAVE_*` / `MAX_DARTS` / `build_pattern()` 已全部删除），
也不再持有 `SECTION_DATA` / `SECTION_START_INPUT_CLEARANCE` /
`SECTION_DIFFICULTY` / `SECTION_MODIFIER` 那批常量。

**现在整个文件只有 4 行** —— 它退化成一个纯粹的「接哪张图」声明：

```gdscript
extends "res://components/map_module_chunk.gd"

func _init() -> void:
	module_data_path = "res://patterns/library/Dart_Map_A.tres"
```

Section 的构建、长度推导、Entry/Exit 对齐、ACT 衔接体检全部由父类
`components/map_module_chunk.gd` 完成，`dart_encounter.gd` 不再有任何自己的逻辑。
`rope_map_chunk.gd` 用同样的方式复用父类。

关键实现约束（**改这里之前先读**）：
`_build_sections()` 必须在 `_ready()` 里**同步**执行。
`game.gd.spawn_chunk()` 在 `add_child()` 之后立刻读 `exit.global_position`
作为下一个 chunk 的对齐点；一旦改回 `call_deferred()`，
`Exit` 会在下一帧才移动，下一个 Segment 就会直接叠在本段起点上。

---

## 6. Pattern 工作台完整结构（`patterns/**`）

> 这一整套是**独立的人工编排障碍生产工具**。

### 6.1 数据层

| 文件 | 职责 |
|---|---|
| `obstacle_pattern_data.gd` | `@tool class_name ObstaclePatternData extends Resource`。字段：`pattern_name`、`display_name`（人类可读名，F1 优先显示）、`template`（`@export_enum("CUSTOM", "P01", "P04", "P08", "P14", "P15", "P16", "P17", "P18", "P21", "P22", "P24", "P28", "P30")`）、`difficulty`(1–5)、`duration`、`length`、`start_delay`、`tags`、`mirror`、`speed_multiplier`、`supports_mirror/speed/reverse`、`needs_manual_playtest`、`instruction`、`parameters: Dictionary`、`events: Array[PatternEvent]`、`pit_ranges: Array[Vector2]`、`final_pattern: ObstaclePatternData` |
| `pattern_event.gd` | `PatternEvent extends Resource`。`PreviewKind {SPIKE, DART, CEILING, OTHER}`；`obstacle_scene`、`position_offset`、`spawn_time`、`speed`、`direction`（默认 LEFT）、`optional_parameters`、`preview_kind`、`preview_size` |
| `pattern_section_data.gd` | `@tool class_name PatternSectionData extends Resource`。字段：`section_name: String`、`entries: Array[Resource]`（元素为 `ObstaclePatternData` 或 `RecoverySection`）、`stages: PackedStringArray`、`stage_entries: PackedInt32Array`。`stage_for(entry_index)` 按累计计数把 entry 映射到 Phrase 阶段名（见 §6.8） |
| `recovery_section.gd` | `@tool class_name RecoverySection extends Resource`。`@export_range(0.5, 2.0, 0.1) duration := 1.0`；`distance(run_speed) = duration * run_speed` |

### 6.2 生产层

| 文件 | 职责 |
|---|---|
| `pattern_layouts.gd` | `PatternLayouts.build(data, level)` 大 `match data.template`，产出 `{events, pits, gaps, recoveries, notes, issues}`。辅助 `spike()` / `ceiling()` / `dart(time, distance, height, speed, direction)`。内嵌运动数学：P08 用 `RUN_SPEED * (fast_fall_time(jump_height()) + 0.14)`；P21/P22/P24 计算飞镖接触点；P28 用 `append_rhythm` |
| `pattern_walls.gd` | `gap_size()` 随 level 缩放；`ROW_SPACING = 28`，`MIN_HEIGHT = 14`，`MAX_HEIGHT = 310`；构造竖直飞镖墙 + 唯一安全缝隙（`gap.rect`） |
| `pattern_compiler.gd` | 编译与校验（见 §6.4） |
| `pattern_modifier.gd` | 变体（见 §6.5） |
| `pattern_runner.gd` | `PatternRunner extends Node2D`；`MAX_OBSTACLES = 96`；`configure(plan, target)`；`advance(delta)` 按 `spawn_time` 生成、推进、`finish()` 清理；`_draw()` 画 ≤0.8s 的橙色出生预警；`on_player_contact` 仅在 `player.active` 时结算伤害 |
| `pattern_section.gd` | `PatternSection extends Node2D`；`build()` 遍历 entries，`RecoverySection → add_ground`，`ObstaclePatternData → compile + Runner + build_ground`；累计 `section_length`；每个 Pattern 用**自己数据里的 `difficulty`**（兜底用传入值）；`advance(delta, player)` 在玩家越过 `runner.x + plan.length` 后 `finish()`。另有面向 F1 覆盖层的 `pattern_info` / `info_at()` / `template_sequence()` / `all_issues()`。`player` 允许为 null（同步编译时用） |
| `pattern_library.gd` | 菜单 `NAMES` 列表与 `load_pattern(index)` |
| `pattern_preview.gd` | `@tool PatternPreview`，编辑器内绘制边界 / 身体带 / 事件 / 移动缝隙 / 坑 / 恢复窗口 / 参考单跳弧线 |

### 6.3 资源库 `patterns/library/`

12 个模板资源 + `Recovery.tres` + `ExampleSection.tres`：

```
P01_SingleSpike.tres      P15_TopGap.tres        P22_GapCeiling.tres
P04_SingleShuriken.tres   P16_BottomGap.tres     P24_WallLandingTrap.tres
P08_HighLow.tres          P17_GapSwitch.tres     P28_RhythmBurst.tres
P14_MiddleGap.tres        P18_Diagonal.tres      P21_SpikeShuriken.tres
Recovery.tres             ExampleSection.tres
```

`ExampleSection.tres` = `P01 → Recovery → P08 → Recovery`。
`P28_RhythmBurst.tres` 通过 `final_pattern` 引用 `P14_MiddleGap.tres`
（不允许再引用 P28，防止循环）。

**DARTS 专用资源（当前，2026-09-18）** —— `Dart_Map_A` 是 Map Module 入口，
下挂三个 Section，每个 Section 三个 entry：

```
Dart_Map_A.tres                 ← MapModuleData（模块本体，theme=DARTS variant=A）
Dart_Map_A_Section1.tres        PatternSectionData  一 · 进入与高度判断
  Dart_Seg1_Entry.tres            DART_WAVE  上升斜线 + 低位双镖 + 下降斜线
  Dart_Seg2_Breath1.tres          DART_WAVE  第一次短呼吸（低位双枚）
  Dart_Seg3_HeightJudgement.tres  DART_WAVE  低位双镖 → 高位双镖 → 高到低斜线
Dart_Map_A_Section2.tres        PatternSectionData  二 · 延迟二跳与滑铲
  Dart_Seg4_DelayedJump.tres      DART_WAVE  低低 → 高高 → 顶位（延迟二段跳）
  Dart_Seg5_Slide.tres            DART_WAVE  滑铲横排三枚
  Dart_Seg6_SlideToJump.tres      DART_WAVE  滑铲后立刻起跳（上升斜线）
Dart_Map_A_Section3.tres        PatternSectionData  三 · 第二呼吸与高潮
  Dart_Seg7_Breath2.tres          DART_WAVE  第二次短呼吸
  Dart_Seg8_Climax.tres           DART_WAVE  下降 → 上升 → 低低 → 高高 → 滑铲三连
  Dart_ExitRecovery.tres          Recovery    出口喘息（duration 1.4s）
```

**上一代 DARTS 资源（已不在默认路线）** —— `Dart_Introduction.tres` 单 Section
设计，7 stage / 10 entry，`Dart_Scene1_Intro` … `Dart_Scene6_ClimaxWall`，
12909 px / 32.3s。文件保留在库里，只作为 `stages` 写法样例与历史对照。

为可读性做的两件事：

1. **人类可读名称**：每个 Pattern / Section / Recovery 都有 `display_name`，
   F1 覆盖层优先显示它，内部编号放在括号里（如 `齐胸飞镖接高位飞镖 (P30)`）。
   报告与人工反馈因此可以直接说「第二个飞镖墙太简单」而不必记编号。
2. **消灭无意义空白**：`PatternCompiler` 现在按「最后一个威胁真正结束的时刻」
   推导 `plan.length`，`duration` / `length` 退化为**可选地板**。
   旧实现里 `duration` 默认 4.0s 会把只有一枚飞镖的模板强行拉到 1800px，
   这一段曾因此有 5680px（14.2s）的纯跑动空白。

本段唯一的 Variation 只改**一个**主因子：

| 资源 | 相对基准改了什么 | 玩家解法变化 |
|---|---|---|
| `Dart_Scene4_HighGap` | 只改 `safe_gap_position` 110 → 150 | 安全口从中位抬到更高处，进入时机更靠单跳顶点 |

模板 → `parameters` 键一览：

| 模板 | parameters |
|---|---|
| P01 单刺跳 | `spike_width`、`position`、`warning_distance` |
| P04 单飞镖 | `height`、`speed`、`direction`、`spawn_distance` |
| **P30 飞镖动作句** | `speed`、`darts: [{height, delay, distance}]` |
| P08 高低切换 | `spike_width`、`position`、`ceiling_clearance` |
| P14/P15/P16 安全口 | `safe_gap_size`、`safe_gap_position`、`wall_speed`、`spawn_distance` |
| P17 安全口换位 | `wall_count`、`wall_interval`、`gap_positions`、`wall_speed`、`gap_size` |
| P18 斜线飞镖 | `count`、`height`、`height_step`、`x_spacing`、`spawn_distance`、`speed` |
| P21 地刺+飞镖 | `position`、`spike_width`、`height`、`speed` |
| P22 坑+顶部飞镖 | `position`、`pit_width`、`height`、`speed` |
| P24 墙+落点陷阱 | `safe_gap_size`、`safe_gap_position`、`wall_speed`、`spawn_distance`、`landing_time_ratio`、`spike_width` |
| P28 节奏组合 | `first_interval`、`pause_duration`、`speed`、`spawn_distance`；+ `final_pattern` |
| **P30 飞镖动作句** | `speed`；`darts: Array[Dictionary]`，每项 `{height, delay, distance}` |

#### P30 —— 飞镖动作句（Dart Sentence）

P04 只发射**一枚**飞镖，前后必然留下空白，玩家体验是「跑 → 一个障碍 → 跑」。
P30 把**若干枚飞镖编排成一句话**：后一枚飞镖出现时，玩家仍在处理前一枚引发的动作
（起跳 / 下落 / 换高度），因此感受到的是一个连续的小场面。

数据结构：

```gdscript
parameters = {
  "speed": 200.0,
  "darts": [
    {"height": 74.0, "delay": 0.0,  "distance": 720.0},   # 齐胸高度
    {"height": 165.0, "delay": 1.59, "distance": 372.0},  # 高位
  ],
}
```

**关键公式与易错点**：相遇时刻 = `delay + distance / RUN_SPEED`。
因此两枚飞镖的**相遇间隔** = `Δdelay + Δdistance / RUN_SPEED`。
只调 `delay` 而不调 `distance`，相遇间隔会被 `distance` 的增量顶大，
动作句就退化成「两道相距很远的独立题目」。
编译器与设计工具都以**相遇间隔**为判据（应落在 1.5 × 单跳周期内）。

同时必须满足 `MIN_REACTION_TIME`：每枚飞镖的反应窗口
`distance / (RUN_SPEED + speed) >= 0.45s`。
高潮段要「更密」时应当**提高 `speed`**，而不是压缩反应窗口。

#### 6.3.1 动作句与 Pattern 衔接规则（2026-09-18 重写）

> **当前规则在 §0.1「衔接规则：ACT / SAFE 与两个合法带」。** 本节只描述
> `DART_WAVE` 这一层的数据形状与编译器行为；衔接判据已从「模型算最小值」
> 改成「像素间距落在哪个覆盖带」，下面「历史」一节保留旧模型供追溯。

`P30` 之上还有一层：**`DART_WAVE` 模板**。一段 `DART_WAVE` 声明一个
`patterns: Array`（「动作句」列表）；`dart_pattern_library.gd` 把每个动作句
展开成若干 **volley（拍）**，`dart_wave_layout.gd` 再把相邻动作句按间隔排布。
真正决定「上一个 Pattern 的玩家轨迹能不能自然进入下一个」的，是这一层。

**九个动作句种类**（`expand()` 的输入语义）：

| 种类 | 展开方式 | 玩家要做的事 |
|---|---|---|
| `LOW_PAIR` | 低位双枚横排（`ROW_GAP`） | 起跳 |
| `RISE` | 低 → 中 → 高上升斜线（`DIAGONAL_GAP`） | 起跳后继续升（只有首枚是 ACT） |
| `FALL` | 高 → 中 → 低下降斜线 | 等高度落下来（只有末枚是 ACT） |
| `LOW_HIGH` | 低低 + 高高（组内 `ROW_GAP`，组间 `SWITCH_GAP`） | 先跳，再阻止「看到就拉满二段跳」 |
| `HIGH_MID_LOW` | 高 → 中 → 低（同 `FALL` 阶梯） | 站立可过，用于画下降趋势 |
| `DELAYED` | 低低 → 高高 → 顶位单枚（`DELAYED_GAP` / `DELAYED_TAIL`） | 下降途中重新抬升（延迟二段跳） |
| `SLIDE_ROW` | 滑铲线三枚横排（`ROW_GAP`） | 一个滑铲盖住整排 |
| `RISE_THREE` | 低 → 中 → 高（同 `RISE` 阶梯） | 滑铲后立刻起跳 |
| `HIGH_PAIR` | 高位双枚横排 | 站立可过（SAFE） |

**四个高度层 + 一条滑铲线**（全部由 `player.gd` / `PlayerMotionProfile` 推导，
不可手写魔数）：

| 常量 | 值 | 含义 |
|---|---|---|
| `LOW_HEIGHT` | `0.25 × H1` = 46.1 | ACT —— 站立会中，必须**跳**或滑铲 |
| `SLIDE_HEIGHT` | `SLIDE_HEIGHT + PLAYER_HEIGHT/2 + 1` = 66 | ACT —— 只能**滑铲** |
| `MID_HEIGHT` | `0.50 × H1` = 92.2 | SAFE —— 站着就能过，用于画线 |
| `HIGH_HEIGHT` | `0.78 × H1` = 143.9 | SAFE —— 站着就能过，用于画线 |
| `TOP_HEIGHT` | `0.95 × H1` = 175.2 | SAFE —— 只少量使用 |

其中 `H1 = Motion.jump_height() = 184.5`。

> 命中判据来自 `pattern_compiler.dart_hits_body`：飞镖高度 `h` 命中脚高 `f` 的玩家，
> 当且仅当 `h ∈ (f-11, f+77)`。站立身体高 66 → `h ≤ 77` 命中；
> 滑铲身体高 32 → `h ≤ 43` 命中。因此 **`h ∈ (43, 77]` 是「只能滑铲」的窄带**，
> 这是最容易写错的一段 —— 写宽了会变成「站着也能过」，写窄了会变成「无解」。
> 这条判据也是 `standing_safe_height() = 77` 与 ACT/SAFE 分类的来源。

**间距的写法**。间距以 **px** 写在数据里（`start_px` 给首项、`gap_px` 给后续项），
含义是「上一 Pattern 的**实际末枚**相遇 X → 本 Pattern 首枚相遇 X」：

```gdscript
next_first_beat = prev_first_beat + span_of(prev) + px_to_beat(gap_px)
```

`span_of()` 取 `expand()` 的最大 beat 并减去自身 `beat`，所以 Pattern 内部
有几枚、跨多宽都不影响对外间距。「写进数据的空白」与「屏幕上的空白」是同一个数。

**Wave 时长改为推导值**（`dart_wave_layout.gd`）。编辑动作句顺序不再需要手工改
`duration`：

```gdscript
const DURATION_EPSILON := 0.001
var effective_duration: float = maxf(
    data.duration, arrange_end + EXIT_CLEARANCE + DURATION_EPSILON)
plan["authored_duration"] = data.duration
plan["duration"] = effective_duration
plan["length"] = effective_duration * Motion.RUN_SPEED
```

> `DURATION_EPSILON` 是 2026-09-18 补的：末拍判据是
> `beat > effective_duration - EXIT_CLEARANCE`，当编排刚好填满时长时，
> 浮点会让 `2.0025 - 0.3` 算成 `1.7025000000000001 > 1.7025` 成立，
> 整段 Wave 被判违规 —— 表现是**一枚飞镖都不发射**。
>
> `plan["length"]` 这一行同样必须写。漏掉时自动延长只改了 `duration` 而没改
> `length`，于是**后面每一波都左移**，写下的间距与屏幕上的间距全部错位。

编排超出声明时长时会写进 `plan.notes`（「编排需要 X，已从声明的 Y 自动延长」）。
`pattern_compiler.gd` 必须**沿用**这个值，不能再用 `data.duration` 覆盖回去：

```gdscript
plan["duration"] = data.start_delay + maxf(data.duration, float(plan.get("duration", 0.0)))
```

> **为什么需要这条**：`dart_wave_layout` 曾把 `data.duration` 当**上限**、
> `pattern_compiler` 当**可选下限**，两边语义冲突。修好前有 4 个 Wave
> 溢出声明时长 +0.73 ~ +1.77s，这些溢出量被下一段吞掉，表现为「衔接突然变紧」。

**自查工具**：`tests/godot/dart_pattern_linkage_check.gd` 打印 `Dart_Map_A` 全部
相邻动作句对的 `exit_state` / `entry_need` / 模型与实际的间距。
当前 **7 处接缝，最紧的一处是 `RISE → LOW_PAIR`**。
全图级的 ACT 覆盖带体检由 `map_module_chunk.gd::_check_act_continuity()` 完成。

> **教训（写给未来的自己）**：这几个 bug 都是「同一个语义在两个函数里各写一遍，
> 然后悄悄分叉」。改高度层或衔接常量时，先跑 linkage check，
> 再看 `exit_state` 与 `exit_settle` 是否还互相同意。

**历史：旧的「衔接模型」（2026-09-16，已被取代）**

旧模型让每个动作句声明 `entry_need`（首拍要求玩家落地吗）与
`exit_state` / `exit_settle`（打完这句玩家在哪、多久落地），
再用 `link_gap(prev, next) = max(exit_settle + entry_lead_from + LINK_MARGIN, MIN_LINK_GAP)`
算出**最小**间隔。它修掉过两个真盲区：

1. **出口状态必须看整句，不能只看末拍。** 旧实现只读最后一拍的高度，
   `LOW_HIGH`（低 → 高）的末拍被判成 `GROUND`；但前面的低飞镖已经逼玩家起跳，
   打完这句其实**在空中**。
2. **入口预备时间必须成对计算。** `entry_lead` 曾只看下一句自己，
   于是「站立安全」的中位首拍被当成零预备，忽略了玩家可能还没落地。

被取代的原因：它算出来的是「理论最小值」，还要再叠一层余量才变成数据里的数字，
「眼睛看到的空白」与「写下的空白」之间多了一次转换。现在直接写像素，
模型退化为 §0.1 的两个覆盖带。兼容层函数（`entry_need` / `exit_settle` /
`exit_state` / `entry_lead` / `entry_lead_from` / `link_gap`）保留签名以免
旧检查脚本崩，`link_gap()` 现在返回 `0.0`。

### 6.4 `PatternCompiler` 校验规则

```gdscript
const MIN_REACTION_TIME := 0.45
const GAP_MARGIN := 22.0
const PROJECTILE_LIFETIME := 3.5
```

`compile(data, difficulty, modifier, recovery)` 流程：
`Layouts.build` → 标记 `needs_manual_playtest` → 基础数值校验 →
计算速度因子与 `start_delay` 位移 → **按威胁结束时刻推导 `length`** →
`Modifier.apply` → 按 `spawn_time` 排序 → `validate(plan)`。

> **长度推导（2026-09-11 修正）**
>
> 旧实现：`plan.length = max(data.length, plan.duration * RUN_SPEED)`。
> 因为 `ObstaclePatternData.duration` 默认 4.0s、`length` 默认 1800px，
> **任何**模板（哪怕只有一枚飞镖、威胁只持续 2 秒）都会被拉长到 4.5s / 1800px，
> 尾巴上留下大段没有威胁的空白。这是 Dart_Introduction「像是在参观障碍模板」
> 的结构性原因 —— 重做前该段有 5680px（14.2s）的纯跑动空白。
>
> 新实现：先算「最后一个威胁真正结束的时刻」`threat_end`，再换算成距离
> `needed = threat_end * RUN_SPEED`；`data.length` / `data.duration`
> 退化为**可选地板**，只有作者显式调高时才额外留白。
> 威胁结束时刻取二者较大值：
> * 移动障碍 —— `spawn_time + 相遇反应 + 缓冲`；
> * 出生点本身 —— `position_offset.x / RUN_SPEED`（飞镖出生在玩家前方，必须先跑过去）。
>
> 效果：该段长度 14140px → 12611px，尾段空白 5680px → 290px。

`validate(plan)` 逐项检查：

| 检查 | 判据 |
|---|---|
| 事件非空 | `events` 不可为空 |
| 事件合法 | `obstacle_scene != null`、`spawn_time >= 0`、`speed >= 0` |
| 非零方向 | `speed > 0` 时 `direction` 不可为零向量 |
| 反应时间 | `distance / closing_speed >= MIN_REACTION_TIME`（0.45s） |
| 地刺宽度 | `preview_size.x > 0` 且 `preview_size.x + BODY_SIZE.x <= RUN_SPEED * jump_time()` |
| 出生范围 | `position_offset.x + preview_size.x <= plan.length` |
| 坑重叠/边界 | 不可重叠；`0 <= pit.x < pit.y <= plan.length` |
| 坑宽 | `pit.y - pit.x + BODY_SIZE.x <= RUN_SPEED * jump_time()` |
| 安全口净高 | `gap.rect.size.y >= BODY_SIZE.y + GAP_MARGIN`（66 + 22） |
| 安全口高度 | 中心高度 `<= double_jump_height() + BODY_SIZE.y / 2.0` |

另外 `compile` 还会校验：`duration/length > 0`、`start_delay >= 0`、
`speed_multiplier > 0`、`0.5 <= recovery.duration <= 2.0`、
`Modifier.supported(data, modifier)`。

### 6.5 `PatternModifier` 变体

```gdscript
enum Kind { NORMAL, FAST, SLOW, MIRRORED, DOUBLE, REVERSE }
const FAST_MULTIPLIER := 1.2
const SLOW_MULTIPLIER := 0.85
const MIRROR_HEIGHT := 160.0
```

| 变体 | 行为 |
|---|---|
| NORMAL | 不变 |
| FAST / SLOW | 速度 × 1.2 / × 0.85（再乘 `data.speed_multiplier` 与难度系数） |
| MIRRORED | 围绕 `MIRROR_HEIGHT` 翻转：`y' = -320 - y`，同步翻转竖直方向；`gap` 一起翻转 |
| REVERSE | 反转事件发射时间顺序，同步补偿 X |
| DOUBLE | 使用**同一份内存数据**编译两遍，中间插入所选 Recovery 间隔；不复制磁盘资源 |

适用矩阵：

| Modifier | 适用 |
|---|---|
| NORMAL、DOUBLE | 全部 12 个 |
| FAST、SLOW | 除纯静态的 P01、P08 外 |
| MIRRORED | P04、P14、P15、P16、P17、P18 |
| REVERSE | P17、P18 |

### 6.6 难度系数

- 速度倍率在 0.92 ~ 1.08 之间随难度变化
- 安全口每级缩小 10px
- P01 刺宽每级变化 10%；P22 坑宽每级变化 5px；P18 高难度增加一枚
- P17 难度 1/3/5 → 2/3/4 堵墙；间隔 2.3/2.0/1.7s；缺口 136/116/96px

### 6.7 工作台入口

`patterns/test/PatternTest.tscn` + `patterns/test/pattern_test.gd`：

- 根节点 `process_mode = PROCESS_MODE_ALWAYS`，`player` 与 `$DynamicCamera` 为 `PROCESS_MODE_PAUSABLE`
- `_ready()` 自建 `PlayerCombat` 并连接信号。
  **能力基线与正式游戏保持一致**：
  连接 `ninjutsu_requested → cast_ninjutsu()` 与 `fireball_requested → cast_fireballs()`；
  **不连接 `sword_requested`**（Sword 是装备，Fireballs 才是它的主动武器技能；
  代码里仍存在 `cast_sword()` 不代表它属于正式能力集）
- 键位：`R` 重开、`]`/`PgDn` 下一个、`[`/`PgUp` 上一个、`F1` 预览、`P`/`Esc` 暂停
- 死亡 / 落坑 / 到末尾会暂停并提示按 R
- 编辑器下按 `enable_runtime_bridge` 挂载 `addons/godot-mcp/runtime_bridge.gd`
- `patterns/test/PatternPreview.tscn` 是纯预览场景

### 6.8 Phrase 的表达方式（`stages` / `stage_entries`）

**Phrase 不是代码类型，是关卡设计的语义单位。** 它通过
`PatternSectionData` 上的两个并行数组表达：

| 字段 | 类型 | 含义 |
|---|---|---|
| `section_name` | `String` | Section 内部标识，例如 `"Dart_Introduction"` |
| `display_name` | `String` | 人类可读的 Section 名，例如 `"飞镖关"` |
| `stages` | `PackedStringArray` | 阶段名列表，例如 `["Wave 1：单飞镖潮","短喘息",…]` |
| `stage_entries` | `PackedInt32Array` | 每个阶段占用多少个 entry，例如 `[1,1,2,1,…]` |
| `entries` | `Array[Resource]` | 真正的 Pattern / Recovery 序列 |

`stage_for(entry_index)` 按 `stage_entries` 的**累计计数**把 entry 映射到阶段名。
写入 `PatternSection.data` 后，`PatternSection.build()` 会把阶段名记进
`pattern_info[i].stage`，供 F1 调试覆盖层显示。
两个数组长度不一致、或累计数对不上 `entries.size()` 时返回 `""`（宁可显示空，不猜）。

**当前正式实例** —— `Dart_Map_A_Section1/2/3.tres`，每个 Section 都是
3 stage / 3 entry 的一一对应：

| Section | `section_name` | `display_name` | `stages` | `entries` |
|---|---|---|---|---|
| 1 | `Dart_Map_A_Entry` | 一 · 进入与高度判断 | 进入飞镖潮 / 第一次短呼吸 / 开始要求高度判断 | `Dart_Seg1_Entry` · `Dart_Seg2_Breath1` · `Dart_Seg3_HeightJudgement` |
| 2 | `Dart_Map_A_DelayedAndSlide` | 二 · 延迟二跳与滑铲 | 延迟二段跳题 / 只放一个滑铲题 / 滑铲之后马上起跳 | `Dart_Seg4_DelayedJump` · `Dart_Seg5_Slide` · `Dart_Seg6_SlideToJump` |
| 3 | `Dart_Map_A_Climax` | 三 · 第二呼吸与高潮 | 第二处短呼吸 / 高潮连续组合 / 短出口 | `Dart_Seg7_Breath2` · `Dart_Seg8_Climax` · `Dart_ExitRecovery` |

Section 长度 3120 / 1995 / 2920 px，合计 8035 px（跑速 400 时约 20.1s）。
Section 3 的末段是 1.4s 出口 Recovery。

> **旧实例** —— `Dart_Introduction.tres`（7 stage / 10 entry，`Dart_Scene1_Intro` …
> `Dart_ExitRecovery`，12909 px / 32.3s）是**上一代**的单 Section 飞镖关，
> 现已不在默认路线里。它仍然是一个可用的 `stages` 写法样例，
> 但**不代表当前正式地图**。

---

## 7. 正式系统与 Pattern 系统当前接线状态

> **本节已于 2026-09-11 重写。**
> 上一版结论是「两套系统互不相通」。该结论**已经过时**。

### 7.1 结论

**DARTS 是第一个完成 Map Module 垂直接入的正式内容。**
其余 12 个 Segment 仍是旧的手写实现。

```
树 A（正式世界）
  Route   = RhythmRouteGenerator.build_cycle() 的 Array[int]
  Segment = scenes/segment_*.tscn（Chunk）
  Obstacle= Spike / SlideBeam / Coin / Dart……

对于 DARTS（第一张正式 Map Module）：
  Route   →  game.gd.spawn_chunk()
          →  ChunkKind.DARTS → CHUNK_SCENES[12] → scenes/segment_darts.tscn
          →  components/dart_encounter.gd
          →  components/map_module_chunk.gd (MapModuleChunk)
          →  patterns/library/Dart_Map_A.tres (MapModuleData)
          →  3 × PatternSectionData / PatternSection
          →  patterns/pattern_compiler.gd (PatternCompiler.compile)
          →  patterns/pattern_runner.gd  (PatternRunner)
          →  实际 Dart / Spike 障碍

对于其余 12 个 Segment（仍是旧实现）：
  Route   →  game.gd.spawn_chunk()
          →  scenes/segment_*.tscn 里手写的障碍摆放
          →  Spike / SlideBeam / Coin……
          ── 不经过 Section / Pattern ──
```

调用链完全成立且已被自动化测试覆盖：

```
game.gd → RhythmRouteGenerator → segment_darts → MapModuleChunk
        → MapModuleData → PatternSectionData → PatternSection
        → PatternRunner → Pattern → Obstacle
```

### 7.2 硬证据

- `game.gd` **仍然没有**直接引用 `patterns/`；
  接入点是 `components/dart_encounter.gd`，由 `CHUNK_SCENES[12]` 间接引入
- `components/dart_encounter.gd` 现在 `extends "res://components/map_module_chunk.gd"`，
  不再自己写波次；内容来自 `Dart_Map_A.tres` 及其三个 Section 资源
- `scenes/segment_darts.tscn` 已删除硬编码的 7200px 地面，
  只保留 `SegmentDarts` / `Entry` / `Exit` / `Hint` 四个节点
- `PatternSection` 现在同时被正式游戏（DARTS）与 `PatternTest.tscn` 使用
- 自动化验证：
  `tests/godot/dart_section_wiring_regression.gd`（接线）
  `tests/godot/dart_section_official_regression.gd`（完整流程 + 衔接 + 暂停/重开/泄漏）
  `tests/godot/dart_patterns_regression.gd`（400 / 620 px/s 通过性）
  `tests/godot/official_darts_playthrough.gd`（正式场景连续实跑 2 遍）
  四份全部通过

### 7.3 各层成熟度裁定

| 层 | 是否存在 | 说明 |
|---|---|---|
| Route | ✅ 存在 | 仍在 `game.gd` 内，未抽成独立 Segment 管理器 |
| Map Module | ✅ 已接入 | DARTS / JUMP_MAP 使用两张完整地图，拥有主题、Variant、Difficulty、Section 顺序与整图 Entry / Exit |
| Segment | ⚠ 兼容入口 | `segment_darts.tscn` 保留旧路由槽位，内部委托给 Map Module |
| Section | ✅ 已接入 | DARTS / JUMP_MAP 真实使用 |
| Phrase | ⚠ 语义层存在 | 不是代码类型，通过 `PatternSectionData.stages` / `stage_entries` 表达 |
| Pattern | ✅ 存在且可用 | 编译器 / 运行器完整，DARTS / JUMP_MAP 真实调用 |
| Obstacle | ✅ 存在且可用 | 两棵树唯一真正共享的层 |

### 7.4 模块接入状态

| 模块 | 状态 |
|---|---|
| `game.gd` / `rhythm_route_generator.gd` / `scenes/segment_*.tscn` | **已接入正式游戏** |
| `components/player_combat.gd` / `ability_projectile.gd` / `combat_target.gd` | **已接入正式游戏** |
| `components/dart_encounter.gd` | **已接入正式游戏**，且已改为 Pattern 驱动 |
| `components/map_module_chunk.gd` / `patterns/map_module_data.gd` | **已接入正式游戏**，两张地图共用的 Map Module 运行时与数据层 |
| `patterns/obstacle_pattern_data.gd` · `event` · `layouts` · `walls` · `compiler` · `modifier` · `runner` | **已接入正式游戏**（经由 DARTS） |
| `patterns/pattern_section.gd` · `pattern_section_data.gd` · `recovery_section.gd` | **已接入正式游戏**（经由 DARTS） |
| `patterns/library/Dart_Map_A*.tres` / `Dart_Seg1..8_*.tres` / `Dart_ExitRecovery.tres` | **已接入正式游戏**（Map、Section 与 8 个 Pattern 数据） |
| `patterns/library/Jump_Map_A*.tres` / `JumpMap_Wave*.tres` | **已接入正式游戏**（3 Section / 8 Wave） |
| `patterns/jump_wave_layout.gd` / `components/spike_strip.gd` / `components/jump_pillar.gd` | **已接入正式游戏**（跳跃编排与静态障碍） |
| `patterns/library/P*.tres`（P01–P28） | 仍为工作台素材；`needs_manual_playtest` 仍为 `true` |
| `patterns/pattern_preview.gd` | 仅工作台 / 编辑器 |
| `scenes/segment_spikes.tscn` · `segment_slide.tscn` | **残留**，不参与默认路线 |
| 其余 12 个 `scenes/segment_*.tscn` | **仍是旧的手写障碍实现**，尚未迁移 |

### 7.5 第二张 Map Module 已完成

`Jump_Map_A` 已按地刺起跳、石柱连续动作、棘石组合三个 Section 重新设计完成。
独立追加路由槽位，不替换旧的 `Jump_A` 短练习段。Map Module / Section / Runner
直接复用，五种跳跃 Pattern 与可落脚柱子提供后续跳跃地图的具体样板，见 §0.2。

---

## 8. 当前已知硬编码

| 位置 | 硬编码 |
|---|---|
| `rhythm_route_generator.gd` | 每轮五张完整地图占据前两组的五个位置，顺序由种子决定 |
| `rhythm_route_generator.gd` | `GROUP_COUNT = 3`、`ENCOUNTERS_PER_GROUP = 3` |
| `rhythm_route_generator.gd` | 三个固定遭遇池数组 |
| `game.gd` | `CHUNK_SCENES` 14 项数组，**索引即协议**；越界即 `push_error` |
| `game.gd` | `CHUNK_AHEAD = 2200` / `CHUNK_CLEAN_BEHIND = 700` |
| `game.gd` | `DEFAULT_COIN_ENERGY = 10.0` 兜底 |
| `Dart_Map_A.tres` | `theme = DARTS`、`variant = A`、`difficulty = 1` 与三个固定 Section 的顺序 |
| `pattern_compiler.gd` | `MIN_REACTION_TIME = 0.45`、`GAP_MARGIN = 22`、`PROJECTILE_LIFETIME = 3.5`、`DART_CLEARANCE_RADIUS = 11`；长度按 `threat_end` 推导（`duration`/`length` 仅为可选地板）。**`plan.duration` 取 `data.start_delay + max(data.duration, 布局层算出的时长)`**，不再用 `data.duration` 覆盖布局结果 |
| `dart_pattern_library.gd` | 高度层由 `H1 = 184.5` 等比推出：`LOW 0.25 H1 = 46.1 / MID 0.50 H1 = 92.2 / HIGH 0.78 H1 = 143.9 / TOP 0.95 H1 = 175.2`，另加滑铲线 `SLIDE = 66`；像素间距 `INNER_GAP 110 / ROW_GAP 102 / TIGHT_LINK 115 / NORMAL_LINK 150 / BREATH 285 / SWITCH_GAP 115 / DELAYED_GAP 130 / DELAYED_TAIL 100 / DIAGONAL_GAP 110 / FIRST_BEAT_PX 320`；覆盖带 `SEAM_SAFETY_PX 24 / TAKEOFF_LEAD_PX 80`，派生 `contact_pad_px() = 34 / slide_cover_px() = 359.6 / seam_continuous_max_px() = 268 / seam_clean_min_px() = 384` |
| `dart_wave_layout.gd` | `APPROACH_JUMPS = 2.0`、`MIN_BEAT_GAP = 0.25`、`EXIT_CLEARANCE = 0.3`；**有效时长 = max(声明 duration, 编排所需时长)**，把 `plan.duration` / `plan.length` 都按有效时长写回 |
| `rope_wave_layout.gd` | `DART_SPEED = 0.45 × RUN_SPEED`、`APPROACH_JUMPS = 2.5`、`SPIKE_HEIGHT_RATIO = 0.32`、`BURST_INTERVAL = FLIP_DURATION × 0.5 = 0.09`；绳索段布局层数据 `MAX_BURST_COUNT = 8`、`MIN_SPACING = 0.06`、`MAX_SPACING = 0.40` |
| `pattern_layouts.gd` | P30 动作句：相邻相遇间隔判据 `0.25s ~ 1.5 × jump_time()` |
| `pattern_modifier.gd` | `FAST_MULTIPLIER = 1.2`、`SLOW_MULTIPLIER = 0.85`、`MIRROR_HEIGHT = 160` |
| `pattern_walls.gd` | `ROW_SPACING = 28`、`MIN_HEIGHT = 14`、`MAX_HEIGHT = 310` |
| `pattern_runner.gd` | `MAX_OBSTACLES = 96`、预警线 0.8s |
| `pattern_section.gd` | 地面高度固定 80px（碰撞盒与 `Polygon2D`）；Recovery 金币 `COIN_HEIGHT = 34`、`COIN_SPACING_RATIO = 0.5` |
| `player_combat.gd` | `FIREBALL_COOLDOWN = 8.0`、`FIREBALL_DURATION = 6.0` |
| `orbit_fireball.gd` | 复用 `ability_projectile.gd` 的 `ORBIT_RADIUS` / `FIREBALL_RADIUS`；开火节奏见 `FIREBALL_LAUNCH_INTERVAL` |

---

## 9. 当前技术债务

1. **已有两张完整地图**：DARTS 与 JUMP_MAP 完成 Map Module 垂直接入，
   其余旧 Segment 尚未组成 Mixed / Rope Map Module。
2. **无难度推进**：`difficulty` 与 `modifier` 在 DARTS 里是常量
   （`SECTION_DIFFICULTY = 1` / `NORMAL`）；正式游戏整体难度恒定，
   玩家第一分钟与第 N 分钟面对同一强度循环。
3. **跨地图难度曲线未完成**：两张 Map 内部已有教学、变化、升压与释放，
   外层仍是固定组数的遭遇循环，尚未随圈数推进难度。
4. **路线逻辑寄生在 `game.gd`**：缺少独立的 Segment / Route 管理层，
   任何内容调整都要改代码而非改数据。
5. **可达性无自动校验**：其余 12 个手写 `scenes/segment_*.tscn` 的跳跃跨度
   是否落在 `PlayerMotionProfile` 推算的安全带内，**没有任何自动检查**。
   DARTS 已由 `PatternCompiler` 覆盖。
6. **Pattern 模板仍未人工验证**：`library/P*.tres`（P01–P28）均为
   `needs_manual_playtest = true`；260 个受支持组合的参数检查
   与生成测试**不构成联合路线证明**。DARTS 的 8 个 `Dart_Seg*.tres`
   已由三层自动检查覆盖，但**仍待朋友本人试玩**确认手感。
7. **飞镖段验证面窄**：只在 400 / 620 px/s、NORMAL、difficulty 1、
   不使用技能、固定种子（20260911 / 20260909）的条件下验证过可无伤通过，
   不代表所有随机路线或任意操作都安全。
   当前可无伤通过由三个独立求解器支持（`dart_map_reachability` 解析扫描、
   `dart_map_solvability_probe` 逐帧求解、`dart_map_module_regression` 的
   ACT 覆盖带断言），但它们都是**求解器**，不等于人类手感。
8. **`PatternCompiler` 缺少「飞镖空间可读性」的默认校验**：
   现已实现 `dart_hits_body()` 与「任何姿态都碰不到即装饰」的检查，
   但由 `plan.check_dart_reachability` 显式打开（默认关闭），
   以免影响既有 P21 / P22 模板的合法性判定。
   **尚未有工具常态化打开它。**
   （注意：2026-09-18 新增的 ACT 覆盖带检查是**另一件事** ——
   它判「一簇贴地镖能不能被一个滑铲盖住」，已在 `map_module_chunk.gd`
   全图常态化打开，不受这个开关影响。）
9. **反应式试玩驱动器判不出「连续动作」**：`dart_map_playtest.gd` 只看眼前的
   飞镖决定动作，不做离线规划，因此在需要提前起跳 / 连滑的接缝上必踩。
   它当前受伤 5 次、死亡 1 次，**不代表关卡不可解**（见 §0.1 交付判据）。
   建议改造方向见 `docs/DART_MAP_PLAYTEST_FINDINGS.md`。
10. **残留场景**：`segment_spikes.tscn` / `segment_slide.tscn` 仍在仓库中。
11. **文档与实现同步依赖人工**：本文件与 `docs/LEVEL_DESIGN.md` 需随架构变化手动更新。

---

## 10. 键位与输入（`project.godot`）

| 动作 | 键 |
|---|---|
| `jump` | `Space` / `↑` / `W` |
| `slide` | `S` / `↓` |
| `sword` | `J` |
| `ninjutsu` | `Shift` / `K` |
| `fireball` | `Q` |
| `pause` | `P` / `Esc` |
| `restart` | `R` |

视口 960×540；渲染器 GL Compatibility；启用 `addons/godot-mcp/plugin.cfg`。

---

## 11. 相关文档

| 文档 | 内容 |
|---|---|
| `.codebuddy/skills/ninja-run-level-design/SKILL.md` | 长期稳定的工作规则、真值来源、流程 |
| `docs/LEVEL_DESIGN.md` | 关卡设计原则与判据 |
| `README.md` | 项目总览、操作说明、段库表、战斗参数、程序化视觉 |
| `patterns/README.md` | Pattern 工作台使用手册 |
| `tests/PATTERN_VALIDATION.md` | Pattern 验证记录 |
| `tests/COMBAT_VALIDATION.md` | 战斗验证记录 |
| `tests/jump/README.md` | 跳跃实测数据 |
