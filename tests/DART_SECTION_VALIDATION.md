> 当前完整地图验证见 [DART_MAP_VALIDATION.md](DART_MAP_VALIDATION.md)。下文为历史版本记录。

# DART_SECTION_VALIDATION.md — DARTS Segment 验证记录

## 2026-09-13 — Dart_Map_A / Map Module

- 正式数据：`patterns/library/Dart_Map_A.tres`
- 结构：单飞镖阶段 → 飞镖墙阶段 → 综合阶段
- 验证条件：基础跑速 400 px/s、Difficulty 1、固定数据编排、不使用技能、自动推进玩家 X 坐标
- 定向命令：`Godot --headless --path . --fixed-fps 60 --script tests/godot/dart_map_module_regression.gd`
- 结果：3 个 Section 均同步生成；长度 8216 / 9764 / 4039 px；总长 22019 px（约 55.0s）
- 接缝：Section 2/3 的 Entry 与前一 Section 真实 Exit 重合；Module Exit = 22019 px
- 穿越：已推进通过前两个 Section，所有对应 PatternRunner 均启动或完成
- 人工试玩：未执行，`needs_manual_playtest` 保持不变；节奏、可读性与实际操作手感交由真人试玩

---

> 本文件记录 **DARTS（`segment_darts`）作为第一个完成 Pattern 垂直接入的
> 正式 Segment** 的验证条件与结论。
>
> 对应代码见 `docs/ARCHITECTURE.md` §7；对应数据结构见 §6.8。
>
> 最后一次完整验证：2026-09-11。

---

## 1. 被验证的目标

`Dart_Introduction` —— 第一个正式 Dart Section Variant。

调用链：

```
game.gd
→ RhythmRouteGenerator.build_cycle()   (DARTS 随五张完整地图一起换序)
→ game.gd.spawn_chunk()
→ ChunkKind.DARTS → CHUNK_SCENES[12] → scenes/segment_darts.tscn
→ components/dart_encounter.gd
→ patterns/pattern_section.gd           (PatternSection)
→ patterns/library/Dart_Introduction.tres (PatternSectionData)
→ patterns/pattern_compiler.gd          (PatternCompiler.compile)
→ patterns/pattern_runner.gd            (PatternRunner)
→ 实际 Dart / Spike 障碍
```

---

## 2. 验证条件（必须随结论一起记录）

| 项 | 值 |
|---|---|
| 跑速 | **400 px/s**（`Player.RUN_SPEED`）；`dart_patterns_regression` 额外覆盖 **620 px/s**（滑铲冲刺） |
| Modifier | **NORMAL**（`SECTION_MODIFIER`） |
| 设计难度 | **1**（`SECTION_DIFFICULTY`） |
| 主动技能 | **不使用**（不按 `ninjutsu` / `fireball`） |
| 装备 | Sword 可按但不影响结论；`sword_requested` 在正式游戏与 PatternTest 均**未连接** |
| 种子 | **20260911**（官方回归 / 正式实跑）、**20260909**（跑速回归） |
| 渲染 | `--headless`，`--fixed-fps 60` |
| 引擎 | Godot **4.7.2.stable.official** |

> 结论只在这些条件下成立。换难度、加 modifier、开技能、
> 或换随机种子后必须重新验证。

---

## 3. Section 组成（2026-09-11 重做后）

| # | entry | 显示名 | stage | 长度 | 事件 | 最小反应时间 |
|---|---|---|---|---|---|---|
| 0 | `Dart_Scene1_Intro` (P30) | 齐胸飞镖接高位飞镖 | 场景1 认识飞镖 | 1271 px | 2 | 0.637 s |
| 1 | `Dart_Scene2_AirRead` (P30) | 低飞镖起跳后空中换位 | 场景2 连续跳跃 | 1563 px | 3 | 0.628 s |
| 2 | `Dart_Scene3_EntryToWall` (P30) | 起跳后落地读中位缺口 | 场景3 读取缺口 | 940 px | 1 | 1.182 s |
| 3 | `Dart_Scene3_GapWall` (P14) | 中位缺口飞镖墙 | 场景3 读取缺口 | 1031 px | 3 | 1.199 s |
| 4 | `Dart_Recovery` (1.4s, 金币 ×3) | 喘息 | 喘息 | 560 px | — | — |
| 5 | `Dart_Scene4_HighGap` (P14) | 高位缺口飞镖墙 | 场景4 高位缺口 | 1031 px | 4 | 1.199 s |
| 6 | `Dart_Scene5_Switch` (P17) | 连续换位飞镖墙 | 场景5 上下换位 | 3200 px | 14 | 1.267 s |
| 7 | `Dart_Scene6_Climax` (P30) | 三连快镖 | 场景6 短高潮 | 1484 px | 3 | 0.619 s |
| 8 | `Dart_Scene6_ClimaxWall` (P14) | 高潮收尾墙 | 场景6 短高潮 | 1051 px | 5 | 1.178 s |
| 9 | `Dart_ExitRecovery` (1.2s, 金币 ×2) | 出口喘息 | 出口喘息 | 480 px | — | — |

