extends Node3D
## 简易轨道相机：WASD 平移，右键旋转，滚轮缩放。

@export var move_speed: float = 40.0
@export var look_sensitivity: float = 0.003
@export var zoom_speed: float = 4.0
@export var min_pitch_deg: float = -85.0
@export var max_pitch_deg: float = -15.0

@onready var _pivot: Node3D = $Pivot
@onready var _camera: Camera3D = $Pivot/Camera3D

var _yaw: float = 0.0
var _pitch: float = deg_to_rad(-45.0)
var _distance: float = 80.0
var _dragging: bool = false


func _ready() -> void:
	# Lost Temple 大致中心附近
	global_position = Vector3(0, 0, 0)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(8.0, _distance - zoom_speed)
			_apply()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(250.0, _distance + zoom_speed)
			_apply()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * look_sensitivity
		_pitch -= mm.relative.y * look_sensitivity
		_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
		_apply()


func _process(delta: float) -> void:
	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_key_pressed(KEY_Q):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_E):
		input_dir.y += 1.0

	if input_dir != Vector3.ZERO:
		var basis_yaw := Basis(Vector3.UP, _yaw)
		var move := (basis_yaw * input_dir).normalized()
		var speed := move_speed
		if Input.is_key_pressed(KEY_SHIFT):
			speed *= 3.0
		global_position += move * speed * delta


func _apply() -> void:
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, _distance)
