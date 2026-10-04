# 地刺与柱子地图验证

日期：2026-09-13。Godot 4.7.2，60 Hz 物理，NORMAL / difficulty 1，seed 20260913。以当前磁盘中的 `Jump_Map_A` 为准。

## 地图与实跑结果

地图长 28,800 px，三个 Section、八个 Wave，44 段地刺、41 根可落脚石柱。所有布局在模块创建时同步编译，提前约 979 px 实例化。

| 条件 | 地图用时 | 生成 | 受伤 | 柱顶落地 | 柱侧阻挡 | 屏内出生 |
|---|---:|---:|---:|---:|---:|---:|
| 400 px/s，无头与真实渲染 | 72.00s | 85/85 | 0 | 41 | 0 帧 | 0 |
| 持续 620 px/s，无头与真实渲染 | 46.45s | 85/85 | 0 | 41 | 0 帧 | 0 |
| 基础 400，真实滑铲输入，无头 | 68.28s | 85/85 | 0 | 41 | 0 帧 | 0 |

滑铲路线触发 9 次地面加速，实测峰值 620 px/s；空中动量按正式角色逻辑自然衰减。三条路线均未使用战斗技能，最终生命 50。出口回收检查通过，各 Wave 均完成且未残留障碍节点。

`jump_map_playtest.gd` 使用继承自 `test_world.tscn` 的单图练习入口；仅把路线设为热身 → Jump_Map_A → 出口。角色、游戏驱动、HUD、镜头、碰撞均为正式实现。输入控制器通过 `Input.action_press/release` 执行跳跃、二跳、急降与滑铲，不写角色位置、垂直速度、生命或碰撞状态；620 检查只设置基础跑速作为边界条件。

## 实际渲染与调优

使用 RTX 4050 / OpenGL Compatibility 正常窗口完整实跑，并检查单刺、双刺、低柱、高低柱、组合与出口的截图。

- 最初高潮的入口刺与第一根柱子脱节，400 路线出现柱侧阻挡。将首柱从刺后 0.5 基准秒提前到 0.3 秒，同时首柱从单跳高度的 0.65 倍降至 0.55 倍，形成越刺直接上柱的动作。
- 620 路线曾在柱间填刺处受伤。定位到输入控制器越过柱沿后提前为下一片刺带使用二跳，尚未落稳就离柱；改为完成当前柱顶落地再判断下一动作。保留正常碰撞与伤害断言。
- 滑铲与高速窗口均可完整通过；单刺/双刺的暖色尖端、石柱的亮色可落脚顶面可区分。高潮每组包含入口刺和三次落柱，四组连续推进，比前一波更密。
- F1 最初的测试按键释放过早，未覆盖完整物理输入帧。改为独立按下/释放事件并跨物理帧持键后，实际渲染已显示自然语言 Map / Section / Wave；正式 F1 处理代码没有改动。

截图：

- [双刺节奏与 F1](artifacts/jump-map/01-620.png)
- [低柱教学落顶](artifacts/jump-map/04-400.png)
- [柱间填刺](artifacts/jump-map/07-400.png)
- [组合高潮](artifacts/jump-map/09-620.png)
- [短出口](artifacts/jump-map/10-620.png)

## 必要验证

- `jump_map_module_check.gd`：正式路线第二槽位、飞镖 → Jump 接缝、重复模块接缝、Section 连续、总长、八波完整编译、障碍提前生成距离、F1 输入及自然语言文本、暂停冻结、恢复与重开清理，通过。
- `jump_map_playtest.gd`：上述速度条件的完整输入实跑、85 个障碍生成、受伤、落柱、阻挡、屏内出生与出口回收，通过。
- `dart_map_module_regression.gd`：共享编译器与正式路由接入后的飞镖模块定向检查，通过。
- `game.gd --check-only`：脚本解析通过。

没有运行整套 regression。可复现命令（将 Godot 替换为本机可执行文件）：

```text
Godot --headless --path . --fixed-fps 60 --script tests/godot/jump_map_module_check.gd
Godot --headless --path . --fixed-fps 60 --script tests/godot/jump_map_playtest.gd
Godot --headless --path . --fixed-fps 60 --script tests/godot/jump_map_playtest.gd -- --speed=620
Godot --headless --path . --fixed-fps 60 --script tests/godot/jump_map_playtest.gd -- --boost
Godot --path . --script tests/godot/jump_map_playtest.gd -- --capture --speed=620
```

## 验证边界

这是 agent 控制的真实游戏渲染与物理实跑，不是人的手感验收。桌面 computer-use 工具返回 native pipe unavailable，因此未使用操作系统按键注入；实际控制使用 Godot 输入事件。所有 Wave 继续保留 `needs_manual_playtest = true`。

结构检查验证了飞镖与跳跃模块的真实场景接线和接缝；本次整图调优使用单图入口，没有重新实跑飞镖全程。验证证明以上输入路线可达，不保证任意操作、任意速度或未来变体都可通过。

手动体验入口：在 Godot 打开 `tests/jump_map/JumpMapPractice.tscn` 按 F6；F1 看当前波次，R 重开。