- **总长** = `12611 px`（跑速 400 时约 **31.5 s**）
- **Recovery** = `1040 px` = 2.6 s；**Pattern 尾段无意义空白** = `290 px` = 0.7 s
- 全部 entry 的编译器 issue = **0**

### 3.1 为什么旧版「显得只是在参观障碍模板」

旧版把每个障碍都做成**独立的单飞镖 Pattern**（`Dart_P04_Intro`、
`Dart_P04_HeightVariation`、`Dart_P14_GapIntro`…），并且：
`duration` 默认 4.0s，`PatternCompiler` 的 `length = max(data.length, duration × RUN_SPEED)`
把**每一个** Pattern 都拉到 1800 px。于是玩家体验是
「跑 → 一个障碍 → 跑很久 → 一个障碍」，出现 **5680 px = 14.2 s** 的纯跑动空白
（占全段 40%）。

重做做了三件事：

1. 新增 **P30 飞镖动作句**：在**同一个 Pattern 内**编排多枚飞镖，
   相遇间隔控制在一个单跳周期内，形成「一次操作解决两拍」；
2. 把 `PatternCompiler` 的 `length` 改为**按最后威胁结束时刻推导**，
   `duration` / `length` 退化为可选地板（见 `docs/ARCHITECTURE.md` §6.4）；
3. Recovery 铺金币做「这里可以喘息」的低压力视觉引导。

结果：总长 14140 → **12611 px**，尾段空白 5680 → **290 px**（**压缩 5390 px = 13.5 s**）。

### 3.2 反应时间与可读性

- 硬线：`PatternCompiler.MIN_REACTION_TIME = 0.45 s`
- 本段优先目标：`>= 0.6 s`
- 实测最小反应时间：**0.619 s**（`Dart_Scene6_Climax` 的小高潮快镖）
- 其余 Pattern 均 >= 1.17 s

> 小高潮把相遇间隔压到 0.62 / 0.58 s（比单跳周期 0.70 s 还短），
> 密度是**靠提高 `speed` 到 220** 得到的，而不是压缩反应窗口。
> 反应窗口仍保持 0.6 s 以上，高于 0.45 s 硬线。

### 3.3 连续动作检查（本段的核心设计目标）

`tests/godot/dart_section_design_check.gd` 会对每个 P30 动作句
逐枚打印**相遇时刻**并判断相邻间隔是否落在 `1.5 × 单跳周期` 内：

```
· 齐胸飞镖接高位飞镖
     相遇 2.30s  高度 74
     相遇 3.02s  高度 165  <- 间隔 0.72s（连续动作）
· 低飞镖起跳后空中换位
     相遇 2.30s  高度 8
     相遇 3.04s  高度 165  <- 间隔 0.74s（连续动作）
     相遇 3.76s  高度 74   <- 间隔 0.72s（连续动作）
· 三连快镖
     相遇 2.40s  高度 74
     相遇 3.02s  高度 8    <- 间隔 0.62s（连续动作）
     相遇 3.60s  高度 165  <- 间隔 0.58s（连续动作）
```

> **易错点**：相遇时刻 = `delay + distance / RUN_SPEED`。
> 只调 `delay` 而不调 `distance`，相遇间隔会被 `distance` 的增量顶大，
> 动作句就退化成「两道相距很远的独立题目」。
> 必须让 `Δdistance ≈ (目标相遇间隔 − Δdelay) × RUN_SPEED`。

