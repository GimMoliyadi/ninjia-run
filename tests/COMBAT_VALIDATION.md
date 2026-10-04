# 血条与战斗机制验证记录

验证日期：2026-09-09。环境：Windows、Godot 4.7.2、60 Hz 固定帧率；截图使用 OpenGL Compatibility / NVIDIA RTX 4050 实际渲染。

## 实现与检查范围

- 满血隐藏血条，受伤显示，部分回血保持显示，满血隐藏；死亡、重开恢复正确状态。原实现只有 HUD 生命数字，没有血条绘制组件。
- J 挥刀、K/Shift 螺旋丸、Q 武器主动技能（**三颗环绕火球**），及三个可点击按钮。技能各自具有冷却，目标销毁只结算一次。
  - 修正（2026-09-11）：技能激活后角色周围**始终维持三个环绕火球槽位**；
    其中一颗向目标发射后脱离角色成为独立攻击弹，原位立刻补上新的环绕火球。
    环绕数在技能持续期间恒为 3，同屏攻击火球数**可以超过 3**。
  - 修正前 `cast_fireballs()` 只生成 3 个一经发射就不补位的投射物，
    环绕数 3→0 衰减，屏幕上「总共只有三颗火球」。
- 火球分配目标、失效重选、平滑转向、真实命中爆炸与无目标超时。螺旋丸沿移动路径检查命中，穿透竹刺/飞镖，保留结构横梁。
- 飞镖四种阵列、预警、固定瞄准、数量上限、独立平地间隔、死亡暂停和重开清理。
- 自查重点：延迟销毁期间避免重复得分；目标释放后的引用有效性；高速碰撞；暂停时计时冻结；重开立即脱离旧节点；关卡提示与技能 HUD 不重叠。

## 已通过

执行：`Godot --headless --path . --fixed-fps 60 --script tests/godot/<文件>.gd --quit-after 4000`。通过要求退出码为 0、没有 SCRIPT ERROR/ERROR，且出现测试成功标记，不能仅凭退出码判定。

| 测试 | 结果 |
|---|---|
| combat_regression.gd | 通过：血条、治疗、无敌帧、刀范围、螺旋丸穿透、火球环绕槽位与独立投射物、冷却、J/Q/K/P/R 实际输入、死亡和重开 |
| fireball_skill_regression.gd | 通过：激活后 orbit=3、发射后仍=3、连发后仍=3、projectile 可 >3、技能结束停止发射、restart 清空 |
| dart_patterns_regression.gd | 通过：飞镖墙缺口、连续动作句、数量上限；400/620 像素/秒下，不用技能，按预警读位，无伤抵达出口 |
| authored_route_regression.gd | 通过：按首圈实际段数生成验证，适配飞镖长段，保留全部场景和重开可复现检查 |
| rhythm_route_generator_regression.gd | 通过 |
| encounter_generation_regression.gd | 通过 |
| area_signal_regression.gd | 通过 |
| player_jump_regression.gd | 通过 |
| slide_momentum_regression.gd | 通过 |
| camera_lock_regression.gd | 通过 |

另外实际执行了 Godot 无头导入及 1800 帧启动烟测。导入时已有编辑器占用 MCP 的 9876 端口，插件报告端口占用；游戏脚本导入正常。烟测无脚本错误。

## 原有验证缺口（4 项，不计为通过）

| 测试 | 失败原因 |
|---|---|
| rope_regression.gd | 旧测试用第二次 S 期待绳下翻回绳上；现有实现明确吞掉绳下 S，使用 Space 翻回 |
| boost_pool_regression.gd | 旧测试连续设置下翻缓冲期待上下翻转与保速，与当前绳下 S 规则冲突 |
| player_visual_regression.gd | 旧测试访问当前 scarf.gd 不存在的 WIND_SPACING；另有锚点断言失败 |
| scarf_history_regression.gd | 旧测试直接调用当前 scarf.gd 不存在的 _process；当前飘带使用 _physics_process，并有旧参数断言冲突 |

为区分回归，在临时副本中移除了本次 player.gd 新增的血量信号、治疗、刀输入及 player.tscn 新增的刀/血条节点，再运行以上四项，复现相同失败。当前目录没有可用的独立提交基线，这属于移除本次相关改动的对照验证，不是历史提交验证。没有修改原绳索/飘带实现或跳过、弱化这些测试。

因此本次新功能的针对性验证通过，但全套测试尚未全绿，不能宣称整个项目已达到发布验收标准。自动通行仅覆盖飞镖段上述两种速度与操作策略；整体难度和手感仍需玩家试玩反馈。

## 后续修正：绳轴翻转

将屏幕平面旋转改为绳轴侧视投影，身体高度先收缩再展开，横向宽度固定。碰撞保持目标侧切换；飞镖检测不再把换侧瞬移补成连续受击路径，目标侧仍正常扣血。

新增 `rope_flip_projection_regression.gd`：双向切换、动画中点、绳线支点、横向宽度、原侧飞镖不误伤和目标侧仍受伤；无头与真实 OpenGL 渲染运行通过。同时重新运行 combat、dart_patterns 和 slide_momentum 三项，均通过。上面的四项原有测试缺口仍保留。

## 渲染截图

执行：`Godot --path . --fixed-fps 60 --script tests/godot/combat_preview.gd --quit-after 300`。脚本真实启动游戏、触发伤害/回血和技能，并保存 viewport 图像。

- [满血隐藏](artifacts/full-health.png)
- [受伤与技能](artifacts/combat-damaged.png)
- [满血恢复后隐藏](artifacts/healed.png)
- [飞镖阵列](artifacts/dart-wave.png)
- [完整回归输出](artifacts/regression-results.json)

截图目录设置 `.gdignore`，避免证据图片被导入为游戏资产。

## 2026-09-12 火球持续槽位复核

- 根因：旧实现把三颗环绕火球本身当作仅有的三发攻击弹，发射后槽位随弹体离开，
  没有常驻视觉槽位与独立 projectile 的分层。
- 当前实现：`orbit_fireball.gd` 保持 3 个常驻槽位；`player_combat.gd` 以共享
  `0.42s` 节奏轮转一个槽位；每次创建独立 `ability_projectile.gd` 攻击弹。
- `fireball_skill_regression.gd` 在 Godot 4.7.2 / 60 FPS 下通过：激活、首次发射、
  连续发射均保持 orbit=3；同屏 projectile 可超过 3；6.0s 技能结束后停止新发射；
  已发射弹按 4.0s 生命周期结束；restart 清空 orbit/projectile/累计数/技能与冷却计时。
- `combat_regression.gd` 同轮通过：追踪、碰撞、伤害、冷却、暂停、死亡和重置未回归。
