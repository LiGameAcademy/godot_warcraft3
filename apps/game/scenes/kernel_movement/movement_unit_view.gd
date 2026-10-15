class_name RtsMovementUnitView
extends Node3D

var unit_code: String = ""
var _model: Wc3ModelScene
var _from_position: Vector3 = Vector3.ZERO
var _to_position: Vector3 = Vector3.ZERO
var _from_facing: float = 0.0
var _to_facing: float = 0.0
var _initialized: bool = false
var _moving: bool = false
@onready var _ring: MeshInstance3D = $SelectionRing


func configure(code: String, model: Wc3ModelScene) -> void:
	unit_code = code
	_model = model
	add_child(model)
	_model.play_logical("Stand")


func accept_frame(wc3_position: Vector3, facing: float, radius: float, moving: bool, snap: bool) -> void:
	_from_position = _to_position
	_from_facing = _to_facing
	_to_position = Wc3Coords.wc3_to_godot(wc3_position)
	_to_facing = Wc3Coords.yaw_wc3_unit_to_godot(facing)
	if not _initialized or snap:
		_from_position = _to_position
		_from_facing = _to_facing
		_initialized = true
		position = _to_position
		_model.rotation.y = _to_facing
	_ring.scale = Vector3(radius * Wc3Coords.WORLD_SCALE, 1.0, radius * Wc3Coords.WORLD_SCALE)
	if moving != _moving:
		_moving = moving
		_model.play_logical("Walk" if moving else "Stand")


func display(alpha: float, selected: bool) -> void:
	position = _from_position.lerp(_to_position, alpha)
	_model.rotation.y = lerp_angle(_from_facing, _to_facing, alpha)
	_ring.visible = selected
