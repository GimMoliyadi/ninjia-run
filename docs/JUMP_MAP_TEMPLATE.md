# 跳跃地图样板：踏石 · 棘林

正式入口是 `scenes/segment_jump_map.tscn`，主数据是 `patterns/library/Jump_Map_A.tres`。F5 的每轮热身后，飞镖、跳跃、绳索、平台和忍者图按种子换序；在 `tests/jump_map/JumpMapPractice.tscn` 按 F6 可以直接练习跳跃图。练习入口只缩短路线，复用正式游戏、角色、碰撞、镜头、HUD 和技能。

## 完整节奏

总长 28,800 px，400 px/s 时 72 秒，持续 620 px/s 时 46.45 秒。三段长度 9,840 / 9,600 / 9,360 px；共八波、44 段地刺和 41 根可站立石柱。

| 基准时间 | Wave / 内容 | 玩家学习与压力变化 |
|---|---|---|
| 0–7s | 起拍 · 五次稳跳 | 1 秒进入后，五个单刺教起跳节拍 |
| 7–15s | 紧拍 · 双刺成组 | 六组双刺，一次跳越整组 |
| 15–23s | 长短拍 · 看落点再起跳 | 宽间距双刺与较宽单刺交替，改变落点和等待时间 |
| 23–24.6s | 短喘息 · 落地拾金 | 平地、三枚金币，为新机制腾出注意力 |
| 24.6–32.6s | 初识石柱 · 越柱落顶 | 六根等高低柱，明亮柱顶提示可以落脚 |
| 32.6–40.6s | 高低错落 · 选择一跳或二跳 | 低柱与高于单跳顶点的柱子交替 |
| 40.6–48.6s | 连柱三步 · 踩稳再起跳 | 三组低高低连柱，用落顶重置跳跃次数 |
| 48.6–58.6s | 柱间生棘 · 连续换落点 | 三组柱间填刺；沿已经学会的柱顶路线连续动作 |
| 58.6–70.6s | 踏石终阵 · 越刺登高再连跳 | 四组“入口刺 → 低柱 → 高柱 → 回落柱”，最高柱交替抬升，组间间隔缩短 |
| 70.6–72s | 短出口 · 平地收步 | 短平地拾金，按 Entry / Exit 接下一块 |

高潮与前段的区别是：单组动作从三次落柱扩展到先越刺，再登柱；组数从三组升到四组，组间节拍从 3.2 秒收紧到 2.9 秒，柱宽由 4.2 个身宽收至 3.5 个身宽。第一根柱子降低到单跳高度的 0.55 倍，让越刺能够直接衔接上柱。

## 数据层级与五种 Pattern

`MapModuleData.sections → PatternSectionData.entries → JUMP_WAVE.parameters.phrases → PatternEvent → SpikeStrip / JumpPillar`。

Wave 沿用 `ObstaclePatternData`，由 `jump_wave_layout.gd` 编译有序动作句。每句只有布局数据，不持有计时器或角色引用。

| pattern | 参数 | 生成内容 |
|---|---|---|
| `single_spike` | `beat`, `width_ratio` | 一段地刺 |
| `spike_pair` | 上述 + `spacing_ratio` | 两段地刺，中间保留指定身宽的间距 |
| `pillar` | `beat`, `width_ratio`, `height_ratio` | 一根可落脚石柱 |
| `pillar_chain` | `beat`, `width_ratio`, `gap_ratio`, `heights` | 按高度数组排列石柱 |
| `mixed_chain` | 同上 | 相邻柱子间填入地刺，两侧保留边缘余量 |

`beat` 是相对 Wave 起点的基准秒数，横坐标为 `beat × RUN_SPEED`，不会随着玩家加速重排。宽度以 `BODY_SIZE.x` 为单位，高度以 `jump_height()` 为单位；连柱净间距以 `RUN_SPEED × jump_time()` 为单位。这些值都来自 `PlayerMotionProfile`。

```gdscript
parameters = {
    "phrases": [
        {"pattern": "mixed_chain", "beat": 0.3,
         "width_ratio": 4.2, "gap_ratio": 0.52,
         "heights": [0.6, 1.15, 0.7]}
    ]
}
```

资源使用 `template = "JUMP_WAVE"`、`start_delay = 0`、`supports_speed = false`。`duration` 决定 Wave 地面长度；不要通过旧模板的 `length` 字段拉长尾部。此模板当前仅支持 NORMAL 固定布局；游戏中正常滑铲、跳跃动量仍然生效。

## 生成、碰撞与可读性

模块构建时同步编译全部 Wave。静态障碍提前约 979 px 实例化，沿用距离型 `PatternRunner`，没有临近红圈或随机出生。波次结束时回收自己的障碍；地图回收和重开由正式驱动处理。

`SpikeStrip` 复用现有地刺伤害与可破坏行为；`JumpPillar` 是实心平台，上表面安全、侧面阻挡。墨绿石身和亮色柱顶区分可落脚表面，铜色尖端标出刺带危险。柱子不依赖击碎来通过。

编译器检查重叠、非正尺寸、柱高上限、刺带宽度和 Wave 出口余量。这些检查只拦截明显错误，不能证明连续动作可达。正式地图已用真实输入控制器检查单跳、二跳、急降落柱和滑铲加速。

## 复用步骤

1. 复制一组 `JumpMap_Wave*.tres`，先写自然语言 `display_name`、`instruction` 与阶段 tags，再编辑动作句。先教单一障碍，随后重复、变化，最后组合。
2. 在 Section 中按顺序引用 Wave。`stages` 与 `stage_entries` 对齐，喘息使用独立 `RecoverySection`，不把额外空地塞进每波尾部。
3. 新建 Map 数据引用 Section，复制薄场景入口并修改 `module_data_path`。地面、出口和 F1 信息由现有运行时自动构建。
4. 要接入正式路线时，给 `ChunkKind` 和 `CHUNK_SCENES` 追加同索引入口，再配置路由。不要改旧索引，也不在 `game.gd` 中写地图专属生成逻辑。
5. 先检查编译、真实接缝和重开回收，再实跑 400 / 620 与实际滑铲加速。只看数值通过还不够：检查普通渲染窗口中能否读出下一落点、组间区别和高潮压力。

当前 agent 实跑结果见 [验证记录](../tests/JUMP_MAP_VALIDATION.md)。所有 Wave 保留 `needs_manual_playtest = true`，等待人的手感评价。
