# Obstacle Pattern 工作台

这是一套人工编排的障碍生产工具。正式入口仍然是原来的 `test_world.tscn`；正式飞镖地图已通过 MapModuleChunk 接入。DART_WAVE 将有序单镖与墙列编译为距离节拍，具体编排及实跑结果见 ../tests/DART_MAP_VALIDATION.md；下文 P01～P30 的时间型模板仍可在工作台独立预览。

## 立即试玩

在 Godot 打开 `res://patterns/test/PatternTest.tscn`，按 **F6 运行当前场景**。底部选择模板、Difficulty 和 Modifier；改选项会重开。

| 操作 | 按键 |
|---|---|
| 起跳、二段跳 | Space |
| 急降、滑铲；空中快速连按接落地滑铲 | S |
| 重开当前模板 | R |
| 下一个 / 上一个 | `]` / `[`，也支持 PgDn / PgUp |
| 暂停 / 恢复 | P 或 Esc |
| 显示 / 隐藏预览 | F1 |

死亡、落坑、到达末尾会暂停，按 R 重来。战斗复用现有 PlayerCombat，方便检查障碍可破坏性；测试场景不带正式游戏的能量经济。判断路线时应先不使用技能。

## 模板与数据文件

所有数据在 `res://patterns/library/`，每个文件都能在 Inspector 编辑。默认 difficulty=3。

| 模板 | 数据文件 | Inspector 的 parameters |
|---|---|---|
| P01 单刺跳 | `P01_SingleSpike.tres` | spike_width、position、warning_distance |
| P04 单飞镖 | `P04_SingleShuriken.tres` | height、speed、direction、spawn_distance |
| P08 高低切换 | `P08_HighLow.tres` | spike_width、position、ceiling_clearance |
| P14 中间安全口 | `P14_MiddleGap.tres` | safe_gap_size、safe_gap_position、wall_speed、spawn_distance |
| P15 上方安全口 | `P15_TopGap.tres` | 同 P14，默认中心高度 165 |
| P16 下方安全口 | `P16_BottomGap.tres` | 同 P14，默认中心高度 40 |
| P17 安全口换位 | `P17_GapSwitch.tres` | wall_count、wall_interval、gap_positions、wall_speed、gap_size |
| P18 斜线飞镖 | `P18_Diagonal.tres` | count、height、height_step、x_spacing、spawn_distance、speed |
| P21 地刺+飞镖 | `P21_SpikeShuriken.tres` | position、spike_width、height、speed |
| P22 坑+顶部飞镖 | `P22_GapCeiling.tres` | position、pit_width、height、speed |
| P24 墙+落点陷阱 | `P24_WallLandingTrap.tres` | safe_gap_size、safe_gap_position、wall_speed、spawn_distance、landing_time_ratio、spike_width |
| P28 节奏组合 | `P28_RhythmBurst.tres` | first_interval、pause_duration、speed、spawn_distance；final_pattern 是独立 Resource 引用 |

通用数据类型：`obstacle_pattern_data.gd`、`pattern_event.gd`。模板布局：`pattern_layouts.gd`，墙列：`pattern_walls.gd`。编译和检查：`pattern_compiler.gd`，变体：`pattern_modifier.gd`，生成与清理：`pattern_runner.gd`，手工组合及地形：`pattern_section.gd`、`pattern_section_data.gd`，恢复区：`recovery_section.gd`。菜单列表：`pattern_library.gd`。预览：`pattern_preview.gd`。试玩逻辑：`test/pattern_test.gd`。

地刺、横梁复用现有场景；`scenes/Shuriken.tscn` 只是现有 `components/dart.gd` 的场景封装。

## 修改参数

- 安全口：P14/15/16/24 改 `parameters.safe_gap_size` 和 `safe_gap_position`。位置表示离地高度，单位 px；P17 改 `gap_size` 与人工排列的 `gap_positions`，绝不随机抽取。
- 飞镖速度：单枚/斜线/混合模板改 `parameters.speed`，墙改 `wall_speed`。整个模板再乘 `speed_multiplier` 和难度速度系数。FAST=1.2，SLOW=0.85。移动方向为向量，Runner 使用单位向量乘速度。
- 难度：工作台下拉框覆盖本次编译的等级；资源的 `difficulty` 保存设计等级，供调用者传入。速度只在 0.92~1.08 之间变化，安全口每级缩小 10px。P01 刺宽每级变化 10%，P22 坑宽每级变化 5px，P18 高难度增加一枚。
- P17 默认难度 1/3/5 分别为 2/3/4 堵墙；间隔 2.3/2.0/1.7 秒；缺口 136/116/96px。顺序来自同一人工数组。
- Mirror：支持的资源勾选 `mirror=true`，或工作台选 MIRRORED，二者不会重复翻转。围绕离地 160px 的水平线翻转，`y'=-320-y`，同步翻转竖直运动方向。缺口也一起翻转。

| Modifier | 适用范围 |
|---|---|
| NORMAL、DOUBLE | 全部 12 个 |
| FAST、SLOW | 除纯静态的 P01、P08 外 |
| MIRRORED | P04、P14、P15、P16、P17、P18 |
| REVERSE | P17、P18；反转发射时间顺序，保持各事件相对出生距离 |

