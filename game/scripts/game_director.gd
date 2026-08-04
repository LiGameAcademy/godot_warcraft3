class_name GameDirector
extends Node

## 游戏总管（对标 MapEditor）。
## 职责：配置 MapLoader、Melee 开局（随机 sloc + 种族预览刷兵）、相机。

const MeleeRacePreviewScr = preload("res://game/scripts/data/melee_race_preview.gd")
const MeleeBootstrapScr = preload("res://game/scripts/logic/melee_bootstrap.gd")
const BuildingVisualScr = preload("res://scripts/map/presentation/building_visual.gd")

@export var map_root: MapLoader
@export var rts_camera: RtsCamera
@export var game_hud: GameHud
@export var map_dir: String = "res://assets/map-parsed/echoisles"
## 开发期：0 无 / 1 大黄 / 2 大+中 / 3 大+中+小灰(32)
@export_range(0, 3) var view_grid_level: int = 3
@export var show_pathing_ground: bool = true
@export var show_ramp_debug: bool = false

@export_group("Melee 开局")
## 预览种族：human / orc / undead / nightelf
@export var preview_race: String = "human"
## 本地玩家 owner（队伍色）
@export_range(0, 15) var local_player: int = 0
## true：在地图 sloc 中随机选一个；false：优先匹配 local_player 的 owner
@export var random_start_location: bool = true
@export var spawn_melee_base: bool = true
## 开发：F6 Birth / F7 Stand Work（训练烟）/ F8 Stand
@export var debug_building_fx_hotkeys: bool = true

@export_group("相机")
## 对齐 WC3 CameraRates Forward≈3000 → ×WORLD_SCALE
@export var camera_pan_speed: float = 30.0
## 默认最远档 1650（MiscData）；滚轮六档联动 AOA，勿再拉到 50+
@export var camera_initial_distance: float = 16.5
@export var camera_min_distance: float = 11.0
@export var camera_max_distance: float = 16.5
@export var camera_initial_pitch_deg: float = -56.0
@export var camera_fov: float = 70.0
@export var use_wc3_zoom_curve: bool = true
@export var apply_camera_bounds: bool = true

## Echo Isles cameraBounds（WC3 XY）；小地图点击跳转用
var _cam_min := Vector2(-6912.0, -5376.0)
var _cam_max := Vector2(6912.0, 4864.0)
var _rng := RandomNumberGenerator.new()
var _bootstrapped: bool = false


func _ready() -> void:
	_rng.randomize()
	_resolve_exports()
	if map_root == null:
		push_error("GameDirector: 未绑定 map_root")
		return
	_configure_map_root()
	_wire_hud()
	_load_camera_bounds()
	_configure_camera()
	if map_root.map_loaded.is_connected(_on_map_loaded) == false:
		map_root.map_loaded.connect(_on_map_loaded)
	if map_root.is_map_ready():
		_on_map_loaded()


func _resolve_exports() -> void:
	if map_root == null:
		map_root = get_node_or_null("../MapRoot") as MapLoader
	if rts_camera == null:
		rts_camera = get_node_or_null("../RtsCamera") as RtsCamera
	if game_hud == null:
		game_hud = get_node_or_null("../GameHud") as GameHud


func _configure_map_root() -> void:
	if not map_dir.is_empty():
		map_root.map_dir = map_dir
	map_root.place_doodads = true
	map_root.place_units = true
	map_root.show_pathing_debug_grid = true
	map_root.show_ramp_debug = show_ramp_debug
	map_root.show_pathing_ground = show_pathing_ground
	map_root.set_view_grid_level(view_grid_level)
	if show_pathing_ground and map_root.get_pathing_map() != null:
		map_root.set_show_pathing_ground(true)


func _configure_camera() -> void:
	if rts_camera == null:
		return
	rts_camera.pan_speed = camera_pan_speed
	rts_camera.use_wc3_zoom_curve = use_wc3_zoom_curve
	rts_camera.camera_fov = camera_fov
	rts_camera.min_distance = camera_min_distance
	rts_camera.max_distance = camera_max_distance
	rts_camera.initial_distance = camera_initial_distance
	rts_camera.initial_pitch_deg = camera_initial_pitch_deg
	rts_camera.apply_export_tuning()
	if apply_camera_bounds:
		_apply_camera_world_bounds()


func _apply_camera_world_bounds() -> void:
	if rts_camera == null:
		return
	# WC3 XY → Godot XZ：x'=x*s，z'=-y*s
	var s := Wc3Coords.WORLD_SCALE
	var min_xz := Vector2(_cam_min.x * s, -_cam_max.y * s)
	var max_xz := Vector2(_cam_max.x * s, -_cam_min.y * s)
	# 规范化（z 可能因取负翻转）
	var lo := Vector2(minf(min_xz.x, max_xz.x), minf(min_xz.y, max_xz.y))
	var hi := Vector2(maxf(min_xz.x, max_xz.x), maxf(min_xz.y, max_xz.y))
	rts_camera.set_boundaries(lo, hi)


