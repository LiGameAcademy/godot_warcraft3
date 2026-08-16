class_name GameMinimap
extends Control
## 游戏小地图：war3mapMap 底图 + 视口黄框 + 分类图标 / 队伍色方块。
## 金矿 → minimap-gold；中立建筑（UnitUI.nbmmIcon）→ minimap-neutralbuilding；
## 玩家单位/建筑 → 队伍色正方形；中立单位 → 黑色。
## 坐标与编辑器共用 MapMinimapUtils（heightfield UV）。

const BuildingVisualScr = preload("res://scripts/map/presentation/building_visual.gd")

signal clicked(uv: Vector2)

const NEUTRAL_OWNER_MIN := 12
const GOLD_MINE_TYPE := "ngol"
const DOT_UNIT := 2.5
const DOT_BLDG := 4.0
## HUD 角标默认边长（正方形；与 war3mapMap 256² 对齐）。
const DEFAULT_SIDE := 176.0
## 原作路径优先；MiniMapIcon/ 下为编辑器 MMP 用图，作回退。
const ICON_GOLD := "UI/MiniMap/minimap-gold.png"
const ICON_GOLD_FALLBACK := "UI/MiniMap/MiniMapIcon/MinimapIconGold.png"
const ICON_NEUTRAL_BLDG := "UI/MiniMap/minimap-neutralbuilding.png"
const ICON_NEUTRAL_BLDG_FALLBACK := "UI/MiniMap/MiniMapIcon/MinimapIconNeutralBuilding.png"
const ICON_DRAW_SCALE := 1.15
const _NEUTRAL_DOT := Color(0.05, 0.05, 0.05, 1.0)

@onready var _tex: TextureRect = $Background
@onready var _overlay: Control = $Overlay

var _image: Image = null
var _hf: Wc3Heightfield = null
var _unit_host: Node = null
var _camera: Camera3D = null
var _camera_rig: Node3D = null
## 本地玩家（预留友军高亮等；点色一律走队伍色表）
var _local_player: int = 0
var _catalog: Wc3IdCatalog = null
var _viewport_quad: PackedVector2Array = PackedVector2Array()
var _drag_pressed: bool = false
var _icon_gold: Texture2D = null
var _icon_neutral_bldg: Texture2D = null
var _icons_loaded: bool = false
## typeId → 是否显示中立建筑小地图图标（含 false 哨兵）
var _nbmm_cache: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size.x < 64.0 or custom_minimum_size.y < 64.0:
		custom_minimum_size = Vector2(DEFAULT_SIDE, DEFAULT_SIDE)
	_ensure_icons()
	if _overlay != null and not _overlay.draw.is_connected(_on_overlay_draw):
		_overlay.draw.connect(_on_overlay_draw)
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	if not gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)
	set_process(true)


func configure(
	heightfield: Wc3Heightfield,
	unit_host: Node,
	camera: Camera3D,
	camera_rig: Node3D,
	local_player: int = 0,
	catalog: Wc3IdCatalog = null
) -> void:
	_hf = heightfield
	_unit_host = unit_host
	_camera = camera
	_camera_rig = camera_rig
	_local_player = local_player
	if catalog != null:
		_catalog = catalog
	_ensure_icons()
	if _overlay != null:
		_overlay.queue_redraw()


func set_id_catalog(catalog: Wc3IdCatalog) -> void:
	_catalog = catalog
	_nbmm_cache.clear()
	if _overlay != null:
		_overlay.queue_redraw()


func load_from_map_dir(map_dir: String) -> bool:
	var img := _try_load_war3map(map_dir)
	if img == null:
		return false
	_image = img
	if _tex != null:
		_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_tex.texture = ImageTexture.create_from_image(img)
	if _overlay != null:
		_overlay.queue_redraw()
	return true


func set_background_texture(tex: Texture2D) -> void:
	if _tex != null:
		_tex.texture = tex
	_image = tex.get_image() if tex != null else null
	if _overlay != null:
		_overlay.queue_redraw()


