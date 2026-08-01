extends Window
## 可浮动「导航 / 预览」窗：上半小地图，下半装饰物 3D 预览（对齐 WE 左侧栏职责，不钉死侧栏）。


signal closed_by_user
signal minimap_clicked(norm_uv: Vector2) ## 0..1，地图 UV（x→东，y→北）
signal preview_params_changed(variation: int, angle_deg: float, scale: float, random_var: bool)

const PREVIEW_DIST_DEFAULT := 450.0 ## WE 像素感距离；内部换算到 Godot 相机
const WORLD_SCALE := 0.01 ## 与 Wc3Coords.WORLD_SCALE 近似：预览用本地尺度

## MMP 图标逻辑路径（AssetProvider / converted）。
const ICON_PATHS := {
	0: "UI/MiniMap/MiniMapIcon/MinimapIconGold.png",
	1: "UI/MiniMap/MiniMapIcon/MinimapIconNeutralBuilding.png",
	2: "UI/MiniMap/MiniMapIcon/MinimapIconStartLoc.png",
	3: "UI/MiniMap/MinimapIconCreepLoc.png",
	4: "UI/MiniMap/MinimapIconCreepLoc2.png",
}

@onready var _minimap_frame: PanelContainer = %MinimapFrame
@onready var _minimap_tex: TextureRect = %MinimapTex
@onready var _minimap_overlay: Control = %MinimapOverlay
@onready var _chk_buildings: CheckBox = %ChkBuildings
@onready var _chk_units: CheckBox = %ChkUnits
@onready var _chk_viewport: CheckBox = %ChkViewport
@onready var _preview_title: Label = %PreviewTitle
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
var _minimap_raster: MapMinimapRaster
var _minimap_image: Image
var _viewport_quad: PackedVector2Array = PackedVector2Array()
var _show_viewport_rect: bool = true
var _show_buildings: bool = true
var _show_units: bool = true
var _mmp_icons: Array = [] ## [{type,x,y,color:[r,g,b,a]}]
var _icon_textures: Dictionary = {} ## type -> Texture2D


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
	_load_icon_textures()
	_apply_minimap_frame_style()


func setup(catalog: Wc3IdCatalog, cache: MapModelCache) -> void:
	_catalog = catalog
	_cache = cache


func _wire() -> void:
	_minimap_overlay.gui_input.connect(_on_minimap_gui)
	_minimap_overlay.draw.connect(_on_minimap_overlay_draw)
	_minimap_overlay.resized.connect(func() -> void: _minimap_overlay.queue_redraw())
	_chk_viewport.toggled.connect(func(on: bool) -> void:
		_show_viewport_rect = on
		_minimap_overlay.queue_redraw()
	)
	_chk_buildings.toggled.connect(func(on: bool) -> void:
		_show_buildings = on
		_minimap_overlay.queue_redraw()
	)
	_chk_units.toggled.connect(func(on: bool) -> void:
		_show_units = on
		_minimap_overlay.queue_redraw()
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


func _apply_minimap_frame_style() -> void:
	if _minimap_frame == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.22, 0.24, 1.0)
	sb.border_color = Color(0.12, 0.12, 0.14, 1.0)
	sb.set_border_width_all(3)
	sb.set_content_margin_all(4)
	_minimap_frame.add_theme_stylebox_override("panel", sb)


func _load_icon_textures() -> void:
	_icon_textures.clear()
	for t in ICON_PATHS.keys():
		var logical: String = str(ICON_PATHS[t])
		var tex: Texture2D = RuntimeAssets.load_converted_texture(logical)
		if tex == null:
			var abs_path: String = RuntimeAssets.resolve(logical)
			if not abs_path.is_empty():
				tex = RuntimeAssets.load_texture(abs_path)
		if tex != null:
			_icon_textures[int(t)] = tex


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


## 刷新小地图底图：优先 map_dir/war3mapMap.png，否则 heightfield 光栅。
func refresh_minimap(hf: Wc3Heightfield, map_dir: String = "") -> void:
	_mmp_icons.clear()
	_minimap_image = null
	_minimap_raster = null
	if not map_dir.is_empty():
		_minimap_image = _try_load_war3map_map(map_dir)
		_mmp_icons = _try_load_mmp_icons(map_dir)
	if _minimap_image == null:
		if hf == null or hf.width < 2 or hf.height < 2:
			_minimap_tex.texture = null
			_minimap_overlay.queue_redraw()
			return
		_minimap_raster = MapMinimapRaster.new(hf, 256)
		_minimap_image = _minimap_raster.rasterize()
	_minimap_tex.texture = ImageTexture.create_from_image(_minimap_image)
	_minimap_overlay.queue_redraw()


func set_viewport_uv_quad(quad: PackedVector2Array) -> void:
	_viewport_quad = quad
	_minimap_overlay.queue_redraw()


