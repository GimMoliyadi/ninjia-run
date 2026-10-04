extends SceneTree

const ResourceChecks = preload("res://tests/godot/rig_action_resource_checks.gd")
const BindingChecks = preload("res://tests/godot/rig_action_binding_checks.gd")
const PreviewChecks = preload("res://tests/godot/rig_action_preview_checks.gd")
const VisualChecks = preload("res://tests/godot/rig_action_visual_checks.gd")

var _errors: PackedStringArray = []
var _assertions := 0


func _initialize() -> void:
	call_deferred("_validate")


func _validate() -> void:
	ResourceChecks.run(root, _check)
	BindingChecks.run(root, _check)
	PreviewChecks.run(root, _check)
	VisualChecks.run(root, _check)
	if _errors.is_empty():
		print("V2 动作契约通过：%d 条断言；八动作/53浮点轨/alpha鞋底/只读状态绑定/版本启停/连续预览。未实例化真实 Player，未运行 Gameplay 或渲染。" % _assertions)
	else:
		print("V2 动作契约失败：%d/%d 条断言。" % [_errors.size(), _assertions])
	quit(0 if _errors.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		if not _errors.has(message):
			push_error(message)
		_errors.append(message)