func _process(_delta: float) -> void:
	if _camera == null or _hf == null or not _hf.is_valid():
		return
	_viewport_quad = MapMinimapUtils.compute_camera_minimap_uv_quad(
		_camera, _camera_rig if _camera_rig != null else _camera, _hf
	)
	if _overlay != null:
		_overlay.queue_redraw()


func _on_resized() -> void:
	if _overlay != null:
		_overlay.queue_redraw()


func _ensure_icons() -> void:
	if _icons_loaded:
		return
	_icons_loaded = true
	_icon_gold = _load_icon_first([ICON_GOLD, ICON_GOLD_FALLBACK])
	_icon_neutral_bldg = _load_icon_first([ICON_NEUTRAL_BLDG, ICON_NEUTRAL_BLDG_FALLBACK])


func _load_icon_first(candidates: Array) -> Texture2D:
	for logical in candidates:
		var tex := _load_icon(str(logical))
		if tex != null:
			return tex
	return null


func _load_icon(logical: String) -> Texture2D:
	var tex := RuntimeAssets.load_converted_texture(logical)
	if tex != null:
		return tex
	var abs_path := RuntimeAssets.resolve(logical)
	if not abs_path.is_empty():
		return RuntimeAssets.load_texture(abs_path)
	return null


func _try_load_war3map(map_dir: String) -> Image:
	if map_dir.is_empty():
		return null
	for file_name in ["war3mapMap.png", "war3mapMap.tga", "war3mapMap.blp"]:
		var path := map_dir.path_join(file_name)
		var disk := RuntimeAssets.project_abs(path)
		if disk.is_empty() or not FileAccess.file_exists(disk):
			continue
		var img := Image.new()
		if img.load(disk) == OK:
			return img
	return null


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_drag_pressed = mb.pressed
		if mb.pressed:
			_emit_click_at(mb.position)
			accept_event()
	elif event is InputEventMouseMotion and _drag_pressed:
		var mm := event as InputEventMouseMotion
		_emit_click_at(mm.position)
		accept_event()


func _emit_click_at(local_pos: Vector2) -> void:
	var uv := _control_to_uv(local_pos)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return
	clicked.emit(uv)


func _control_to_uv(pos: Vector2) -> Vector2:
	var drawn := _drawn_rect()
	if drawn.size.x < 1.0 or drawn.size.y < 1.0:
		return Vector2(-1, -1)
	return Vector2(
		(pos.x - drawn.position.x) / drawn.size.x,
		(pos.y - drawn.position.y) / drawn.size.y
	)


func _uv_to_overlay(uv: Vector2) -> Vector2:
	var drawn := _drawn_rect()
	return Vector2(
		drawn.position.x + uv.x * drawn.size.x,
		drawn.position.y + uv.y * drawn.size.y
	)


## 与 TextureRect KEEP_ASPECT_CENTERED 一致：按底图像素比居中 letterbox。
func _drawn_rect() -> Rect2:
	var cs := size
	if cs.x <= 1.0 or cs.y <= 1.0:
		return Rect2(Vector2.ZERO, cs)
	if _image == null:
		# 无图时仍按正方形可用区（避免矩形控件里 UV 被压扁）
		var side := minf(cs.x, cs.y)
		return Rect2((cs - Vector2(side, side)) * 0.5, Vector2(side, side))
	var ts := Vector2(float(_image.get_width()), float(_image.get_height()))
	if ts.x < 1.0 or ts.y < 1.0:
		return Rect2(Vector2.ZERO, cs)
	var sc := minf(cs.x / ts.x, cs.y / ts.y)
	var drawn := ts * sc
	return Rect2((cs - drawn) * 0.5, drawn)


func _on_overlay_draw() -> void:
	_draw_unit_markers()
	if _viewport_quad.size() >= 4:
		var pts := PackedVector2Array()
		for i in range(4):
			pts.append(_uv_to_overlay(_viewport_quad[i]))
		pts.append(pts[0])
		_overlay.draw_polyline(pts, Color(1.0, 0.85, 0.2, 1.0), 1.5, true)