### 3.4 飞镖墙缺口的可达性（本轮发现并修正的设计失误）

`pattern_walls.gd` 的行高从 14px 到 310px、步长 28px；`safe_gap_position`
决定挖掉哪一段。按玩家身高 66px 推导：

| `safe_gap_position` | 缺口区间 | 站立能过？ | 下蹲能过？ | 结论 |
|---|---|---|---|---|
| **80**（旧值） | −15…175 | ✅ | ✅ | **纯走路，没有任何操作** ← 失误 |
| **110**（新值） | 20…200 | ❌ | ❌ | 必须跳入中段 ✅ |
| **150** | 55…245 | ❌ | ❌ | 必须跳得更高 ✅ |
| **175** | 85…265 | ❌ | ❌ | 必须跳得更高 ✅ |

旧版 Scene3 / Scene5 / Scene6 的墙都用 `gap_position = 80`，
玩家**可以直接跑过去**，视觉上只看到一串悬在头顶的飞镖 ——
这正是「飞镖墙看起来很孤立」的原因。已全部改为 110 以上，
并把 Scene5 的换位改成 110 ↔ 175（两档都必须跳、但身体位置明显不同）。

### 3.5 单一变化维度

| Variation | 唯一改动的参数 | 从 → 到 | 玩家解法变化 |
|---|---|---|---|
| `Dart_Scene4_HighGap` | `safe_gap_position` | 110 → 150 | 安全口从中位抬到更高处，**进入时机更靠单跳顶点** |

由 `dart_section_design_check.gd` 程序化断言为 **恰好 1 个参数键变化**。
`Dart_Scene6_ClimaxWall` 是**独立 Pattern（不是 Variation）**，
因此不要求单维度，工具会注明「该 Pattern 不是 Variation，无需单维度约束」。

---

## 4. Exit 与段间衔接

- `Exit` 由 `dart_encounter._reposition_exit()` 在 `_ready()` 内**同步**重定位到
  `section.position.x + section.section_length`
- 实测 `Exit` 落在 Section 真实结尾（长度变化自动生效，不写死数值）
- 与下一段（`SegmentSingleJump`）的实测接缝 = **0.00 px**
- 所有 Pattern 都在进入下一段之前结束（`Exit` 落在 Section 真实结尾）

### 4.1 必须同步构建（重要约束）

`build_section()` **必须**在 `_ready()` 里同步执行，不能 `call_deferred`。

原因：`game.gd.spawn_chunk()` 在 `add_child()` 之后**立刻**读
`exit.global_position` 作为下一个 chunk 的对齐点。
若延迟到下一帧，读到的是场景里的旧入口位置，
下一个 Segment 会直接叠在本段起点上（本次开发中实际踩到过这个 bug）。

---

## 5. 自动化测试（6 份，全部通过）

| 测试 | 覆盖 |
|---|---|
| `tests/godot/dart_section_design_check.gd` | 长度分解、每 entry 反应时间、编译器 issue、连续动作判据、Variation 单因子断言、节奏与留白总览 |
| `tests/godot/fireball_skill_regression.gd` | 武器主动技能：orbit 恒为 3 / 发射后立即补位 / projectile 可 > 3 / 技能结束停止发射 / restart 清空 |
| `tests/godot/dart_section_wiring_regression.gd` | 接线正确性：序列、长度、Exit、地面覆盖、runner plan（期望值从数据推导） |
| `tests/godot/dart_section_official_regression.gd` | 真实路径完整走完：生成 / 推进 / 清理 / 衔接 / 飞镖生命周期 / 暂停恢复 / Restart / 泄漏 |
| `tests/godot/dart_patterns_regression.gd` | 400 与 620 px/s 两档跑速下的无伤通过 + 飞镖上限 |
| `tests/godot/official_darts_playthrough.gd` | 正式场景**连续实跑 2 遍**，记录控制台与运行时错误 |

另有视觉试玩工具（需真实窗口，非 headless）：

```bash
"<godot>" --path . --script tests/godot/darts_playtest_capture.gd
# 输出到 tests/artifacts/darts/*.png
```

运行方式：

