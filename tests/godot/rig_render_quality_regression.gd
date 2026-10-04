extends SceneTree

const Rig = preload("res://visuals/rig_v2/visual_root_v2.tscn")
const LOGICAL_SIZE := Vector2i(960, 540)
const OUTPUT_SIZE := Vector2i(1280, 720)
const PLAYER_SCALE := Vector2(0.055, 0.055)
const EXPECTED_CHARACTER_TEXTURES := 18

var _failures := PackedStringArray()
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var logical := Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	var output := Vector2i(ProjectSettings.get_setting("display/window/size/window_width_override"), ProjectSettings.get_setting("display/window/size/window_height_override"))
	_check(logical == LOGICAL_SIZE, "高清输出不能改变逻辑视野")
	_check(output == OUTPUT_SIZE, "默认窗口应提供1280×720原生输出")
	_check(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items", "不能把低分辨率视口整体放大冒充高清")
	var rig: Node2D = Rig.instantiate()
	root.add_child(rig)
	_check(rig.scale.is_equal_approx(PLAYER_SCALE), "不能通过放大角色改变原有视觉比例")
	_check(rig.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "V2须使用带多级纹理的线性缩小过滤")
	var textures := {}
	for item in rig.find_children("*", "CanvasItem", true, false):
		if item is Polygon2D or item is Sprite2D:
			if item.texture != null and item.texture.get_width() > 1:
				_check(_uses_mipmapped_filter(item), "绘制节点不能覆写为无mipmap采样：%s" % item.name)
				textures[item.texture.resource_path] = item.texture
	_check(textures.size() == EXPECTED_CHARACTER_TEXTURES, "检查必须覆盖全部18张实际角色贴图")
	for path in textures:
		_check_texture(path, textures[path])
	rig.free()
	for failure in _failures:
		printerr(failure)
	print("RENDER_QUALITY checks=%d textures=%d failures=%d" % [_checks, textures.size(), _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _uses_mipmapped_filter(item: CanvasItem) -> bool:
	var current := item
	while current != null:
		if current.texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
			return current.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		current = current.get_parent() as CanvasItem
	return false


func _check_texture(path: String, texture: Texture2D) -> void:
	var image := texture.get_image()
	_check(image != null and image.has_mipmaps(), "运行时贴图缺少实际mipmaps：" + path)
	var source := Image.load_from_file(ProjectSettings.globalize_path(path))
	_check(source.get_size() == Vector2i(texture.get_size()), "贴图导入不应裁减原始分辨率：" + path)
	var config := ConfigFile.new()
	var error := config.load(path + ".import")
	_check(error == OK, "缺少可复现的贴图导入设置：" + path)
	if error != OK:
		return
	_check(config.get_value("params", "mipmaps/generate", false), "重新导入后必须保留mipmaps：" + path)
	_check(config.get_value("params", "compress/mode", -1) == 0, "保留无损纹理压缩：" + path)
	_check(config.get_value("params", "process/size_limit", -1) == 0, "禁止缩小源贴图尺寸：" + path)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