func _draw_unit_markers() -> void:
	if _unit_host == null or _hf == null or not _hf.is_valid():
		return
	_ensure_icons()
	for c in _unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var n := c as Node3D
		if not WorldMembership.is_in_world(n):
			continue
		if not n.has_meta("unit_data"):
			continue
		var d: Dictionary = n.get_meta("unit_data", {})
		var tid := str(d.get("typeId", "")).strip_edges()
		if tid.is_empty() or tid == "sloc":
			continue
		var uv := MapMinimapUtils.world_to_minimap_uv(n.global_position, _hf)
		if uv.x < -0.02 or uv.y < -0.02 or uv.x > 1.02 or uv.y > 1.02:
			continue
		var pos := _uv_to_overlay(uv)
		var owner_id := int(d.get("owner", -1))
		var is_bldg := _is_building_type(tid)
		var icon := _pick_icon(tid, owner_id, is_bldg)
		if icon != null:
			var sz := _icon_draw_size(icon)
			_overlay.draw_texture_rect(icon, Rect2(pos - sz * 0.5, sz), false)
		else:
			var col := _dot_color(tid, owner_id)
			var half := DOT_BLDG if is_bldg else DOT_UNIT
			_overlay.draw_rect(Rect2(pos - Vector2(half, half), Vector2(half * 2.0, half * 2.0)), col)


func _is_building_type(type_id: String) -> bool:
	if BuildingVisualScr.is_building(type_id):
		return true
	if _catalog != null:
		return bool(_catalog.lookup(type_id).get("is_building", false))
	return false


func _icon_draw_size(icon: Texture2D) -> Vector2:
	if icon == null:
		return Vector2.ZERO
	return icon.get_size() * ICON_DRAW_SCALE


## 仅金矿球 / 中立小屋；其余返回 null → 队伍色或中立黑点。
func _pick_icon(type_id: String, owner_id: int, is_building: bool) -> Texture2D:
	if type_id == GOLD_MINE_TYPE:
		return _icon_gold
	if is_building and _shows_neutral_building_icon(type_id, owner_id):
		return _icon_neutral_bldg
	return null


func _shows_neutral_building_icon(type_id: String, owner_id: int) -> bool:
	if _nbmm_cache.has(type_id):
		return bool(_nbmm_cache[type_id])
	var show_icon := false
	if _catalog != null:
		var info: Dictionary = _catalog.lookup(type_id)
		if info.has("nbmm_icon"):
			show_icon = bool(info.get("nbmm_icon", false))
		else:
			var is_neutral := owner_id >= NEUTRAL_OWNER_MIN or owner_id < 0
			show_icon = is_neutral and bool(info.get("is_building", false))
	else:
		var from_ui := _nbmm_lookup_defstore(type_id)
		if from_ui["found"]:
			show_icon = bool(from_ui["value"])
		else:
			show_icon = owner_id >= NEUTRAL_OWNER_MIN or owner_id < 0
	_nbmm_cache[type_id] = show_icon
	return show_icon


## {found: bool, value: bool}
func _nbmm_lookup_defstore(type_id: String) -> Dictionary:
	var out := {"found": false, "value": false}
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return out
	var ds: Node = (loop as SceneTree).root.get_node_or_null("Wc3DefStore")
	if ds == null or not ds.has_method("get_row"):
		return out
	ds.call("ensure_table", UnitUiDef.TABLE_NAME)
	var row: Resource = ds.call("get_row", UnitUiDef.TABLE_NAME, type_id) as Resource
	if row is UnitUiDef:
		out["found"] = true
		out["value"] = (row as UnitUiDef).nbmm_icon
	return out


## 玩家 → 队伍色；中立 → 黑。
func _dot_color(type_id: String, owner_id: int) -> Color:
	if owner_id >= NEUTRAL_OWNER_MIN or owner_id < 0:
		return _NEUTRAL_DOT
	var color_i := MapUnitLayer.resolve_team_color_index(type_id, owner_id)
	if color_i >= 0 and color_i < MapPlaceholders.PLAYER_COLORS.size():
		return MapPlaceholders.PLAYER_COLORS[color_i]
	return MapPlaceholders.PLAYER_COLORS[clampi(owner_id, 0, MapPlaceholders.PLAYER_COLORS.size() - 1)]