```bash
"/c/Users/30858/Desktop/Godot/Godot_v4.7.2-stable_win64_console.exe" \
  --headless --path . --fixed-fps 60 \
  --script tests/godot/<测试名>.gd
```

跑速回归可通过环境变量改遍数：

```bash
GODOT_DARTS_RUNS=2 <godot> --headless --path . --fixed-fps 60 \
  --script tests/godot/official_darts_playthrough.gd
```

---

## 6. 自动化验证结论

| 检查项 | 结果 |
|---|---|
| Pattern 是否真实由 `PatternRunner` 生成 | ✅ 是（8 个 Runner，全部实际生成障碍，共 36 个事件） |
| 是否有 P30 动作句 | ✅ 3 个（场景1 / 场景2 / 场景6），相遇间隔 0.58–0.74 s，全部落在单跳周期内 |
| 是否有多枚飞镖串成一次操作 | ✅ 是（连续动作检查全部通过） |
| 飞镖墙缺口是否需要操作 | ✅ 全部 >= 110，站立/下蹲都过不去，必须跳 |
| 是否有 Variation | ✅ `Dart_Scene4_HighGap`，唯一改动 `safe_gap_position` |
| Recovery 是否存在 | ✅ 两段，1040 px（1.4s + 1.2s），各带金币引导 |
| Pattern 是否重叠 | ✅ 无重叠、无空隙（cursor 连续） |
| 无意义空白 | ✅ 290 px = 0.7 s（重做前 5680 px = 14.2 s） |
| Entry / Exit 是否正确 | ✅ Exit 落在真实结尾 |
| 相邻 Segment 接缝 | ✅ 0.00 px |
| 飞镖生命周期 | ✅ 越过后全部回收，段后残留 = 0 |
| 玩家碰撞 | ✅ 会读预警的玩家可无伤通过（health = 50） |
| 暂停 / 恢复 | ✅ 暂停冻结、恢复继续 |
| Restart 后重新初始化 | ✅ 8 个 Runner 全部 `spawned_count=0` / `completed=false` / `event_index=0` |
| Godot runtime error | ✅ 无（正式实跑 2 遍控制台干净） |
| orphan / 残留节点 | ✅ `stray = 0`，`live darts = 0`，根节点数不增长 |
| PatternRunner 状态重置 | ✅ `dirty = 0` |

> **注意「直线不解题」是预期结果，不是缺陷。**
> 若让虚拟玩家全程走直线不闪避，会撞上飞镖墙（`run_state → GAME_OVER`），
> 后续 Runner 全部冻结。这恰好证明碰撞与伤害链路真实生效。
> 通过性结论只在「玩家会读预警并做出下蹲/起跳/进安全口」的前提下成立。

> **「可通过」与「有趣」是两个不同的验收目标。**
> 上表只证明**可通过**。是否**有趣**、节奏是否舒服、动作句读不读得出来，
> 必须靠 §7 的人工试玩。

---

## 7. 人工试玩清单（**尚未执行**）

> 自动化只能证明「链通、可通行、无泄漏」。
> 手感、可读性、教学节奏**必须**由人试玩确认。
>
> `needs_manual_playtest` 继续保持 `true`，直到下表全部打勾。

### 7.1 逐场景确认

- [ ] **场景1 齐胸飞镖接高位飞镖**：第一枚齐胸飞镖是否一看就知道要处理？
      第二枚在 0.72 s 后出现时，是否感觉是「同一跳里的第二拍」
      而不是「新的一个障碍」？
- [ ] **场景2 低飞镖起跳后空中换位**：贴地飞镖是否逼出起跳？
      在空中看到的第二枚高位飞镖，读位是否来得及？落地后第三枚齐胸飞镖
      是否迫使命中蹲下 —— 三段是否串成**一次连续跳跃**？
- [ ] **场景3 读取缺口**：先起跳、再落地读飞镖墙的缺口，
      「前一个障碍影响进入状态」这件事是否真的发生了？
- [ ] **场景4 高位缺口**：与场景3 相比，是否感觉到「同一堵墙，口更高了」
      而不是「换了一个新机关」？
- [ ] **场景5 上下换位**：110 ↔ 175 的换位是否形成真正的移动节奏？
      第一组建立的解法在第二组是否自然复用？
