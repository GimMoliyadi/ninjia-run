# JumpTest：跳跃与团身穿缝

打开 `res://tests/jump/JumpTest.tscn`，F6 运行当前场景。所有节点、碰撞、相机和按键都已配置，不需要操作 Inspector。

开始时暂停，按 Enter 开始。R 重开后也会暂停，方便准备。

| 操作 | 按键 |
|---|---|
| 一段跳 / 空中再次按键触发二段跳 | Space |
| 急降 / 滑铲 | S |
| 空中急降后排队落地滑铲 | 快速连按两次 S |
| 开始 / 暂停 | Enter 或 P |
| 重开当前项目 | R |
| 上一项 / 下一项 | `[` / `]`，或 PgUp / PgDn |
| 隐藏 / 显示碰撞框 | F1 |

底部菜单有五个独立项目：24px 矮块、96px 高块、250px 缺口、58px 团身通道、高台与横梁。蓝框是正常碰撞体，橙框是团身碰撞体。通道宽松于 40px 团身轮廓，但不足以容纳 66px 站姿。失败可立即重开，不需要跑完整关卡。

## 本轮改变

- 根据最新试玩反馈，取消按住时长控制高度：点按一次即完成完整跳跃，松手不改变上升速度或重力。一段跳达到此前长按的最高点，二段跳略低；需要提前落地时按 S 急降。
- 原先二段跳只是 AIRBORNE 中再次赋速。现在有 AirState：NONE、FIRST_JUMP、DOUBLE_JUMP_ROLL、SECOND_JUMP、FALL；外层 MovementState 保留。
- jumped 信号携带 1/2，视觉层能区别一段跳拉伸与二段翻滚。二段跳会把当前下降速度换成独立的向上初速，保留水平动量，同时取消急降与落地滑铲队列。
- ActionPivot 在 0.32 秒内完成一周旋转；旋转中心位于团身碰撞体中心。Orientation 继续单独处理 Rope 的翻身投影，不旋转它。落地或挂绳会中断空中翻滚。
- ninja_body.gd 新增 double_jump_roll 姿势：头靠近躯干、手脚收拢，轮廓在约 40px 范围内。团身时刀的外观临时收起，战斗逻辑不变。
- 碰撞箱以脚底为基准缩小。翻滚时间结束与碰撞箱恢复是两件事：先结束转圈；若普通矩形会撞到实体墙，则继续团身，每个物理帧检查，离开窄处后立即恢复。没有用超时强行撑开，也没有位移补偿或穿墙。
- Scarf 继续使用原世界坐标链条，锚点改为实际 Neck 的全局位置，更新在身体姿势之后，能跟随 ActionPivot 的旋转。残影与游戏中的 Sword 引用同步更新。

场景结构：

```text
Player [player.gd]
└─ PlayerVisual [visuals/player_visual.gd]
   └─ Orientation
      └─ ActionPivot
         └─ Body [visuals/ninja_body.gd]
            ├─ Neck
            │  └─ Scarf
            └─ Sword
```

## 集中参数

以下均在 `player.gd` 文件顶部。无需用户修改，反馈后由开发侧调整。

| 参数 | 当前值 | 含义 |
|---|---:|---|
| JUMP_SPEED | -820 px/s | 一段起跳速度 |
| ASCENT_GRAVITY | 2400 px/s² | 固定上升重力，不依赖按住时长 |
| FALL_GRAVITY | 2200 px/s² | 放慢自然下降，上一版为 4200 |
| SECOND_JUMP_SPEED | -790 px/s | 二段独立起跳速度 |
| DOUBLE_JUMP_ROLL_DURATION | 0.32 s | 翻滚动作时间 |
| ROLL_WIDTH × ROLL_HEIGHT | 40 × 40 px | 团身碰撞箱 |
| PLAYER_WIDTH × PLAYER_HEIGHT | 46 × 66 px | 正常碰撞箱 |
| PLAYER_WIDTH × SLIDE_HEIGHT | 46 × 32 px | 滑铲碰撞箱，保持原尺寸 |
| FAST_FALL_SPEED | 1200 px/s | 急降初速，保持原值 |
| COYOTE_TIME / JUMP_BUFFER_TIME | 0.10 / 0.15 s | 沿用原计时器与消费逻辑 |

60Hz 实际物理运行的一段跳最高点：

| 按住时长 | 约 17ms | 67ms | 133ms | 200ms | 400ms |
|---|---:|---:|---:|---:|---:|
| 高度 | 133px | 133px | 133px | 133px | 133px |

当前二段跳从触发点再升高约 123.5px，为一段跳约 93%。自然下降约 0.35 秒，一段跳总滞空约 0.683 秒；S 急降仍立即给予至少 1200px/s 的向下速度。优先反馈下降是否太飘、二段修正力度、急降落点和穿缝难度。

## 验证记录（2026-09-10）

- `jump_control_regression.gd`：五种按住时长的高度一致且达到此前最高点；松手不改变加速度；二段高度为一段的 90%~100%；自然下降时间至少 0.32 秒；下落时二段跳重新向上；jumped 索引；团身姿势与约一周旋转；Orientation 不转；空中恢复、低顶阻止扩张、出顶恢复；落地缓冲、真实离台土狼跳；提前落地与重开清理翻滚；Neck 锚点。
- `jump_course_regression.gd`：五条真实输入路线都到达终点。第四项实际经历 compact_in_gap、waiting_in_gap、restored；没有二段跳无法越过第三项，没有团身无法穿过第四项。已用图形模式运行并截图，不只做静态检查。
- 现有 player_jump、fast_fall、slide_momentum、rope_flip_projection、combat、dart_patterns 回归通过。
- Pattern 的 260 个受支持参数组合与 12 项切换/重开回归通过。没有新增 Pattern，也没有把 JumpTest 改成正式入口。跳跃手感变化后仍需重新人工试玩 Pattern，参数检查不是完整路线证明。
- MCP 实际运行 JumpTest，输入 Space 后读到 FIRST_JUMP 与 46×66，再次输入后读到 DOUBLE_JUMP_ROLL、40×40、ActionPivot 旋转角约 1.96rad。读取运行树确认新层级，最终游戏错误日志为 0 条。
- MCP 原键盘注入只填 keycode，无法匹配项目已有物理键映射；在 runtime_bridge.gd 补填 physical_keycode 后完成真实按键验证，没有改玩家键位。

相关命令：

```powershell
$godotExe = 'C:\Users\30858\Desktop\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --fixed-fps 60 --script tests/godot/jump_control_regression.gd
& $godotExe --headless --path . --fixed-fps 60 --script tests/godot/jump_course_regression.gd
& $godotExe --path . --fixed-fps 60 --script tests/godot/jump_course_regression.gd -- --capture
```

截图：`tests/artifacts/jump-roll.png`、`jump-gap-wait.png`、`jump-gap-exit.png`、`jump-mcp-roll.png`。

未宣称完整旧测试套通过：旧 player_visual/scarf_history 测试依赖此前已不存在的 WIND_SPACING/history 接口，本轮没有为它们改造围巾算法。此次新增测试覆盖当前围巾锚点与翻滚姿势。自动路线通过不能代替实际手感验收。
