extends Window
## 可浮动「导航 / 预览」窗：上半小地图，下半装饰物 3D 预览（对齐 WE 左侧栏职责，不钉死侧栏）。


signal closed_by_user
signal minimap_clicked(norm_uv: Vector2) ## 0..1，地图 UV（x→东，y→北）
signal preview_params_changed(variation: int, angle_deg: float, scale: float, random_var: bool)
## angle_deg = 放置朝向（写入地图）；预览环视 yaw/pitch 不在此信号中。
signal preview_clear_requested ## Esc：取消装饰物预览 / 笔刷类型

const PREVIEW_DIST_DEFAULT := 400.0 ## WE 预览距离默认
const PREVIEW_DIST_MIN := 50.0
const PREVIEW_DIST_MAX := 2000.0
const PREVIEW_DIST_STEP := 50.0
const PLACE_FACING_DEFAULT := 270.0 ## 放置朝向（写入地图）；与预览环视无关
const PLACE_FACING_STEP := 45.0 ## 输入框提交对齐
const PLACE_FACING_NUDGE := 45.0 ## ↺/↻ 与快捷键步进
const PREVIEW_SCALE_DEFAULT := 1.0
const WORLD_SCALE := 0.01 ## 与 Wc3Coords.WORLD_SCALE 近似：预览用本地尺度
const ORBIT_YAW_SENS := 0.35 ## 度 / 像素（仅观察相机）
const ORBIT_PITCH_SENS := 0.25
const ORBIT_PITCH_MIN := 5.0
const ORBIT_PITCH_MAX := 80.0
const ORBIT_PITCH_DEFAULT := 25.0
const ORBIT_YAW_DEFAULT := 0.0
const ZOOM_WHEEL_FACTOR := 1.12
const _Pe2 := preload("res://scripts/map/presentation/effects/wc3_pe2_particles.gd")

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
@onready var _chk_game_preview: CheckBox = %ChkGamePreview
@onready var _preview_title: Label = %PreviewTitle
@onready var _model_root: Node3D = %ModelRoot
@onready var _preview_cam: Camera3D = %PreviewCamera
@onready var _preview_viewport: SubViewport = %PreviewViewport
@onready var _preview_input: Control = %PreviewInput
@onready var _preview_loading: Label = %PreviewLoadingLabel
@onready var _chk_random: CheckBox = %ChkRandom
@onready var _var_label: Label = %VarLabel
@onready var _var_prev: Button = %VarPrev
@onready var _var_next: Button = %VarNext
@onready var _anim_label: Label = %AnimLabel
@onready var _anim_prev: Button = %AnimPrev
@onready var _anim_option: OptionButton = %AnimOption
@onready var _anim_next: Button = %AnimNext
@onready var _dist_label: Label = %DistLabel
@onready var _dist_edit: LineEdit = %DistEdit
@onready var _angle_label: Label = %AngleLabel
@onready var _angle_edit: LineEdit = %AngleEdit
@onready var _facing_ccw: Button = %FacingCcw
@onready var _facing_cw: Button = %FacingCw

var _catalog: Wc3IdCatalog
var _cache: MapModelCache
var _type_id: String = ""
var _variation: int = 0
var _num_var: int = 1
var _team_color_owner: int = 0 ## 单位预览队伍色；装饰物忽略
var _preview_kind: String = "" ## "unit" | "doodad" | ""
var _dist_we: float = PREVIEW_DIST_DEFAULT
## 放置朝向（度）：幽灵 / 落笔 / 模型正面朝向。与下方环视 yaw 分离。
var _place_facing_deg: float = PLACE_FACING_DEFAULT
## 预览相机环视（仅观察，不写入地图）。
var _view_yaw_deg: float = ORBIT_YAW_DEFAULT
var _cam_pitch_deg: float = ORBIT_PITCH_DEFAULT
var _scale: float = PREVIEW_SCALE_DEFAULT ## 放置用，预览 UI 已移除；固定 1
var _random_var: bool = true
var _preview_gen: int = 0
var _preview_instance: Node3D = null
var _anim_names: PackedStringArray = PackedStringArray()
var _suppress_anim_signal: bool = false
var _suppress_edit_signal: bool = false
var _orbit_dragging: bool = false
var _orbit_last: Vector2 = Vector2.ZERO
var _minimap_raster: MapMinimapRaster
var _minimap_image: Image
var _viewport_quad: PackedVector2Array = PackedVector2Array()
var _show_viewport_rect: bool = true
var _show_buildings: bool = true
var _show_units: bool = true
var _game_preview: bool = false ## true=磁盘 war3mapMap；false=实时光栅
var _mmp_icons: Array = [] ## [{type,x,y,color:[r,g,b,a]}]
var _icon_textures: Dictionary = {} ## type -> Texture2D
var _last_hf: Wc3Heightfield
var _last_map_dir: String = ""
var _last_tiles: Wc3TerrainTileCatalog
var _last_cliff_catalog: Wc3CliffCatalog
var _last_romp: PackedByteArray = PackedByteArray()
## 空闲预读 GLB 字节（最多排队数量）；解析仍在点选时做。
const PREWARM_BYTES_MAX := 16
var _bytes_prewarm_queue: PackedStringArray = PackedStringArray()
var _bytes_prewarm_active: bool = false


