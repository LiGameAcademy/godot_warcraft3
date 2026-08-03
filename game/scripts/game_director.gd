class_name GameDirector
extends Node

## 游戏总管（对标 MapEditor）。
## 职责：配置共用 MapLoader、开发期可视化、后续挂 Session / MeleeBootstrap / 输入。
## 不拼地形 Mesh、不写 Heightfield；表现一律走 map_root。

@export var map_root: MapLoader
@export var rts_camera: RtsCamera
@export var game_hud: GameHud
@export var map_dir: String = "res://assets/map-parsed/echoisles"
## 开发期：0 无 / 1 大黄 / 2 大+中 / 3 大+中+小灰(32)
@export_range(0, 3) var view_grid_level: int = 3
@export var show_pathing_ground: bool = true
@export var show_ramp_debug: bool = false

## Echo Isles cameraBounds（WC3 XY）；小地图点击跳转用
var _cam_min := Vector2(-6912.0, -5376.0)
var _cam_max := Vector2(6912.0, 4864.0)


func _ready() -> void:
	_resolve_exports()
	if map_root == null:
		push_error("GameDirector: 未绑定 map_root")
		return
	_configure_map_root()
	_wire_hud()
	_load_camera_bounds()


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
