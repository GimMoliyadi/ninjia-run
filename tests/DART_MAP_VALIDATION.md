# Dart_Map_A 完整地图验证 · 2026-09-13

## 范围与结果

正式入口为 `project.godot → test_world.tscn → game.gd → segment_darts.tscn`。
本次只运行地图接线检查及必要实跑，没有执行整套回归。

- 地图长度 29,280 px，Section 长度依次 9,520 / 10,400 / 9,360 px。
- 八波共 76 个相遇节拍、214 枚飞镖；所有计划在模块创建时完成。
- 常速 400：73.2 秒；持续峰值 620：47.23 秒（仅指模块内部经过时间）。
- 固定种子 20260913，正常角色物理、正常碰撞/血量，不使用任何攻击技能。
- 测试只注入跳跃、急降和滑铲输入，不推进玩家坐标、不传送、不锁血、不关闭碰撞。
- 400 与 620 的定向实跑均 214/214 枚生成、屏内出生 0、受伤 0、结束血量 50。
- 真实滑铲输入实跑完成 20 次滑铲指令，214/214 枚生成、屏内出生 0、受伤 0；同时覆盖空中动量继承、地面减速。
- 同屏存活峰值 12 枚，出口无飞镖残留。暂停时玩家位置与 Wave 时钟不变；恢复继续，重开清空旧飞镖并重建完整地图。
- 两份模块按真实 Entry/Exit 重复放置，接缝一致；三个 Section 内接缝一致。
- Godot 4.7.2；实际渲染使用 OpenGL Compatibility / RTX 4050。正式窗口连续实跑两轮，第二轮为调好后真实滑铲版本，退出码 0。
- 无头结果与最终正式渲染运行均未输出 GDScript 运行错误。

## 实际观察与调整

第一轮窗口完整观察了单镖、墙阵、换位、混合高潮与出口，按真实进度捕获画面。发现高潮的低镖与高门衔接过紧；同时峰值实跑暴露第二、三波交界的连续低镖间隔不足。

调整第三波开头为高镖，承接上一波低镖；高潮采用低镖后 0.28 个基准秒接中门，交替使用 110/140 的缺口中心。高低大幅换位仍在墙阵阶段和混合前半段表达；高潮专注一次跳跃接连处理低镖与门。修改后重新完成两档速度及真实滑铲实跑，并检查最终渲染截图。

截图在 `tests/artifacts/dart-map/`：`00-400.png`～`10-400.png` 为最终正式窗口滑铲实跑，各时点覆盖三个 Section 和出口。这些是实际渲染帧，没有拼接障碍或修改截图。

由代理注入输入的实跑与画面审看不等于真人手感验收，资源的 `needs_manual_playtest` 保持 true。

## 必要命令

```text
Godot --headless --path . --fixed-fps 60 --script tests/godot/dart_map_module_regression.gd
Godot --headless --path . --fixed-fps 60 --script tests/godot/dart_map_playtest.gd
Godot --headless --path . --fixed-fps 60 --script tests/godot/dart_map_playtest.gd -- --speed=620
Godot --headless --path . --fixed-fps 60 --script tests/godot/dart_map_playtest.gd -- --boost
Godot --path . --script tests/godot/dart_map_playtest.gd -- --boost --capture
```

`darts_playtest_capture.gd` 已转为同一实跑脚本的截图入口。旧 `dart_section_*`、`official_darts_playthrough.gd` 中针对 `Dart_Introduction` / 单 Section 的验证属于历史记录，不作为当前地图通过证据。

## 距离节拍契约

`DART_WAVE.parameters.volleys` 顺序固定，每拍包含 `beat` 与 `height` 或 `gap/gap_size`。beat 以 400 px/s 为基准，表示相遇的地图位置，而不是玩家到入口以后再等待的发射时间。

提前飞行时间为 `2 × PlayerMotionProfile.jump_time()`，约 1.40 个基准秒。出生时距离角色约 728～854 px。运行时用实际前进距离推进飞行，因此加速不漏拍，也不在玩家附近重新定位飞镖；暂停停止，重开从原数据重建。只为进入预飞行范围的事件实例化节点。碰撞保留移动路径扫掠；当帧新生飞镖只推进出生后剩余的时间。

出生坐标允许位于所属 Wave 外，模块长度由 Wave 的显式时长与 Recovery 决定。Wave 结束不提前删仍在飞行的飞镖，越过玩家后自然回收。