func _ready() -> void:
	transparent = false
	unfocusable = false
	always_on_top = true
	close_requested.connect(_on_close)
	_wire()
	_apply_locale()
	if not EditorI18n.locale_changed.is_connected(_on_locale):
		EditorI18n.locale_changed.connect(_on_locale)
	_sync_param_edits()
	_chk_random.button_pressed = _random_var
	_chk_viewport.button_pressed = true
	_chk_buildings.button_pressed = true
	_chk_units.button_pressed = true
	if _chk_game_preview != null:
		_chk_game_preview.button_pressed = false
	_refresh_var_label()
	_update_variation_ui_visibility()
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
	if _chk_game_preview != null:
		_chk_game_preview.toggled.connect(func(on: bool) -> void:
			_game_preview = on
			_reload_minimap_from_cache()
		)
	_chk_random.toggled.connect(func(on: bool) -> void:
		_random_var = on
		_emit_params()
	)
	_var_prev.pressed.connect(func() -> void: _step_variation(-1))
	_var_next.pressed.connect(func() -> void: _step_variation(1))
	if _anim_prev != null:
		_anim_prev.pressed.connect(func() -> void: _step_animation(-1))
	if _anim_next != null:
		_anim_next.pressed.connect(func() -> void: _step_animation(1))
	if _anim_option != null:
		_anim_option.item_selected.connect(_on_anim_selected)
	if _preview_input != null:
		_preview_input.gui_input.connect(_on_preview_gui_input)
	if _dist_edit != null:
		_dist_edit.text_submitted.connect(func(_t: String) -> void: _commit_dist_edit())
		_dist_edit.focus_exited.connect(_commit_dist_edit)
	if _angle_edit != null:
		_angle_edit.text_submitted.connect(func(_t: String) -> void: _commit_facing_edit())
		_angle_edit.focus_exited.connect(_commit_facing_edit)
	if _facing_ccw != null:
		_facing_ccw.pressed.connect(func() -> void: nudge_place_facing(-PLACE_FACING_NUDGE))
	if _facing_cw != null:
		_facing_cw.pressed.connect(func() -> void: nudge_place_facing(PLACE_FACING_NUDGE))


func _sync_param_edits() -> void:
	_suppress_edit_signal = true
	if _dist_edit != null:
		_dist_edit.text = str(int(round(_dist_we)))
	if _angle_edit != null:
		_angle_edit.text = str(int(round(_place_facing_deg)))
	_suppress_edit_signal = false


func _commit_dist_edit() -> void:
	if _suppress_edit_signal or _dist_edit == null:
		return
	var v := _dist_edit.text.strip_edges().to_float()
	if not is_finite(v):
		_sync_param_edits()
		return
	_set_distance(v, true)


func _commit_facing_edit() -> void:
	if _suppress_edit_signal or _angle_edit == null:
		return
	var v := _angle_edit.text.strip_edges().to_float()
	if not is_finite(v):
		_sync_param_edits()
		return
	# 输入框按 45° 对齐；按钮/快捷键用 90°
	set_place_facing(snappedf(v, PLACE_FACING_STEP), true)


func _set_distance(value: float, sync_edit: bool = true) -> void:
	_dist_we = clampf(value, PREVIEW_DIST_MIN, PREVIEW_DIST_MAX)
	if sync_edit:
		_sync_param_edits()
	_apply_preview_camera()


## 设置放置朝向（度）。sync_edit 刷新输入框；默认发出 preview_params_changed。
func set_place_facing(value: float, sync_edit: bool = true, emit_params: bool = true) -> void:
	_place_facing_deg = fposmod(value, 360.0)
	if sync_edit:
		_sync_param_edits()
	_apply_model_xform()
	if emit_params:
		_emit_params()


func nudge_place_facing(delta_deg: float) -> void:
	set_place_facing(_place_facing_deg + delta_deg, true, true)


func get_place_facing() -> float:
	return _place_facing_deg