- [ ] **场景6 短高潮**：三连快镖（0.62 / 0.58 s 间隔）是否明显更忙？
      是否读得出是「这一段的高潮」而不是「又一组障碍」？
- [ ] **喘息 / 出口喘息**：金币 + 空跑是否真的让人松下来？
      还是觉得「怎么还没结束」？

### 7.2 整段节奏

- [ ] 整段是否形成 **认识 → 连续动作 → 读取缺口 → 喘息 → 变化 → 换位 → 小高潮 → 释放**？
- [ ] 屏幕上是否还出现**大段只有平地**的情况？（若有，记下 x 坐标）
- [ ] 是否经常出现「处理完一个障碍之后就没事干」？（若有，记下 x 坐标）
- [ ] 飞镖墙看起来是否还是**孤立的**？
- [ ] 是否存在「不知道自己怎么死的」的时刻？（若有，记下 x 坐标）
- [ ] 第一次通关大概死几次？是否落在一个可接受的区间？

### 7.3 反馈方式（F1）

按 **F1** 打开调试覆盖层，可以看到：

- 当前 **Segment**（DARTS）
- 当前 **Section**（`飞镖教学`，内部 ID `Dart_Introduction`）
- 当前 **Stage**（`场景1 认识飞镖` / `喘息` / `场景5 上下换位` …）
- 当前 **Pattern**（`齐胸飞镖接高位飞镖 (P30)` / `中位缺口飞镖墙 (P14)` …）
- 当前 **Modifier** 与 **Difficulty**

因此反馈可以直接写成自然语言，不需要记编号，例如：

> 「**场景5 上下换位**的**连续换位飞镖墙**太紧」
> 「**场景3 读取缺口**之后留白太长」

覆盖层会同时显示人类可读名与内部编号，定位无歧义。

---

## 8. 复用清单：迁移 `segment_single_jump` 时可直接拿走的

下一段（`segment_single_jump`）是路由上的第二个 Segment，
与 DARTS 同属「少量 Pattern 串联」，可直接复用：

### 8.1 可直接复用（无需改动）

| 资产 | 说明 |
|---|---|
| `patterns/pattern_section.gd` | Section 容器：编译、地面、`advance()`、调试信息 |
| `patterns/pattern_section_data.gd` | 数据 + `stages` / `stage_entries` / `stage_for()` |
| `patterns/recovery_section.gd` | Recovery 长度表达 |
| `patterns/pattern_compiler.gd` / `runner.gd` / `modifier.gd` | 编译与运行 |
| `patterns/player_motion_profile.gd` | 运动真值（跑速 / 跳跃 / 滑铲 / 地面线） |
| `components/chunk.gd` | Chunk 契约基类 |
| `docs/ARCHITECTURE.md` §6.8 | Phrase 的表达方式 |
| `tests/godot/dart_section_design_check.gd` | 换成新数据即可做长度/反应时间/单因子检查 |

### 8.2 需要照抄并改名的部分（`components/dart_encounter.gd`）

四件事，全部与「段名」有关：

1. `extends "res://components/chunk.gd"`
2. `SECTION_DATA` 指向新的 `*_Section.tres`
3. `SECTION_START_INPUT_CLEARANCE` / `SECTION_DIFFICULTY` / `SECTION_MODIFIER`
4. `debug_info()` 里的 `"segment"` 名称

**必须保留的实现细节：**

- `build_section()` 在 `_ready()` 内**同步**执行（见 §4.1）
- `_build_entry_clearance()` 调 `section.add_ground(-width, width)`
  —— 负起点。因为 Section 已经前移了 `clearance × RUN_SPEED`，
  入口缓冲地面必须落在 Section 局部坐标的 `0` 之前。
- `advance()` 里把 `game.gd` 传入的真实 `player` 补进 runner
- `_reposition_exit()` 用 `section.section_length` 定位 Exit

### 8.3 建议的迁移顺序

1. 先用 `dart_section_design_check.gd` 的模板核算新段长度与反应时间
2. 写 `patterns/library/<Name>_Section.tres`（含 `stages` / `stage_entries`）
3. 复制 `dart_encounter.gd` → `<name>_encounter.gd`，改 4 处
4. 清空原 `segment_<name>.tscn` 里的手写障碍，只留
   `Entry` / `Exit` / `Hint` + 段脚本
