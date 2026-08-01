extends Node3D
## 编辑器用轨道相机。输入由 EditorInputRouter 注入（WE：RMB 平移 / Ctrl+RMB 旋转）。


@export var move_speed: float = 40.0
@export var look_sensitivity: float = 0.003
@export var zoom_speed: float = 4.0
@export var pan_drag_scale: float = 0.0025
@export var min_pitch_deg: float = -85.0
@export var max_pitch_deg: float = -15.0
## 约 3 个大栅格（512 WC3 单位）距离，便于近距编辑
@export var initial_distance: float = 15.36

@onready var _pivot: Node3D = $Pivot
@onready var _camera: Camera3D = $Pivot/Camera3D

## 大黄栅格边长 → Godot；初始观察距离约 3 格
const LARGE_GRID_GODOT := 512.0 * Wc3Coords.WORLD_SCALE ## 5.12
const EDIT_DISTANCE_GRIDS := 3.0

var _yaw: float = 0.0
var _pitch: float = deg_to_rad(-50.0)
var _distance: float = 15.36


func _ready() -> void:
	_distance = initial_distance
	global_position = Vector3(0, 0, 0)
	_apply()


func get_camera() -> Camera3D:
	return _camera


func get_orbit_distance() -> float:
	return _distance


func get_look_at() -> Vector3:
	return global_position


func focus_map_extent(_map_tiles: Vector2i, _tile_size_godot: float = 1.28) -> void:
	# 编辑默认近距：约 3 个大栅格，不再按整图拉远
	_distance = EDIT_DISTANCE_GRIDS * LARGE_GRID_GODOT
	global_position = Vector3(0, 0, 0)
	_apply()


## 屏幕像素位移 → 地面平移（RMB / 中键）。
func apply_pan_screen(screen_delta: Vector2) -> void:
	var basis_yaw := Basis(Vector3.UP, _yaw)
	var right: Vector3 = basis_yaw * Vector3.RIGHT
	var forward: Vector3 = basis_yaw * Vector3(0, 0, -1)
	var pan_scale: float = maxf(_distance, 4.0) * pan_drag_scale
	global_position += (-right * screen_delta.x + forward * screen_delta.y) * pan_scale


## Ctrl+RMB 轨道旋转。
func apply_orbit(screen_delta: Vector2) -> void:
	_yaw -= screen_delta.x * look_sensitivity
	_pitch -= screen_delta.y * look_sensitivity
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	_apply()


## steps < 0 拉近，> 0 拉远。
func apply_zoom(steps: int) -> void:
	if steps == 0:
		return
	_distance = clampf(_distance + float(steps) * zoom_speed, 4.0, 280.0)
	_apply()


## 由 InputRouter 每帧注入（方向键 / WASD / QE）。
func set_keyboard_move(dir: Vector3, sprint: bool, delta: float) -> void:
	if dir == Vector3.ZERO:
		return
	var basis_yaw := Basis(Vector3.UP, _yaw)
	var move := (basis_yaw * dir).normalized()
	var speed := move_speed * (3.0 if sprint else 1.0)
	global_position += move * speed * delta


func _apply() -> void:
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, _distance)