func _unhandled_key_input(event: InputEvent) -> void:
	# 预览窗有焦点时主视口收不到快捷键，在此转发
	if not visible or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	var focus := gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	var code: Key = k.keycode
	if code == KEY_NONE:
		code = k.physical_keycode
	match code:
		KEY_ESCAPE:
			preview_clear_requested.emit()
			get_viewport().set_input_as_handled()
		KEY_BRACKETLEFT, KEY_COMMA:
			nudge_place_facing(-PLACE_FACING_NUDGE)
			get_viewport().set_input_as_handled()
		KEY_BRACKETRIGHT, KEY_PERIOD:
			nudge_place_facing(PLACE_FACING_NUDGE)
			get_viewport().set_input_as_handled()
		KEY_R:
			nudge_place_facing(-PLACE_FACING_NUDGE if k.shift_pressed else PLACE_FACING_NUDGE)
			get_viewport().set_input_as_handled()


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_orbit_dragging = mb.pressed
			_orbit_last = mb.position
			_preview_input.accept_event()
			return
		if mb.pressed and (
			mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			var factor := ZOOM_WHEEL_FACTOR if mb.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 / ZOOM_WHEEL_FACTOR)
			_set_distance(_dist_we / factor, true)
			_preview_input.accept_event()
			return
	if event is InputEventMouseMotion and _orbit_dragging:
		var mm := event as InputEventMouseMotion
		var delta: Vector2 = mm.position - _orbit_last
		_orbit_last = mm.position
		# 仅环视相机；不改放置朝向（避免 WE「预览角=放置角」歧义）
		_view_yaw_deg = fposmod(_view_yaw_deg - delta.x * ORBIT_YAW_SENS, 360.0)
		_cam_pitch_deg = clampf(
			_cam_pitch_deg + delta.y * ORBIT_PITCH_SENS,
			ORBIT_PITCH_MIN,
			ORBIT_PITCH_MAX,
		)
		_apply_preview_camera()
		_preview_input.accept_event()


func _apply_minimap_frame_style() -> void:
	if _minimap_frame == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.22, 0.24, 1.0)
	sb.border_color = Color(0.12, 0.12, 0.14, 1.0)
	sb.set_border_width_all(3)
	sb.set_content_margin_all(4)
	_minimap_frame.add_theme_stylebox_override("panel", sb)
	# 外框保持正方形（宽由窗口决定时同步高度）
	if not _minimap_frame.resized.is_connected(_sync_minimap_frame_square):
		_minimap_frame.resized.connect(_sync_minimap_frame_square)
	call_deferred("_sync_minimap_frame_square")
	if _minimap_tex != null:
		_minimap_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_minimap_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_minimap_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Panel 被拉宽时把高度设成相同，避免方图横向拉伸。
func _sync_minimap_frame_square() -> void:
	if _minimap_frame == null:
		return
	var w: float = _minimap_frame.size.x
	if w < 64.0:
		w = 280.0
	var target := Vector2(w, w)
	if not _minimap_frame.custom_minimum_size.is_equal_approx(target):
		_minimap_frame.custom_minimum_size = target


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
	if _chk_game_preview != null:
		_chk_game_preview.text = EditorI18n.t("EDITOR_MINIMAP_GAME_PREVIEW")
	_chk_random.text = EditorI18n.t("EDITOR_PREVIEW_RANDOM_VAR")
	_dist_label.text = EditorI18n.t("EDITOR_PREVIEW_DISTANCE")
	_angle_label.text = EditorI18n.t("EDITOR_PREVIEW_FACING")
	if _facing_ccw != null:
		_facing_ccw.tooltip_text = EditorI18n.t("EDITOR_PREVIEW_FACING_CCW")
	if _facing_cw != null:
		_facing_cw.tooltip_text = EditorI18n.t("EDITOR_PREVIEW_FACING_CW")
	if _preview_input != null:
		_preview_input.tooltip_text = EditorI18n.t("EDITOR_PREVIEW_ORBIT_HINT")
	if _preview_loading != null:
		_preview_loading.text = EditorI18n.t("EDITOR_PREVIEW_LOADING")
	if _anim_label != null:
		_anim_label.text = EditorI18n.t("EDITOR_PREVIEW_ANIM")
	if _anim_prev != null:
		_anim_prev.tooltip_text = EditorI18n.t("EDITOR_PREVIEW_ANIM_PREV")
	if _anim_next != null:
		_anim_next.tooltip_text = EditorI18n.t("EDITOR_PREVIEW_ANIM_NEXT")
	_refresh_var_label()
	if _type_id.is_empty():
		_preview_title.text = EditorI18n.t("EDITOR_PREVIEW_EMPTY")
	else:
		_refresh_preview_title()


func _on_close() -> void:
	closed_by_user.emit()
	hide()