5. 复制 `dart_section_official_regression.gd` 做该段的回归
6. 更新 `docs/ARCHITECTURE.md` §7.4 的模块接入状态表

### 8.4 本轮的坑（迁移时直接避开）

1. **Exit 时序**：延迟构建会导致下一个 Segment 叠放（§4.1）
2. **玩家不在任何 group**：`get_nodes_in_group("player")` 拿不到玩家，
   必须走 `get_parent().get_node_or_null("Player")`
3. **「时间窗口够」≠「有威胁」**：飞镖还必须校验站立姿态是否真的会撞到（§3.3 旧版）
4. **「有缺口」≠「需要操作」**：飞镖墙的 `safe_gap_position` 太低时，
   玩家站着就能走过去，墙会退化成「头顶悬着一串装饰飞镖」（§3.4）
5. **相遇间隔 ≠ `delay` 间隔**：`Δencounter = Δdelay + Δdistance / RUN_SPEED`，
   只调 `delay` 会把动作句顶成两道独立题目（§3.3）
6. **`duration` 默认值会制造空白**：`PatternCompiler` 的 `length` 必须按
   真实威胁结束时刻推导，否则每个 Pattern 都会被拉到 1800 px（§3.1）
7. **测试期望值要从数据推导**：把 `runners.size() == 6`、
   序列 `"P04 → P14 → P17"` 之类写死在测试里，
   一旦重新编排 Section 就会同时产生「正确的失败」和「错误的成功」。
   应改为从 `section.data.entries` 推导期望。

---

## 2026-09-12 五波飞镖潮重编验证

验证条件：Godot 4.7.2，固定 60 FPS，基础跑速 400 px/s；另以 620 px/s
复核滑铲峰值路线；不使用武器或忍术；正式路线 seed 20260911。

| 阶段 | 实际内容 | 节奏 / 时长 |
|---|---|---|
| 入口 | 360px 安全地面 | 0.9s；首个威胁约在进段后 1.8s 相遇 |
| Wave 1 单飞镖潮 | 5 枚，高低变化 | 间隔 1.00 / 0.95 / 0.85 / 0.75s；4.95s |
| Wave 2 单飞镖加强 | 6 枚，高低交替 | 间隔 0.78 / 0.72 / 0.66 / 0.60 / 0.56s；4.97s |
| 短喘息 | 金币 ×3 | 0.7s |
| Wave 3 成排飞镖潮 | 4 墙 | 中 / 中 / 中 / 略高；5.13s |
| Wave 4 成排飞镖加强 | 6 墙 | 中 / 中 / 高 / 低 / 高 / 低；6.73s |
| Wave 5 混合高潮 | 高位→贴地→齐胸三连镖 → 中/中/高三墙 → 贴地双镖 → 中缝墙 | 9.00s；全段唯一混合两类语言且间隔最密 |
| 短出口 | 金币 ×2 | 0.8s |

- Section：12909px / 32.3s；含入口合计 13269px / 33.2s。
- Pattern 尾段无意义空白：0px / 0s；最大连续无威胁间隔：1.84s。
- 对照早期散漫版本：14140px / 35.4s，尾段空白 5680px / 14.2s；
  本轮删除全部 5680px 无意义尾空白，并用明确波次填充主体。
- `dart_section_design_check.gd`：五波映射、数量、节奏、反应窗口、最大静默间隔通过。
- `dart_patterns_regression.gd`：400 / 620 px/s，无技能，无伤通过。
- `dart_section_wiring_regression.gd`：Entry / Exit、地面覆盖、Runner 接线通过。
- `dart_section_official_regression.gd`：正式生成、生命周期、暂停、restart、清理、下段 seam 通过。
- `official_darts_playthrough.gd`：正式路线连续两次自动读位通过。
- 正常窗口：OpenGL 3.3 / NVIDIA RTX 4050，8 个 Pattern 与总览均成功渲染并写入
  `tests/artifacts/darts/`。代表帧确认单镖、墙、换位与混合高潮的视觉语言清楚。
- 仍需真人连续试玩判断：0.7s 喘息是否足够明显、Wave 4 六墙是否疲劳、
  Wave 5 是否主观上达到最高压力，以及 0.8s 出口是否舒服。
