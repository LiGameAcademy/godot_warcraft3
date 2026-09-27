class_name RtsCamera
extends Node3D

## 游戏用 RTS 相机：地面观察点 + Pivot 俯仰/偏航 + 相机距离。
## 滚轮缩放复刻 WC3 MiscData.txt：[Camera] 六档 Distance/AOA 联动。
## 不占用右键（留给选单位/下命令）；默认不响应中键旋转（对齐原作）。

## WC3 MiscData Distance（游戏单位）→ Godot（× WORLD_SCALE）。
## AOA 304→339：拉近时从俯视逐渐抬到近似平视（pitch = AOA − 360）。
const WC3_ZOOM_DISTANCES_WC3: Array[float] = [1650.0, 1600.0, 1500.0, 1400.0, 1275.0, 1100.0]
const WC3_ZOOM_AOA_DEG: Array[float] = [304.0, 311.0, 318.0, 325.0, 332.0, 339.0]

@export_group("平移")
@export var pan_speed: float = 30.0
@export var pan_sprint_mult: float = 2.5
@export var edge_pan_margin: int = 28
@export var edge_pan_enabled: bool = true
## 0：立即响应并停止；正数：指数平滑速率（每秒）。
@export var pan_smoothing: float = 0.0
## 游戏场景关闭 WASD（与停止/移动等热键冲突）；方向键与边缘滚动仍可用。
@export var wasd_pan_enabled: bool = false
@export var arrow_pan_enabled: bool = true

@export_group("旋转")
@export var look_sensitivity: float = 0.003
@export var min_pitch_deg: float = -75.0
@export var max_pitch_deg: float = -18.0
@export var initial_pitch_deg: float = -56.0
## WC3 原作无中键/拖拽旋转镜头；默认关闭。调试预览可再打开。
@export var allow_manual_orbit: bool = false

@export_group("缩放")
## true：滚轮走 WC3 六档，距离与俯仰联动；false：自由距离 + 固定俯仰。
@export var use_wc3_zoom_curve: bool = true
@export var zoom_step: float = 1.0
@export var min_distance: float = 11.0
@export var max_distance: float = 16.5
@export var initial_distance: float = 16.5
## Godot 垂直 FOV。50 是本轮视觉校准起点，不是 WC3 参数的直接换算。
@export var camera_fov: float = 50.0
@export_range(0.0, 1.0, 0.01) var zoom_duration: float = 0.18

@export_group("地形")
@export var terrain_follow_enabled: bool = true
## 空间采样半径（Godot 单位），避免小地形起伏直接传给镜头。
@export var terrain_sample_radius: float = 1.28
@export var terrain_height_smoothing: float = 10.0
@export var target_height_offset: float = 0.0

@export_group("边界")
## 世界 XZ（Godot）；未设置时不夹紧。可由 GameDirector 按地图 extent 注入。
@export var boundary_min: Vector2 = Vector2(-1e6, -1e6)
@export var boundary_max: Vector2 = Vector2(1e6, 1e6)
@export var use_boundaries: bool = false

@export_group("聚焦")
## 默认小地图定位立即生效；开场等显式传入 duration 的调用保留动画。
@export var focus_duration: float = 0.0

@onready var _pivot: Node3D = $Pivot
@onready var _camera: Camera3D = $Pivot/Camera3D

var _yaw: float = 0.0
var _pitch: float = deg_to_rad(-56.0)
var _distance: float = 16.5
var _zoom_index: int = 0
var _orbit_dragging: bool = false
var _pan_velocity: Vector3 = Vector3.ZERO
var _focus_tween: Tween
var _zoom_tween: Tween
var _heightfield: Wc3Heightfield
## GameMain.setup() 注入的地图根（仅引用，不直接持有；MapRoot 装配由 MapLoader 自己负责）。
## [br]当前仅缓存；具体地形采样 / 边界夹紧仍由 GameDirector._configure_camera 写入
## [member set_heightfield] 与 [member set_boundaries]。
var _map_root_ref: MapLoader = null


func _ready() -> void:
	apply_export_tuning()


## 由 [GameMain] 在子节点装配第 4 步调 [method setup] 注入。
##
## [code]p_map_root[/code] 仅写入 [member _map_root_ref] 字段（未来地形跟随用）；
## 不修改任何 @export 字段。具体的 zoom / fov / 边界参数由
## [GameDirector._configure_camera] 在 [method GameDirector._boot_match] 中按需写入。
##
## [param p_map_root] 地图根（用于缓存引用，便于后续地形 / 边界注入）。
func setup(p_map_root: MapLoader) -> void:
	_map_root_ref = p_map_root
	apply_export_tuning()


## 把 @export 缩放/俯仰同步到运行时内部状态（Director 可在 _ready 后再调）。
func apply_export_tuning() -> void:
	_kill_zoom_tween()
	if _camera:
		_camera.keep_aspect = Camera3D.KEEP_HEIGHT
		_camera.fov = camera_fov
	if use_wc3_zoom_curve:
		_rebuild_wc3_distance_limits()
		_zoom_index = _nearest_zoom_index(initial_distance)
		_apply_zoom_level(_zoom_index, false)
	else:
		_pitch = deg_to_rad(initial_pitch_deg)
		_distance = clampf(initial_distance, min_distance, max_distance)
		_apply()