## 刷新小地图底图。
## game_preview 勾选时优先磁盘 war3mapMap；否则纹理采样实时光栅（显示 256 Nearest）。
func refresh_minimap(
	hf: Wc3Heightfield,
	map_dir: String = "",
	tiles: Wc3TerrainTileCatalog = null,
	cliff_catalog: Wc3CliffCatalog = null,
	romp: PackedByteArray = PackedByteArray(),
) -> void:
	_last_hf = hf
	_last_map_dir = map_dir
	_last_tiles = tiles
	_last_cliff_catalog = cliff_catalog
	_last_romp = romp
	_mmp_icons.clear()
	_minimap_image = null
	_minimap_raster = null
	if not map_dir.is_empty():
		_mmp_icons = _try_load_mmp_icons(map_dir)
	if _game_preview and not map_dir.is_empty():
		_minimap_image = _try_load_war3map_map(map_dir)
	if _minimap_image == null:
		_minimap_image = _rasterize_live(hf, tiles, cliff_catalog, romp)
	_apply_minimap_texture(_minimap_image)


## 仅强制实时光栅（笔刷 / undo 后调用；忽略 game_preview 勾选的磁盘图）。
func refresh_minimap_live(
	hf: Wc3Heightfield,
	tiles: Wc3TerrainTileCatalog = null,
	cliff_catalog: Wc3CliffCatalog = null,
	romp: PackedByteArray = PackedByteArray(),
) -> void:
	_last_hf = hf
	if tiles != null:
		_last_tiles = tiles
	if cliff_catalog != null:
		_last_cliff_catalog = cliff_catalog
	_last_romp = romp
	if _game_preview:
		_minimap_overlay.queue_redraw()
		return
	_minimap_image = _rasterize_live(
		hf,
		_last_tiles,
		_last_cliff_catalog,
		_last_romp,
	)
	_apply_minimap_texture(_minimap_image)


## 工作图（1:1）优先；无 raster 时退回当前显示图（如磁盘 PNG）。
func get_minimap_image() -> Image:
	if _minimap_raster != null:
		var work: Image = _minimap_raster.get_image()
		if work != null:
			return work
	return _minimap_image


func _reload_minimap_from_cache() -> void:
	refresh_minimap(_last_hf, _last_map_dir, _last_tiles, _last_cliff_catalog, _last_romp)


func _rasterize_live(
	hf: Wc3Heightfield,
	tiles: Wc3TerrainTileCatalog,
	cliff_catalog: Wc3CliffCatalog,
	romp: PackedByteArray,
) -> Image:
	if hf == null or hf.width < 2 or hf.height < 2:
		return null
	_minimap_raster = MapMinimapRaster.new(hf)
	var colors := PackedColorArray()
	if tiles != null:
		colors = Wc3GroundTileCatalog.build_minimap_colors(hf.ground_tilesets, tiles)
	else:
		colors.resize(maxi(hf.ground_tilesets.size(), 1))
		for i in range(colors.size()):
			colors[i] = MapMinimapUtils.ground_tex_to_color(i)
	var c2g := PackedInt32Array()
	if cliff_catalog != null:
		c2g = cliff_catalog.build_cliff_to_ground_map(hf.cliff_tilesets, hf.ground_tilesets)
	_minimap_raster.setup_terrain(colors, c2g, romp)
	_minimap_raster.rasterize()
	return _minimap_raster.get_display_image()


func _apply_minimap_texture(img: Image) -> void:
	if img == null:
		_minimap_tex.texture = null
		_minimap_overlay.queue_redraw()
		return
	_minimap_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap_tex.texture = ImageTexture.create_from_image(img)
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


func step_variation(delta: int) -> void:
	_step_variation(delta)


func set_random_variation(on: bool) -> void:
	_random_var = on
	if _chk_random != null:
		_chk_random.set_pressed_no_signal(on)
	_emit_params()


func show_doodad(type_id: String, variation: int = 0, apply_type_defaults: bool = true) -> void:
	var new_id := type_id.strip_edges()
	var type_changed := _type_id != new_id
	var info: Dictionary = {}
	if _catalog != null:
		info = _catalog.lookup(new_id)
	var num_var: int = maxi(int(info.get("num_var", 1)), 1)
	var new_var: int = clampi(variation, 0, num_var - 1)
	var var_changed := new_var != _variation
	# 同类型同样式且已有实例：跳过重载（避免面板连点卡顿）
	if (
		not type_changed
		and not var_changed
		and _preview_kind == "doodad"
		and _preview_instance != null
	):
		if apply_type_defaults:
			_apply_type_preview_defaults(info, false)
		_refresh_preview_title()
		return
	_type_id = new_id
	_preview_kind = "doodad"
	_num_var = num_var
	_variation = new_var
	if apply_type_defaults:
		_apply_type_preview_defaults(info, type_changed)
	_refresh_preview_title()
	_refresh_var_label()
	_update_variation_ui_visibility()
	_reload_model()


