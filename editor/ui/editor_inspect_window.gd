extends Window
## 可浮动「导航 / 预览」窗：上半小地图，下半装饰物 3D 预览（对齐 WE 左侧栏职责，不钉死侧栏）。


signal closed_by_user
signal minimap_clicked(norm_uv: Vector2) ## 0..1，地图 UV（x→东，y→北）
signal preview_params_changed(variation: int, angle_deg: float, scale: float, random_var: bool)

const PREVIEW_DIST_DEFAULT := 450.0 ## WE 像素感距离；内部换算到 Godot 相机
const WORLD_SCALE := 0.01 ## 与 Wc3Coords.WORLD_SCALE 近似：预览用本地尺度

@onready var _minimap_tex: TextureRect = %MinimapTex
@onready var _chk_buildings: CheckBox = %ChkBuildings
@onready var _chk_units: CheckBox = %ChkUnits
@onready var _chk_viewport: CheckBox = %ChkViewport
@onready var _preview_title: Label = %PreviewTitle
@onready var _subviewport: SubViewport = %PreviewViewport
@onready var _model_root: Node3D = %ModelRoot
@onready var _preview_cam: Camera3D = %PreviewCamera
@onready var _chk_random: CheckBox = %ChkRandom
@onready var _var_label: Label = %VarLabel
@onready var _var_prev: Button = %VarPrev
@onready var _var_next: Button = %VarNext
@onready var _anim_label: Label = %AnimLabel
@onready var _dist_label: Label = %DistLabel
@onready var _dist_spin: SpinBox = %DistSpin
@onready var _angle_label: Label = %AngleLabel
@onready var _angle_spin: SpinBox = %AngleSpin
@onready var _scale_label: Label = %ScaleLabel
@onready var _scale_spin: SpinBox = %ScaleSpin

var _catalog: Wc3IdCatalog
var _cache: MapModelCache
var _type_id: String = ""
var _variation: int = 0
var _num_var: int = 1
var _angle_deg: float = 270.0
var _scale: float = 1.0
var _random_var: bool = true
var _minimap_image: Image
var _viewport_uv: Rect2 = Rect2()
var _show_viewport_rect: bool = true


func _ready() -> void:
	transparent = false
	unfocusable = false
	always_on_top = true
	close_requested.connect(_on_close)
	_wire()
	_apply_locale()
	if not EditorI18n.locale_changed.is_connected(_on_locale):
		EditorI18n.locale_changed.connect(_on_locale)
	_dist_spin.value = PREVIEW_DIST_DEFAULT
	_angle_spin.value = _angle_deg
	_scale_spin.value = _scale
	_chk_random.button_pressed = _random_var
	_chk_viewport.button_pressed = true
	_chk_buildings.button_pressed = true
	_chk_units.button_pressed = true
	_refresh_var_label()
	_apply_preview_camera()


func setup(catalog: Wc3IdCatalog, cache: MapModelCache) -> void:
	_catalog = catalog
	_cache = cache


func _wire() -> void:
	_minimap_tex.gui_input.connect(_on_minimap_gui)
	_chk_viewport.toggled.connect(func(on: bool) -> void:
		_show_viewport_rect = on
		_redraw_minimap_overlay()
	)
	_chk_random.toggled.connect(func(on: bool) -> void:
		_random_var = on
		_emit_params()
	)
	_var_prev.pressed.connect(func() -> void: _step_variation(-1))
	_var_next.pressed.connect(func() -> void: _step_variation(1))
	_dist_spin.value_changed.connect(func(_v: float) -> void: _apply_preview_camera())
	_angle_spin.value_changed.connect(func(v: float) -> void:
		_angle_deg = v
		_apply_model_xform()
		_emit_params()
	)
	_scale_spin.value_changed.connect(func(v: float) -> void:
		_scale = v
		_apply_model_xform()
		_emit_params()
	)


func _on_locale(_loc: String = "") -> void:
	_apply_locale()