func _wire_hud() -> void:
	if game_hud == null:
		return
	if not map_dir.is_empty():
		game_hud.map_dir = map_dir
	game_hud.set_status(_map_display_name())
	if not game_hud.minimap_clicked.is_connected(_on_minimap_clicked):
		game_hud.minimap_clicked.connect(_on_minimap_clicked)
	if not game_hud.command_pressed.is_connected(_on_command_pressed):
		game_hud.command_pressed.connect(_on_command_pressed)


func _map_display_name() -> String:
	var path := map_dir.path_join("info.json")
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			if typeof(data) == TYPE_DICTIONARY:
				var n := str((data as Dictionary).get("name", "")).strip_edges()
				if not n.is_empty():
					return n
	return map_dir.get_file()


func _load_camera_bounds() -> void:
	var path := map_dir.path_join("info.json")
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var b: Variant = data.get("cameraBounds", null)
	if b is Array and (b as Array).size() >= 4:
		var a: Array = b
		_cam_min = Vector2(float(a[0]), float(a[1]))
		_cam_max = Vector2(float(a[2]), float(a[3]))


func _on_map_loaded() -> void:
	if _bootstrapped:
		return
	_bootstrapped = true
	_bootstrap_melee()


func _bootstrap_melee() -> void:
	var race := MeleeRacePreviewScr.race_from_string(preview_race)
	var preview := MeleeRacePreviewScr.preview_dict(race)
	var slocs := MeleeBootstrapScr.collect_slocs(map_dir)
	if slocs.is_empty():
		if game_hud:
			game_hud.set_status("%s · 无 sloc，跳过开局刷兵" % str(preview.get("display_name", "")))
		return

	var sloc: Dictionary
	if random_start_location:
		sloc = MeleeBootstrapScr.pick_random_sloc(slocs, _rng)
	else:
		sloc = _find_sloc_for_owner(slocs, local_player)
		if sloc.is_empty():
			sloc = MeleeBootstrapScr.pick_random_sloc(slocs, _rng)

	var hall_world := Vector3.ZERO
	if spawn_melee_base:
		var hf := map_root.get_heightfield_dict()
		var result := MeleeBootstrapScr.spawn_at_sloc(map_root, sloc, race, local_player, hf)
		if result.get("ok", false):
			hall_world = result.get("hall_world", Vector3.ZERO) as Vector3
			if game_hud:
				game_hud.set_resources(750, 200, 5, 11)
				game_hud.set_status(
					"%s · %s @ sloc owner=%s · 刷 %d"
					% [
						_map_display_name(),
						str(preview.get("display_name", "")),
						str(sloc.get("owner", "?")),
						int(result.get("spawned", 0)),
					]
				)
		else:
			if game_hud:
				game_hud.set_status("%s · 开局刷兵失败" % str(preview.get("display_name", "")))
	else:
		var pos: Dictionary = sloc.get("position", {})
		hall_world = Wc3Coords.wc3_xy_to_godot(
			float(pos.get("x", 0.0)),
			float(pos.get("y", 0.0)),
			float(pos.get("z", 0.0))
		)

	if rts_camera and hall_world != Vector3.ZERO:
		rts_camera.snap_to(hall_world)
		rts_camera.focus_on_position(hall_world, 0.35)


func _find_sloc_for_owner(slocs: Array[Dictionary], owner_id: int) -> Dictionary:
	for s in slocs:
		if int(s.get("owner", -1)) == owner_id:
			return s
	return {}


func _unhandled_input(event: InputEvent) -> void:
	if not debug_building_fx_hotkeys:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var phase := -1
		var label := ""
		match (event as InputEventKey).keycode:
			KEY_F6:
				phase = BuildingVisualScr.Phase.BIRTH
				label = "Birth（建造尘）"
			KEY_F7:
				phase = BuildingVisualScr.Phase.WORK
				label = "Stand Work（训练烟）"
			KEY_F8:
				phase = BuildingVisualScr.Phase.IDLE
				label = "Stand"
			_:
				return
		if _debug_apply_hall_phase(phase):
			if game_hud:
				game_hud.set_status("主城 FX → %s" % label)
			get_viewport().set_input_as_handled()


func _debug_apply_hall_phase(phase: int) -> bool:
	if map_root == null:
		return false
	var layer := map_root.get_unit_layer()
	if layer == null:
		return false
	var cache: MapModelCache = null
	if map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	for c in layer.get_children():
		if not (c is Node3D):
			continue
		var d: Dictionary = (c as Node).get_meta("unit_data", {})
		var tid := str(d.get("typeId", ""))
		if tid != "htow" and tid != "hkee" and tid != "hcas":
			continue
		if cache != null:
			BuildingVisualScr.apply_phase(cache, c, tid, phase)
		return true
	return false


func _on_minimap_clicked(uv: Vector2) -> void:
	if rts_camera == null:
		return
	var wx := lerpf(_cam_min.x, _cam_max.x, uv.x)
	# 小地图顶 = 北 = 较大 WC3.Y
	var wy := lerpf(_cam_max.y, _cam_min.y, uv.y)
	var world := Wc3Coords.wc3_xy_to_godot(wx, wy, 0.0)
	rts_camera.focus_on_position(world)
	if game_hud:
		game_hud.set_status("镜头 → (%.0f, %.0f)" % [wx, wy])


func _on_command_pressed(slot: int) -> void:
	if game_hud:
		game_hud.set_status("指令格 [%d]（阶段 D 接命令层）" % slot)