## 单位预览：应用 owner 队伍色；单位无 variation。
func show_unit(type_id: String, owner_id: int = 0, apply_type_defaults: bool = true) -> void:
	var new_id := type_id.strip_edges()
	var type_changed := _type_id != new_id
	_team_color_owner = clampi(owner_id, 0, 15)
	var info: Dictionary = {}
	if _catalog != null:
		info = _catalog.lookup(new_id)
	# 同单位已预览：只刷新队伍色 / 标题，不重载 GLB
	if not type_changed and _preview_kind == "unit" and _preview_instance != null:
		if apply_type_defaults:
			_apply_type_preview_defaults(info, false)
		_refresh_preview_title()
		set_preview_team_color(_team_color_owner)
		return
	_type_id = new_id
	_preview_kind = "unit"
	_num_var = 1
	_variation = 0
	if apply_type_defaults:
		_apply_type_preview_defaults(info, type_changed)
	_refresh_preview_title()
	_refresh_var_label()
	_update_variation_ui_visibility()
	_reload_model()


## 切换单位面板玩家色时刷新预览染色（不重载模型）。
func set_preview_team_color(owner_id: int) -> void:
	_team_color_owner = clampi(owner_id, 0, 15)
	if _preview_kind != "unit" or _preview_instance == null or _cache == null:
		return
	var color_i := MapUnitLayer.resolve_team_color_index(_type_id, _team_color_owner)
	_cache.apply_team_color(_preview_instance, color_i, false)