func _apply_locale() -> void:
	title = EditorI18n.t("EDITOR_INSPECT_TITLE")
	_chk_buildings.text = EditorI18n.t("EDITOR_MINIMAP_SHOW_BUILDINGS")
	_chk_units.text = EditorI18n.t("EDITOR_MINIMAP_SHOW_UNITS")
	_chk_viewport.text = EditorI18n.t("EDITOR_MINIMAP_SHOW_VIEWPORT")
	_chk_random.text = EditorI18n.t("EDITOR_PREVIEW_RANDOM_VAR")
	_dist_label.text = EditorI18n.t("EDITOR_PREVIEW_DISTANCE")
	_angle_label.text = EditorI18n.t("EDITOR_PREVIEW_ANGLE")
	_scale_label.text = EditorI18n.t("EDITOR_PREVIEW_SCALE")
	_refresh_var_label()
	if _type_id.is_empty():
		_preview_title.text = EditorI18n.t("EDITOR_PREVIEW_EMPTY")


func _on_close() -> void:
	closed_by_user.emit()
	hide()


## 用地形高度场重绘小地图（层高着色 + 水）。
func refresh_minimap(hf: Wc3Heightfield) -> void:
	if hf == null or hf.width < 2 or hf.height < 2:
		_minimap_tex.texture = null
		return
	var w: int = hf.width
	var h: int = hf.height
	# 限制预览分辨率，大图仍清晰
	var max_side := 256
	var scale_x: float = float(max_side) / float(w)
	var scale_y: float = float(max_side) / float(h)
	var s: float = minf(scale_x, scale_y)
	var iw: int = maxi(int(round(w * s)), 1)
	var ih: int = maxi(int(round(h * s)), 1)
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	var min_l := 99
	var max_l := 0
	for i in range(hf.layer_heights.size()):
		var lv: int = int(hf.layer_heights[i])
		min_l = mini(min_l, lv)
		max_l = maxi(max_l, lv)
	var span: float = maxf(float(max_l - min_l), 1.0)
	for py in range(ih):
		var iy: int = clampi(int(float(py) / float(ih) * float(h)), 0, h - 1)
		# 图像 y 向下；地图 y 向上 → 翻转
		var src_y: int = h - 1 - iy
		for px in range(iw):
			var ix: int = clampi(int(float(px) / float(iw) * float(w)), 0, w - 1)
			var idx: int = src_y * w + ix
			var lv: int = int(hf.layer_heights[idx]) if idx < hf.layer_heights.size() else 2
			var t: float = (float(lv) - float(min_l)) / span
			var col := Color(0.18 + t * 0.55, 0.42 + t * 0.35, 0.22 + t * 0.15)
			var flags: int = int(hf.flags_packed[idx]) if idx < hf.flags_packed.size() else 0
			if (flags & Wc3Coords.FLAG_WATER) != 0:
				col = Color(0.15, 0.35, 0.72).lerp(Color(0.35, 0.55, 0.9), t)
			img.set_pixel(px, py, col)
	_minimap_image = img
	_redraw_minimap_overlay()


func set_viewport_uv(rect: Rect2) -> void:
	_viewport_uv = rect
	_redraw_minimap_overlay()


func _redraw_minimap_overlay() -> void:
	if _minimap_image == null:
		return
	var img := _minimap_image.duplicate()
	if _show_viewport_rect and _viewport_uv.size.x > 0.0 and _viewport_uv.size.y > 0.0:
		var w: int = img.get_width()
		var h: int = img.get_height()
		var x0: int = clampi(int(_viewport_uv.position.x * w), 0, w - 1)
		var y0: int = clampi(int(_viewport_uv.position.y * h), 0, h - 1)
		var x1: int = clampi(int((_viewport_uv.position.x + _viewport_uv.size.x) * w), 0, w - 1)
		var y1: int = clampi(int((_viewport_uv.position.y + _viewport_uv.size.y) * h), 0, h - 1)
		var amber := Color(1.0, 0.85, 0.2, 1.0)
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			img.set_pixel(x, y0, amber)
			img.set_pixel(x, y1, amber)
		for y in range(mini(y0, y1), maxi(y0, y1) + 1):
			img.set_pixel(x0, y, amber)
			img.set_pixel(x1, y, amber)
	_minimap_tex.texture = ImageTexture.create_from_image(img)


