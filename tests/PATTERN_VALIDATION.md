# Pattern 验证记录

环境：Windows、Godot 4.7.2 stable、Compatibility 渲染。日期：2026-09-09。

## 已执行

- 开始时通过 Godot MCP 读取 player.tscn 场景与 CharacterBody2D 参数，并检查现有玩家、Camera、地形、飞镖和伤害接口。
- 分组运行 P01/P04/P08、P14/P15/P16、P17/P18/P21、P22/P24/P28，均实际创建玩家、地形与障碍。
- 最终 `pattern_smoke.gd` 再跑全部 12 个：每个模板事件总数与实际生成数一致，输出 `Pattern smoke passed`，退出 0。这是生成、更新与清理冒烟测试，不是无伤通关。
- `pattern_data_regression.gd`：260 个受支持的模板/难度/Modifier 组合通过；检查不支持变体拒绝、原资源不被修改、DOUBLE 恢复间隔、REVERSE、Mirror、P17 数量、过窄缺口/过宽坑/过短预警/嵌套 P28 拒绝。
- `pattern_test_regression.gd`：12 个选项切换，首次生成，暂停后重开、回血、旧 Section 清理、DOUBLE 与最终障碍清理；另测 CUSTOM 的新 Node2D 场景生成与默认移动。
- 现有 `fast_fall_regression.gd`、`dart_patterns_regression.gd`、`combat_regression.gd` 均通过。原飞镖回归覆盖的是现有游戏弹幕，不代表新 12 模板的路线已验证。
- MCP 实际运行 `res://patterns/test/PatternTest.tscn`，用按键切换到 P17、暂停/逐帧，读取运行树、get_test_status 和截图。截图在 `tests/artifacts/pattern-test.png`。
- 修复开发过程中发现的类型推断错误后重新启动；最终通过 MCP 读取当前游戏日志，error 过滤结果为 0 条。

## 复现命令

项目目录下，用本机 Godot 可执行文件执行：

```powershell
$godotExe = 'C:\Users\30858\Desktop\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --fixed-fps 60 --script tests/godot/pattern_data_regression.gd
& $godotExe --headless --path . --fixed-fps 60 --script tests/godot/pattern_test_regression.gd
& $godotExe --headless --path . --fixed-fps 60 --script tests/godot/pattern_smoke.gd
```

不要仅凭进程返回 0 判断成功；Godot 脚本异常有时不返回非零，需要同时确认成功标记和无 SCRIPT ERROR。

## 未验证范围

全部 12 个的无伤通关与手感、260 种组合的完整输入路线、滑铲峰值速度下的路线、使用者任意修改参数后的可通过性，均未证明。资源和工作台均保留人工试玩标记。

没有改造正式关卡入口，没有运行完整旧测试套。独立 import 的编辑器提示 MCP 9876 已被原编辑器占用；游戏运行桥使用 9877。测试场景仅在编辑器构建中启用桥，自动回归关闭桥以避免争用端口。