## 地图点选：预览该单位实例（朝向 + 队伍色）。
func show_map_unit(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var tid := str(entry.get("typeId", "")).strip_edges()
	if tid.is_empty():
		return
	var owner := clampi(int(entry.get("owner", 0)), 0, 15)
	show_unit(tid, owner, true)
	var deg: float = float(entry.get("angleDegrees", rad_to_deg(float(entry.get("angle", 0.0)))))
	set_place_facing(deg, true, false)


## 地图点选：预览该装饰物实例（类型默认距离 + 实例朝向/样式/缩放）。
func show_map_doodad(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var tid := str(entry.get("id", "")).strip_edges()
	if tid.is_empty():
		return
	var var_i: int = int(entry.get("variation", 0))
	show_doodad(tid, var_i, true)
	var deg2: float = float(entry.get("angleDegrees", rad_to_deg(float(entry.get("angle", 0.0)))))
	set_place_facing(deg2, true, false)
	var scale_data: Dictionary = entry.get("scale", {})
	var sx: float = float(scale_data.get("x", 1.0))
	var sy: float = float(scale_data.get("y", 1.0))
	var sz: float = float(scale_data.get("z", 1.0))
	_scale = maxf((sx + sy + sz) / 3.0, 0.01)
	_apply_model_xform()


## 按 SLK 重置预览距离 /（可选）放置朝向。换类型时重置环视角。
func _apply_type_preview_defaults(info: Dictionary, reset_orbit: bool = true) -> void:
	if info.is_empty():
		_set_distance(PREVIEW_DIST_DEFAULT, true)
		set_place_facing(PLACE_FACING_DEFAULT, true, false)
	else:
		_set_distance(Wc3IdCatalog.preview_distance_wc3(info), true)
		set_place_facing(Wc3IdCatalog.default_facing_deg(info), true, false)
		var ds: float = float(info.get("def_scale", 1.0))
		_scale = maxf(ds, 0.01) if ds > 0.0 else PREVIEW_SCALE_DEFAULT
	if reset_orbit:
		_view_yaw_deg = ORBIT_YAW_DEFAULT
		_cam_pitch_deg = ORBIT_PITCH_DEFAULT
	_apply_preview_camera()


func clear_preview() -> void:
	_preview_gen += 1
	_type_id = ""
	_preview_kind = ""
	_num_var = 1
	_variation = 0
	_set_loading_overlay(false)
	_preview_title.text = EditorI18n.t("EDITOR_PREVIEW_EMPTY")
	_clear_model()
	_reset_anim_ui()
	_update_variation_ui_visibility()


func _update_variation_ui_visibility() -> void:
	var show_var := _num_var > 1 and _preview_kind != "unit"
	if _chk_random != null:
		_chk_random.visible = show_var
	var var_row: Control = get_node_or_null("%VarRow") as Control
	if var_row == null and _var_label != null:
		var_row = _var_label.get_parent() as Control
	if var_row != null:
		var_row.visible = show_var


func _refresh_var_label() -> void:
	_var_label.text = EditorI18n.t("EDITOR_PREVIEW_VARIATION", [_variation, _num_var])
	_update_variation_ui_visibility()


func get_selection() -> Dictionary:
	return {
		"id": _type_id,
		"variation": _variation,
		"angle": _place_facing_deg,
		"scale": _scale,
		"random_var": _random_var,
	}


func _refresh_preview_title() -> void:
	if _type_id.is_empty():
		_preview_title.text = EditorI18n.t("EDITOR_PREVIEW_EMPTY")
		return
	var info: Dictionary = _catalog.lookup(_type_id) if _catalog != null else {}
	var nk := str(info.get("name_key", ""))
	var display := ""
	if nk.begins_with("WESTRING_"):
		var loc := EditorI18n.t(nk)
		if not loc.is_empty() and loc != nk and not loc.begins_with("WESTRING_"):
			display = loc
	if display.is_empty():
		display = str(info.get("name", _type_id))
	if display.is_empty():
		display = _type_id
	_preview_title.text = "%s  [%s]" % [display, _type_id]


func _step_variation(delta: int) -> void:
	if _num_var <= 1:
		return
	_variation = posmod(_variation + delta, _num_var)
	_refresh_var_label()
	_reload_model()
	_emit_params()


func _emit_params() -> void:
	preview_params_changed.emit(_variation, _place_facing_deg, _scale, _random_var)


func _clear_model() -> void:
	_preview_instance = null
	for c in _model_root.get_children():
		_model_root.remove_child(c)
		c.free()


func _set_loading_overlay(on: bool) -> void:
	if _preview_loading == null:
		return
	_preview_loading.text = EditorI18n.t("EDITOR_PREVIEW_LOADING")
	_preview_loading.visible = on


## 启动预览加载：.scn / 内存缓存优先；否则异步 IO +（必要时）GLTF。
func _reload_model() -> void:
	_preview_gen += 1
	var gen := _preview_gen
	_clear_model()
	_reset_anim_ui()
	if _type_id.is_empty() or _catalog == null:
		_set_loading_overlay(false)
		return
	var info: Dictionary = _catalog.lookup(_type_id)
	var path: String = _catalog.converted_glb_path(_type_id, _variation) if _cache != null else ""
	if path.is_empty() or _cache == null:
		_set_loading_overlay(false)
		_finish_preview_missing_or_helper(gen, info, path)
		return
	if _cache.has_cached(path):
		_set_loading_overlay(false)
		_mount_preview_instance(_cache.instance_glb_preview(path), gen, path, info)
		return
	_set_loading_overlay(true)
	_set_anim_status(EditorI18n.t("EDITOR_PREVIEW_LOADING"))
	_reload_model_async(gen, path, info)


func _reload_model_async(gen: int, path: String, info: Dictionary) -> void:
	await get_tree().process_frame
	if gen != _preview_gen:
		return
	# 1) 旁路 .scn：ResourceLoader 线程加载（无 GLTF 解析）
	var scn_path := RuntimeAssets.resolve_model_scene(path)
	if not scn_path.is_empty():
		var packed_scn: PackedScene = await _load_scn_threaded(scn_path, gen)
		if gen != _preview_gen:
			return
		if packed_scn != null:
			if _cache != null:
				_cache.register_external_packed(path, packed_scn)
			var node_scn := packed_scn.instantiate()
			if node_scn is Node3D:
				_mount_preview_instance(node_scn as Node3D, gen, path, info)
				return
			if node_scn != null:
				node_scn.free()
	# 2) 字节缓存 / worker 读盘 → 预览实例（可能触发 GLTF）
	var bytes := PackedByteArray()
	if _cache != null and _cache.has_bytes_cached(path):
		bytes = _cache.take_cached_bytes(path)
	else:
		var disk_path := RuntimeAssets.project_abs(path)
		var holder := {"bytes": PackedByteArray(), "ok": false}
		var task_id: int = WorkerThreadPool.add_task(
			func() -> void:
				if FileAccess.file_exists(disk_path):
					var b := FileAccess.get_file_as_bytes(disk_path)
					holder["bytes"] = b
					holder["ok"] = not b.is_empty()
		)
		await WorkerThreadPool.wait_for_task_completion(task_id)
		if gen != _preview_gen:
			return
		if bool(holder.get("ok", false)):
			bytes = holder["bytes"] as PackedByteArray
			if _cache != null:
				_cache.store_bytes(path, bytes)
	await get_tree().process_frame
	if gen != _preview_gen:
		return
	var node: Node3D = null
	if not bytes.is_empty() and _cache != null:
		node = _cache.instance_glb_from_bytes_preview(path, bytes)
	elif _cache != null:
		node = _cache.instance_glb_preview(path)
	if node == null:
		_finish_preview_missing_or_helper(gen, info, path)
		return
	_mount_preview_instance(node, gen, path, info)
	# 空闲懒烘焙 .scn，下次走线程加载
	if _cache != null:
		_cache.process_lazy_bake_one()


func _load_scn_threaded(scn_path: String, gen: int) -> PackedScene:
	var err := ResourceLoader.load_threaded_request(scn_path, "PackedScene", true)
	if err != OK:
		return RuntimeAssets.load_packed_scene(scn_path)
	while true:
		if gen != _preview_gen:
			return null
		var status := ResourceLoader.load_threaded_get_status(scn_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var res: Resource = ResourceLoader.load_threaded_get(scn_path)
			return res as PackedScene if res is PackedScene else null
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return null
		await get_tree().process_frame
	return null


func _finish_preview_missing_or_helper(gen: int, info: Dictionary, path: String) -> void:
	if gen != _preview_gen:
		return
	_set_loading_overlay(false)
	_clear_model()
	if bool(info.get("use_click_helper", false)):
		var node := Node3D.new()
		node.add_child(MapPlaceholders.make_click_helper(float(info.get("sel_size", 0.0))))
		node.add_child(MapPlaceholders.make_effect_particles())
		_mount_preview_instance(node, gen, path, info)
		_set_anim_status(EditorI18n.t("EDITOR_PREVIEW_ANIM_NONE"))
		return
	_set_anim_status(EditorI18n.t("EDITOR_PREVIEW_MISSING_MODEL"))


func _mount_preview_instance(node: Node3D, gen: int, path: String, info: Dictionary) -> void:
	if gen != _preview_gen:
		if node != null and not node.is_inside_tree():
			node.free()
		return
	_set_loading_overlay(false)
	if node == null:
		_finish_preview_missing_or_helper(gen, info, path)
		return
	_clear_model()
	_model_root.add_child(node)
	_preview_instance = node
	_apply_model_xform()
	call_deferred("_polish_preview_deferred", gen, path, info)
	if _cache != null:
		call_deferred("_idle_lazy_bake")


func _idle_lazy_bake() -> void:
	if _cache != null:
		_cache.process_lazy_bake_one()


func _polish_preview_deferred(gen: int, path: String, info: Dictionary) -> void:
	if gen != _preview_gen or _preview_instance == null:
		return
	var node := _preview_instance
	var has_mesh: bool = MapPlaceholders.node_has_mesh(node)
	if not path.is_empty():
		_Pe2.attach_to(node, path)
	if _preview_kind != "unit":
		MapPlaceholders.attach_editor_helpers(node, info, has_mesh)
	if _preview_kind == "unit" and _cache != null:
		var color_i := MapUnitLayer.resolve_team_color_index(_type_id, _team_color_owner)
		_cache.apply_team_color(node, color_i, false)
	_setup_animations(node)
	call_deferred("_frame_model_deferred", gen)


## 单位面板图标就绪：排队预读 GLB 文件字节（不解析场景）。
func prewarm_unit_type_ids(type_ids: PackedStringArray) -> void:
	if _catalog == null or _cache == null:
		return
	_bytes_prewarm_queue.clear()
	var n := 0
	for tid_v in type_ids:
		if n >= PREWARM_BYTES_MAX:
			break
		var tid := str(tid_v)
		if tid.is_empty():
			continue
		var path: String = _catalog.converted_glb_path(tid, 0)
		if path.is_empty():
			continue
		if _cache.has_cached(path) or _cache.has_bytes_cached(path) or _cache.has_model_scene(path):
			continue
		_bytes_prewarm_queue.append(path)
		n += 1
	if not _bytes_prewarm_active and not _bytes_prewarm_queue.is_empty():
		_tick_bytes_prewarm()


func _tick_bytes_prewarm() -> void:
	if _bytes_prewarm_active or _cache == null:
		return
	while not _bytes_prewarm_queue.is_empty():
		var path: String = _bytes_prewarm_queue[0]
		_bytes_prewarm_queue.remove_at(0)
		if (
			_cache.has_cached(path)
			or _cache.has_bytes_cached(path)
			or _cache.has_model_scene(path)
		):
			continue
		_bytes_prewarm_active = true
		_run_bytes_prewarm(path)
		return


func _run_bytes_prewarm(path: String) -> void:
	var disk_path := RuntimeAssets.project_abs(path)
	var holder := {"bytes": PackedByteArray(), "ok": false}
	var task_id: int = WorkerThreadPool.add_task(
		func() -> void:
			if FileAccess.file_exists(disk_path):
				var b := FileAccess.get_file_as_bytes(disk_path)
				holder["bytes"] = b
				holder["ok"] = not b.is_empty()
	)
	await WorkerThreadPool.wait_for_task_completion(task_id)
	if bool(holder.get("ok", false)) and _cache != null:
		_cache.store_bytes(path, holder["bytes"] as PackedByteArray)
	_bytes_prewarm_active = false
	# 间隔一帧再预读下一个，避免打满磁盘
	await get_tree().process_frame
	_tick_bytes_prewarm()


func _setup_animations(node: Node3D) -> void:
	_anim_names = PackedStringArray()
	if _cache == null or node == null:
		_reset_anim_ui()
		return
	_anim_names = _cache.list_animations(node)
	_suppress_anim_signal = true
	if _anim_option != null:
		_anim_option.clear()
		for i in range(_anim_names.size()):
			_anim_option.add_item(str(_anim_names[i]), i)
	_suppress_anim_signal = false
	var has_anim := _anim_names.size() > 0
	if _anim_prev != null:
		_anim_prev.disabled = not has_anim
	if _anim_next != null:
		_anim_next.disabled = not has_anim
	if _anim_option != null:
		_anim_option.disabled = not has_anim
	if not has_anim:
		_set_anim_status(EditorI18n.t("EDITOR_PREVIEW_ANIM_NONE"))
		return
	# 优先 Stand，否则第一条
	var prefer := 0
	for i in range(_anim_names.size()):
		var n := str(_anim_names[i])
		if n == "Stand" or n == "stand" or n.begins_with("Stand ") or n.begins_with("stand "):
			prefer = i
			break
	if _anim_option != null:
		_suppress_anim_signal = true
		_anim_option.select(prefer)
		_suppress_anim_signal = false
	_play_anim_at(prefer)


func _reset_anim_ui() -> void:
	_anim_names = PackedStringArray()
	_suppress_anim_signal = true
	if _anim_option != null:
		_anim_option.clear()
		_anim_option.disabled = true
	_suppress_anim_signal = false
	if _anim_prev != null:
		_anim_prev.disabled = true
	if _anim_next != null:
		_anim_next.disabled = true


func _set_anim_status(text: String) -> void:
	# 无动画时 OptionButton 留空，状态写到 tooltip / 占位项
	if _anim_option == null:
		return
	_suppress_anim_signal = true
	_anim_option.clear()
	_anim_option.add_item(text, 0)
	_anim_option.select(0)
	_anim_option.disabled = true
	_suppress_anim_signal = false


func _step_animation(delta: int) -> void:
	if _anim_names.is_empty():
		return
	var i: int = _anim_option.selected if _anim_option != null else 0
	i = posmod(i + delta, _anim_names.size())
	if _anim_option != null:
		_suppress_anim_signal = true
		_anim_option.select(i)
		_suppress_anim_signal = false
	_play_anim_at(i)


func _on_anim_selected(index: int) -> void:
	if _suppress_anim_signal:
		return
	_play_anim_at(index)


func _play_anim_at(index: int) -> void:
	if _preview_instance == null or _cache == null:
		return
	if index < 0 or index >= _anim_names.size():
		return
	_cache.play_animation(_preview_instance, str(_anim_names[index]), true)


func _apply_model_xform() -> void:
	# 放置朝向：WE 绕 Z；Godot Y-up → 绕 Y。环视只动相机，不动模型。
	_model_root.rotation_degrees = Vector3(0.0, -_place_facing_deg, 0.0)
	_model_root.scale = Vector3.ONE * maxf(_scale, 0.01)


func _frame_model_deferred(gen: int) -> void:
	if gen != _preview_gen:
		return
	if _preview_instance == null or not is_instance_valid(_preview_instance):
		return
	_frame_model(_preview_instance)


func _frame_model(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _preview_viewport != null:
		_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	node.force_update_transform()
	var aabb := _calc_aabb_local(node)
	if aabb.size.length() < 0.001:
		_apply_model_xform()
		_apply_preview_camera()
		return
	# 包围盒中心拉回原点；距离/角度由预览拖拽与下方输入框控制
	node.position -= aabb.get_center()
	node.force_update_transform()
	_apply_model_xform()
	_apply_preview_camera()


func _apply_preview_camera() -> void:
	var z: float = clampf(_dist_we * WORLD_SCALE * 1.2, 1.5, 120.0)
	var pitch := deg_to_rad(_cam_pitch_deg)
	var yaw := deg_to_rad(_view_yaw_deg)
	var y: float = sin(pitch) * z
	var horiz: float = cos(pitch) * z
	_preview_cam.position = Vector3(sin(yaw) * horiz, y, cos(yaw) * horiz)
	_preview_cam.look_at(Vector3.ZERO, Vector3.UP)


## 相对 model 根节点局部空间的合并 AABB（含各 VisualInstance 变换）。
func _calc_aabb_local(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	root.force_update_transform()
	for child in root.find_children("*", "VisualInstance3D", true, false):
		var vi := child as VisualInstance3D
		if vi == null or not is_instance_valid(vi):
			continue
		vi.force_update_transform()
		var xf: Transform3D = root.global_transform.affine_inverse() * vi.global_transform
		var a: AABB = xf * vi.get_aabb()
		if a.size.length_squared() < 1e-12:
			continue
		if first:
			result = a
			first = false
		else:
			result = result.merge(a)
	return result