不支持的选项在界面禁用，直接编译也会报参数问题。DOUBLE 使用原数据编译两遍事件，中间保留所选 Recovery 的间隔，不复制磁盘上的模板文件。

## 创建新 Pattern

1. 在 FileSystem 新建 `ObstaclePatternData` Resource，保存为新的 `.tres`。
2. 若沿用布局，选择对应 `template`，复制该模板的 parameters 后修改。内置模板由 parameters 生成事件，`events` 数组只用于 CUSTOM，避免双重数据来源。
3. 若需要自由布局，选择 CUSTOM，在 `events` 添加 `PatternEvent`，设置 obstacle_scene、position_offset、spawn_time、speed、direction、optional_parameters。
4. 将资源拖到 PatternTest 根节点的 `custom_pattern`，F6 即可测试。要永久加入菜单，再更新 `pattern_library.gd` 的名称列表及测试场景索引范围。
5. 新障碍场景根节点使用 Node2D 子类。静态障碍可发送 `player_contact(body, damage)`；简单移动物体由 Runner 平移。如有自定义运动，实现 `advance(delta, player)`，Runner 每个物理步调用。已有 velocity 属性会收到速度向量。optional_parameters 的键必须是障碍节点实际拥有的属性。

Resource 只保存数据；Runner 不判断 P01/P17 等编号，因此新障碍不需要修改 Runner。物理碰撞、可破坏行为等由新障碍自身负责。

坐标原点在 Pattern 入口地面，向右为正 X，向上为负 Y，角色位置是脚底。CUSTOM 的 position_offset 是绝对局部出生坐标；内置移动模板会加上 `400 × spawn_time`，使各波相对匀速玩家保持配置的出生距离。start_delay 同时平移时间和 X。duration、length 是最小范围，编译器会扩大范围以容纳事件，Runner 在结束时清理剩余障碍。

## 手工组合与 Recovery

`ExampleSection.tres` 提供 P01 → Recovery → P08 → Recovery 的手工资源数组。Inspector 可重排或替换 entries，条目允许 ObstaclePatternData 或 RecoverySection。没有自动选择器，也没有制作正式关卡。

调用方式（Section 放在入口地面位置）：

```gdscript
var data = preload("res://patterns/library/ExampleSection.tres")
var section := PatternSection.new()
section.position = Vector2(140, 460)
add_child(section)
section.build(data.entries, player, 3, PatternModifier.Kind.NORMAL)
# 在关卡的物理帧里调用：
section.advance(delta, player)
```

`Recovery.tres` 的 duration 可调 0.5~2 秒，以基础跑速 400px/s 转成地面长度；滑铲加速时实际经过时间会缩短。退出 Pattern 会清理该 Pattern 障碍，避免追进后续恢复区。DOUBLE 的第五个 build 参数可传自选 Recovery；工作台会自动传入所选资源。

P28 的恢复窗口从第二枚飞镖保守预计通过角色区域之后开始；之后才生成 final_pattern。final_pattern 不允许再引用 P28，防止循环组合。

## 预览与可通过性边界

测试场景 F1 显示出生点/箭头、Pattern 边框、绿色安全口、红色坑与静态障碍范围、蓝色站立区域和参考单跳弧线。蓝线是运动尺度参考，**不是自动求出的通关路线**。也可打开 `test/PatternPreview.tscn`，在编辑器给 PatternPreview 节点替换 pattern 资源，查看全布局。正式场景没有添加此预览节点；Runner 的橙色出生预警属于障碍提示。

运动标尺直接读取当前 player.gd 常量：跑速 400px/s，滑铲峰值 620；起跳 -820、二跳 -790px/s；固定上升重力 2400、下落重力 2200px/s²，急降初速 1200px/s。点按即完整跳跃，松手不减高度。站立碰撞箱 46×66，滑铲高度 32px，二段翻滚碰撞箱 40×40。连续公式的单跳高度约 140px、时间约 0.70s、跨度约 279px，峰顶二跳理论总高度约 270px。60Hz 实测一段跳约 133px、二段额外升高约 124px，详见 `tests/jump/README.md`；公式不替代实际输入路线验证。

特殊间距：P08 用跑速 ×（峰顶急降时间 + 0.14s 容错），当前约 99px；P21 在刺后预留急降距离再确定飞镖相遇点；P22 默认坑宽 80px（当前单跳跨度约 29%），难度范围 70~90px；P24 使用墙相遇点加 `0.75 × 单跳时间 × 跑速` 安排后续刺，刺在开始时生成，能提前看见。P17 的墙间隔独立于墙速度，留出换位时间。

编译器检查正时间/速度、反应时间、非零运动方向、单跳跨度与碰撞宽度、安全口净高和二跳高度、坑边界/重叠、出生范围。不合格时工作台暂停并显示原因。

**全部 12 个模板仍标记 needs_manual_playtest=true。** 260 个受支持组合的参数检查与生成测试不构成联合路线证明。滑铲加速会改变相遇时间，任意参数修改也可能产生无解组合；还需无技能人工试玩，尤其是 P17、P21、P22、P24、P28 和镜像高位缺口。

下一步可以制作手工 Section 并记录通关路线；建议先完成这些人工验证、固定可用参数区间，再开发按规则选取 Pattern 的 Section Sequencer。

详细执行证据见 `tests/PATTERN_VALIDATION.md`。