func get_camera() -> Camera3D:
	return _camera


func get_look_at() -> Vector3:
	return global_position


func get_orbit_distance() -> float:
	return _distance


func get_zoom_index() -> int:
	return _zoom_index


## 地图就绪后注入；未绑定时维持原有固定高度行为。
func set_heightfield(heightfield: Wc3Heightfield) -> void:
	_heightfield = heightfield
	_update_terrain_height(0.0, true)


## 瞬间定位时同步地形高度，避免切到高地后再慢慢抬升。
func snap_to(world_pos: Vector3) -> void:
	_kill_focus_tween()
	global_position = Vector3(world_pos.x, global_position.y, world_pos.z)
	_clamp_to_bounds()
	_update_terrain_height(0.0, true)
	_pan_velocity = Vector3.ZERO


## 平滑聚焦（阶段 B：开始点相机）。
func focus_on_position(world_pos: Vector3, duration: float = -1.0) -> void:
	_kill_focus_tween()
	var target := Vector3(world_pos.x, global_position.y, world_pos.z)
	if use_boundaries:
		target.x = clampf(target.x, boundary_min.x, boundary_max.x)
		target.z = clampf(target.z, boundary_min.y, boundary_max.y)
	var dur: float = focus_duration if duration < 0.0 else duration
	if dur <= 0.0:
		snap_to(target)
		return
	_focus_tween = create_tween()
	_focus_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 只动画 XZ，避免 Tween 每帧覆盖地形跟随的 Y。
	_focus_tween.tween_method(_set_focus_xz, Vector2(global_position.x, global_position.z), Vector2(target.x, target.z), dur)
	_pan_velocity = Vector3.ZERO


func _set_focus_xz(value: Vector2) -> void:
	global_position.x = value.x
	global_position.z = value.y
	_clamp_to_bounds()


func set_boundaries(min_xz: Vector2, max_xz: Vector2) -> void:
	boundary_min = min_xz
	boundary_max = max_xz
	use_boundaries = true
	_clamp_to_bounds()


func clear_boundaries() -> void:
	use_boundaries = false


func _unhandled_input(event: InputEvent) -> void:
	if not _camera_input_allowed():
		_orbit_dragging = false
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE and allow_manual_orbit:
			_orbit_dragging = mb.pressed
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			# 滚轮上 = 拉近（更高 AOA / 更平视）
			_adjust_zoom(1)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# 滚轮下 = 拉远（更俯视）
			_adjust_zoom(-1)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _orbit_dragging and allow_manual_orbit:
		_kill_zoom_tween()
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * look_sensitivity
		_pitch -= mm.relative.y * look_sensitivity
		_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
		_apply()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var pan_input := _get_pan_input()
	var desired := Vector3.ZERO
	if pan_input != Vector2.ZERO:
		var basis_yaw := Basis(Vector3.UP, _yaw)
		var right: Vector3 = basis_yaw * Vector3.RIGHT
		var forward: Vector3 = basis_yaw * Vector3(0.0, 0.0, -1.0)
		desired = (right * pan_input.x + forward * (-pan_input.y)).normalized()
		var speed: float = pan_speed
		if Input.is_key_pressed(KEY_SHIFT):
			speed *= pan_sprint_mult
		desired *= speed
	var t: float = 1.0 if pan_smoothing <= 0.0 else 1.0 - exp(-delta * pan_smoothing)
	_pan_velocity = _pan_velocity.lerp(desired, t)
	if _pan_velocity.length_squared() > 0.0001:
		_kill_focus_tween()
		global_position += _pan_velocity * delta
		_clamp_to_bounds()
	_update_terrain_height(delta)


func _get_pan_input() -> Vector2:
	if not _camera_input_allowed():
		_pan_velocity = Vector3.ZERO
		_orbit_dragging = false
		return Vector2.ZERO
	var kb := Vector2.ZERO
	if arrow_pan_enabled:
		if Input.is_key_pressed(KEY_LEFT):
			kb.x -= 1.0
		if Input.is_key_pressed(KEY_RIGHT):
			kb.x += 1.0
		if Input.is_key_pressed(KEY_UP):
			kb.y -= 1.0
		if Input.is_key_pressed(KEY_DOWN):
			kb.y += 1.0
	if wasd_pan_enabled:
		if Input.is_key_pressed(KEY_A):
			kb.x -= 1.0
		if Input.is_key_pressed(KEY_D):
			kb.x += 1.0
		if Input.is_key_pressed(KEY_W):
			kb.y -= 1.0
		if Input.is_key_pressed(KEY_S):
			kb.y += 1.0
	if kb != Vector2.ZERO:
		return kb.normalized()

	if not edge_pan_enabled:
		return Vector2.ZERO
	var mouse_pos := get_viewport().get_mouse_position()
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return Vector2.ZERO
	if not get_window().has_focus():
		return Vector2.ZERO
	if not Rect2(Vector2.ZERO, vp).has_point(mouse_pos):
		return Vector2.ZERO
	var edge := Vector2.ZERO
	var m := float(edge_pan_margin)
	if mouse_pos.x < m:
		edge.x = -1.0
	elif mouse_pos.x > vp.x - m:
		edge.x = 1.0
	if mouse_pos.y < m:
		edge.y = -1.0
	elif mouse_pos.y > vp.y - m:
		edge.y = 1.0
	return edge.normalized()


