class_name RtsCamera
extends Node3D

## 游戏用 RTS 相机：地面观察点 + Pivot 俯仰/偏航 + 相机距离。
## 场景结构对齐 editor_camera；操作语义对齐 classic RTS / godot_simple_rts。
## 不占用右键（留给选单位/下命令）。

@export_group("平移")
@export var pan_speed: float = 55.0
@export var pan_sprint_mult: float = 2.5
@export var edge_pan_margin: int = 28
@export var edge_pan_enabled: bool = true
@export var pan_smoothing: float = 12.0

@export_group("旋转")
@export var look_sensitivity: float = 0.003
@export var min_pitch_deg: float = -75.0
@export var max_pitch_deg: float = -20.0
@export var initial_pitch_deg: float = -50.0

@export_group("缩放")
@export var zoom_step: float = 4.0
@export var min_distance: float = 12.0
@export var max_distance: float = 220.0
@export var initial_distance: float = 48.0

@export_group("边界")
## 世界 XZ（Godot）；未设置时不夹紧。可由 GameDirector 按地图 extent 注入。
@export var boundary_min: Vector2 = Vector2(-1e6, -1e6)
@export var boundary_max: Vector2 = Vector2(1e6, 1e6)
@export var use_boundaries: bool = false

@export_group("聚焦")
@export var focus_duration: float = 0.45

@onready var _pivot: Node3D = $Pivot
@onready var _camera: Camera3D = $Pivot/Camera3D

var _yaw: float = 0.0
var _pitch: float = deg_to_rad(-50.0)
var _distance: float = 48.0
var _orbit_dragging: bool = false
var _pan_velocity: Vector3 = Vector3.ZERO
var _focus_tween: Tween


func _ready() -> void:
	_pitch = deg_to_rad(initial_pitch_deg)
	_distance = initial_distance
	_apply()


func get_camera() -> Camera3D:
	return _camera


func get_look_at() -> Vector3:
	return global_position


func get_orbit_distance() -> float:
	return _distance


## 瞬间落到观察点（XZ）；Y 保持当前高度（默认贴地平面）。
func snap_to(world_pos: Vector3) -> void:
	_kill_focus_tween()
	global_position = Vector3(world_pos.x, global_position.y, world_pos.z)
	_clamp_to_bounds()
	_pan_velocity = Vector3.ZERO


## 平滑聚焦（阶段 B：开始点相机）。
func focus_on_position(world_pos: Vector3, duration: float = -1.0) -> void:
	_kill_focus_tween()
	var target := Vector3(world_pos.x, global_position.y, world_pos.z)
	if use_boundaries:
		target.x = clampf(target.x, boundary_min.x, boundary_max.x)
		target.z = clampf(target.z, boundary_min.y, boundary_max.y)
	var dur: float = focus_duration if duration < 0.0 else duration
	_focus_tween = create_tween()
	_focus_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(self, "global_position", target, dur)
	_pan_velocity = Vector3.ZERO


func set_boundaries(min_xz: Vector2, max_xz: Vector2) -> void:
	boundary_min = min_xz
	boundary_max = max_xz
	use_boundaries = true
	_clamp_to_bounds()


func clear_boundaries() -> void:
	use_boundaries = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_orbit_dragging = mb.pressed
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_zoom(-1)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_zoom(1)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _orbit_dragging:
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
	var t: float = clampf(delta * pan_smoothing, 0.0, 1.0)
	_pan_velocity = _pan_velocity.lerp(desired, t)
	if _pan_velocity.length_squared() > 0.0001:
		_kill_focus_tween()
		global_position += _pan_velocity * delta
		_clamp_to_bounds()


func _get_pan_input() -> Vector2:
	# 优先键盘（WASD + 方向键）
	var kb := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		kb.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		kb.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		kb.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		kb.y += 1.0
	if kb != Vector2.ZERO:
		return kb.normalized()

	if not edge_pan_enabled:
		return Vector2.ZERO
	var mouse_pos := get_viewport().get_mouse_position()
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return Vector2.ZERO
	# 窗口失焦时不边缘滚
	if not get_window().has_focus():
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


func _adjust_zoom(direction: int) -> void:
	_distance = clampf(_distance + float(direction) * zoom_step, min_distance, max_distance)
	_apply()


func _clamp_to_bounds() -> void:
	if not use_boundaries:
		return
	global_position.x = clampf(global_position.x, boundary_min.x, boundary_max.x)
	global_position.z = clampf(global_position.z, boundary_min.y, boundary_max.y)


func _kill_focus_tween() -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = null


func _apply() -> void:
	if _pivot == null or _camera == null:
		return
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, _distance)
