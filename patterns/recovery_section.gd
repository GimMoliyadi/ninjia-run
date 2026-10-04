@tool
class_name RecoverySection
extends Resource

@export_range(0.5, 2.0, 0.1) var duration := 1.0

# 人类可读名称，用于 F1 调试覆盖层与人工试玩反馈。
# 例如 "喘息" / "出口喘息"。留空时调试信息显示默认的 "喘息"。
@export var recovery_label := ""

# 可选：在本段地面上铺一排金币，长度按金币数量决定。
#
# 用途：让玩家一眼看出「这里可以喘息」，同时提供低压力内容。
# 金币不是强制障碍，不接触也不会失败。
# 0 表示本段不放金币。
@export_range(0, 12, 1) var coin_count := 0

# 相邻两枚金币的水平间距。
# 默认 0 时用 PlayerMotionProfile 的跳跃跨度的一半推导 ——
# 这是「跑动中自然经过」的间距，不需要额外操作。
@export var coin_spacing := 0.0

func distance(run_speed: float) -> float:
	return duration * run_speed