## 兼容旧 AABB API。
func set_viewport_uv(rect: Rect2) -> void:
	var q := PackedVector2Array()
	q.append(rect.position)
	q.append(Vector2(rect.end.x, rect.position.y))
	q.append(rect.end)
	q.append(Vector2(rect.position.x, rect.end.y))
	set_viewport_uv_quad(q)


func _try_load_war3map_map(map_dir: String) -> Image:
	var dir := map_dir.replace("\\", "/")
	if dir.begins_with("res://"):
		dir = ProjectSettings.globalize_path(dir)
	for fname in ["war3mapMap.png", "war3mapMap.tga"]:
		var p: String = dir.path_join(fname)
		if FileAccess.file_exists(p):
			var img := Image.new()
			if img.load(p) == OK:
				return img
	return null


func _try_load_mmp_icons(map_dir: String) -> Array:
	var dir := map_dir.replace("\\", "/")
	if dir.begins_with("res://"):
		dir = ProjectSettings.globalize_path(dir)
	var path: String = dir.path_join("minimap.json")
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var icons: Variant = (data as Dictionary).get("icons", [])
	return icons if typeof(icons) == TYPE_ARRAY else []


func _on_minimap_overlay_draw() -> void:
	if _minimap_image == null:
		return
	_draw_mmp_icons()
	if _show_viewport_rect and _viewport_quad.size() >= 4:
		var pts := PackedVector2Array()
		for i in range(4):
			pts.append(_minimap_uv_to_overlay_pos(_viewport_quad[i]))
		pts.append(pts[0])
		_minimap_overlay.draw_polyline(pts, Color(1.0, 0.85, 0.2, 1.0), 1.5, true)


func _draw_mmp_icons() -> void:
	if _mmp_icons.is_empty():
		return
	var canvas: float = 256.0
	for item in _mmp_icons:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var t: int = int(d.get("type", -1))
		if not _icon_type_visible(t):
			continue
		var tex: Texture2D = _icon_textures.get(t) as Texture2D
		if tex == null:
			continue
		var ix: float = float(d.get("x", 0))
		var iy: float = float(d.get("y", 0))
		var uv := Vector2(ix / canvas, iy / canvas)
		var pos: Vector2 = _minimap_uv_to_overlay_pos(uv)
		var sz: Vector2 = tex.get_size()
		# 小地图上图标略放大一点，贴近 WE 观感
		var draw_sz: Vector2 = sz * 1.25
		var col := Color(1, 1, 1, 1)
		var c: Variant = d.get("color", null)
		if typeof(c) == TYPE_ARRAY and (c as Array).size() >= 3 and t == 2:
			var a: Array = c
			col = Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
		_minimap_overlay.draw_texture_rect(tex, Rect2(pos - draw_sz * 0.5, draw_sz), false, col)


func _icon_type_visible(t: int) -> bool:
	match t:
		0, 1:
			return _show_buildings
		2, 3, 4:
			return _show_units
		_:
			return false


## 小地图 UV（可出 0..1）→ Overlay 本地坐标（相对 TextureRect 绘制区；可落入灰边）。
func _minimap_uv_to_overlay_pos(uv: Vector2) -> Vector2:
	var drawn: Rect2 = _minimap_drawn_rect()
	return Vector2(
		drawn.position.x + uv.x * drawn.size.x,
		drawn.position.y + uv.y * drawn.size.y,
	)


## TextureRect KEEP_ASPECT_CENTERED 实际绘制矩形（相对 Overlay）。
func _minimap_drawn_rect() -> Rect2:
	var cs: Vector2 = _minimap_overlay.size
	if cs.x <= 1.0 or cs.y <= 1.0 or _minimap_image == null:
		return Rect2(Vector2.ZERO, cs)
	var ts := Vector2(float(_minimap_image.get_width()), float(_minimap_image.get_height()))
	var scale: float = minf(cs.x / ts.x, cs.y / ts.y)
	var drawn: Vector2 = ts * scale
	var offset: Vector2 = (cs - drawn) * 0.5
	return Rect2(offset, drawn)


func _on_minimap_gui(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var uv := control_pos_to_minimap_uv(mb.position)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return
	minimap_clicked.emit(uv)


## 控件坐标 → 小地图纹理 UV（处理 KEEP_ASPECT_CENTERED 留白）。
func control_pos_to_minimap_uv(pos: Vector2) -> Vector2:
	var drawn: Rect2 = _minimap_drawn_rect()
	if drawn.size.x <= 1.0 or drawn.size.y <= 1.0:
		return Vector2(-1, -1)
	var local: Vector2 = pos - drawn.position
	if local.x < 0.0 or local.y < 0.0 or local.x > drawn.size.x or local.y > drawn.size.y:
		return Vector2(-1, -1)
	return Vector2(local.x / drawn.size.x, local.y / drawn.size.y)


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