func _on_minimap_gui(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var sz: Vector2 = _minimap_tex.size
	if sz.x <= 1.0 or sz.y <= 1.0:
		return
	var uv := Vector2(mb.position.x / sz.x, mb.position.y / sz.y)
	uv.x = clampf(uv.x, 0.0, 1.0)
	uv.y = clampf(uv.y, 0.0, 1.0)
	minimap_clicked.emit(uv)


func show_doodad(type_id: String, variation: int = 0) -> void:
	_type_id = type_id
	var info: Dictionary = {}
	if _catalog != null:
		info = _catalog.lookup(type_id)
	_num_var = maxi(int(info.get("num_var", 1)), 1)
	_variation = clampi(variation, 0, _num_var - 1)
	var display := str(info.get("name", type_id))
	_preview_title.text = display if not display.is_empty() else type_id
	_refresh_var_label()
	_reload_model()


func clear_preview() -> void:
	_type_id = ""
	_preview_title.text = EditorI18n.t("EDITOR_PREVIEW_EMPTY")
	_clear_model()
	_anim_label.text = ""


func get_selection() -> Dictionary:
	return {
		"id": _type_id,
		"variation": _variation,
		"angle": _angle_deg,
		"scale": _scale,
		"random_var": _random_var,
	}


func _step_variation(delta: int) -> void:
	if _num_var <= 1:
		return
	_variation = posmod(_variation + delta, _num_var)
	_refresh_var_label()
	_reload_model()
	_emit_params()


func _refresh_var_label() -> void:
	_var_label.text = EditorI18n.t("EDITOR_PREVIEW_VARIATION", [_variation, _num_var])


func _emit_params() -> void:
	preview_params_changed.emit(_variation, _angle_deg, _scale, _random_var)


func _clear_model() -> void:
	for c in _model_root.get_children():
		c.queue_free()


func _reload_model() -> void:
	_clear_model()
	_anim_label.text = ""
	if _type_id.is_empty() or _catalog == null or _cache == null:
		return
	var path: String = _catalog.converted_glb_path(_type_id, _variation)
	if path.is_empty():
		_anim_label.text = EditorI18n.t("EDITOR_PREVIEW_MISSING_MODEL")
		return
	var node: Node3D = _cache.instance_glb(path)
	if node == null:
		_anim_label.text = EditorI18n.t("EDITOR_PREVIEW_MISSING_MODEL")
		return
	_model_root.add_child(node)
	_apply_model_xform()
	if _cache.glb_has_animation(path):
		_cache.autoplay_stand(node)
		_anim_label.text = EditorI18n.t("EDITOR_PREVIEW_ANIM_STAND")
	else:
		_anim_label.text = EditorI18n.t("EDITOR_PREVIEW_ANIM_NONE")
	_frame_model(node)


func _apply_model_xform() -> void:
	# WE 角度：绕 Z；Godot Y-up → 绕 Y
	_model_root.rotation_degrees = Vector3(0.0, -_angle_deg, 0.0)
	_model_root.scale = Vector3.ONE * maxf(_scale, 0.01)


func _frame_model(node: Node3D) -> void:
	var aabb := _calc_aabb(node)
	if aabb.size.length() < 0.001:
		return
	var center := aabb.get_center()
	node.position -= center
	_apply_preview_camera()


func _apply_preview_camera() -> void:
	var dist_we: float = float(_dist_spin.value)
	# WE 距离量级较大；换算到预览相机 Z
	var z: float = clampf(dist_we * WORLD_SCALE * 1.2, 2.0, 80.0)
	_preview_cam.position = Vector3(0.0, z * 0.35, z)
	_preview_cam.look_at(Vector3.ZERO, Vector3.UP)


func _calc_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "VisualInstance3D", true, false):
		var vi := child as VisualInstance3D
		var a: AABB = vi.get_aabb()
		if first:
			result = a
			first = false
		else:
			result = result.merge(a)
	return result