func _camera_input_allowed() -> bool:
	if not get_window().has_focus():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	return not (focus is LineEdit or focus is TextEdit)


func _sample_terrain_height(world_xz: Vector2) -> float:
	var wc3 := Vector2(world_xz.x, -world_xz.y) / Wc3Coords.WORLD_SCALE
	var lo := _heightfield.center_offset
	# Heightfield 的插值需要右上邻点，采样保持在最后一格内部。
	var hi := lo + Vector2(_heightfield.width - 1, _heightfield.height - 1) * _heightfield.tile_size - Vector2.ONE * 0.01
	wc3 = wc3.clamp(lo, hi)
	return _heightfield.interpolated_height(wc3.x, wc3.y) * Wc3Coords.WORLD_SCALE


func _update_terrain_height(delta: float, instant: bool = false) -> void:
	if not terrain_follow_enabled or _heightfield == null or not _heightfield.is_valid():
		return
	if _heightfield.width < 2 or _heightfield.height < 2:
		return
	var center := Vector2(global_position.x, global_position.z)
	var height := _sample_terrain_height(center) * 4.0
	var radius := maxf(terrain_sample_radius, 0.0)
	for offset in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		height += _sample_terrain_height(center + offset * radius)
	height = height / 8.0 + target_height_offset
	var weight := 1.0 if instant or terrain_height_smoothing <= 0.0 else 1.0 - exp(-delta * terrain_height_smoothing)
	global_position.y = lerpf(global_position.y, height, weight)


func _adjust_zoom(direction: int) -> void:
	if use_wc3_zoom_curve:
		# direction>0 = 拉近（index↑）；direction<0 = 拉远（index↓）
		var next := clampi(_zoom_index + direction, 0, WC3_ZOOM_DISTANCES_WC3.size() - 1)
		if next == _zoom_index:
			return
		_apply_zoom_level(next, true)
	else:
		_distance = clampf(_distance - float(direction) * zoom_step, min_distance, max_distance)
		_apply()


func _apply_zoom_level(index: int, animate: bool) -> void:
	_kill_zoom_tween()
	_zoom_index = clampi(index, 0, WC3_ZOOM_DISTANCES_WC3.size() - 1)
	var target := Vector2(
		_wc3_distance_to_godot(WC3_ZOOM_DISTANCES_WC3[_zoom_index]),
		deg_to_rad(_aoa_to_pitch_deg(WC3_ZOOM_AOA_DEG[_zoom_index]))
	)
	if animate and zoom_duration > 0.0:
		_zoom_tween = create_tween()
		_zoom_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_zoom_tween.tween_method(_set_zoom_state, Vector2(_distance, _pitch), target, zoom_duration)
	else:
		_set_zoom_state(target)


func _set_zoom_state(value: Vector2) -> void:
	_distance = value.x
	_pitch = value.y
	_apply()


func _rebuild_wc3_distance_limits() -> void:
	var d0 := _wc3_distance_to_godot(WC3_ZOOM_DISTANCES_WC3[WC3_ZOOM_DISTANCES_WC3.size() - 1])
	var d1 := _wc3_distance_to_godot(WC3_ZOOM_DISTANCES_WC3[0])
	min_distance = minf(d0, d1)
	max_distance = maxf(d0, d1)


func _nearest_zoom_index(godot_distance: float) -> int:
	var best := 0
	var best_d := INF
	for i in range(WC3_ZOOM_DISTANCES_WC3.size()):
		var d: float = absf(_wc3_distance_to_godot(WC3_ZOOM_DISTANCES_WC3[i]) - godot_distance)
		if d < best_d:
			best_d = d
			best = i
	return best


static func _wc3_distance_to_godot(wc3_dist: float) -> float:
	return wc3_dist * Wc3Coords.WORLD_SCALE


static func _aoa_to_pitch_deg(aoa_deg: float) -> float:
	## WC3 AOA：270=竖直俯视，360=水平。Godot pitch 负值朝下 → AOA−360。
	return aoa_deg - 360.0


func _clamp_to_bounds() -> void:
	if not use_boundaries:
		return
	global_position.x = clampf(global_position.x, boundary_min.x, boundary_max.x)
	global_position.z = clampf(global_position.z, boundary_min.y, boundary_max.y)


func _kill_focus_tween() -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = null


func _kill_zoom_tween() -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = null


func _apply() -> void:
	if _pivot == null or _camera == null:
		return
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, _distance)
