# SINGLE_JUMP Section 验证记录

- 日期：2026-09-12
- 正式接线：`ChunkKind.SINGLE_JUMP → segment_single_jump.tscn → SectionChunk → Jump_A.tres`
- 设计速度：`PlayerMotionProfile.RUN_SPEED`（400 px/s）
- 技能：不要求使用
- Variant：Jump_A
- Difficulty：1（各 Pattern 可声明自身难度）
- Wave：基础单跳 → 单跳加强 → 短喘息 → 长长短短长 → 连续单跳高潮 → 短出口
- 自动检查：按本轮要求仅执行 Godot parse/start smoke 与一次正式 `test_world.tscn` smoke run
- 人工试玩：待用户验证节奏、摄像机手感、回血速度与段间 seam
