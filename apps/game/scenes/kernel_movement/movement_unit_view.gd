class_name RtsMovementUnitView
extends Node3D

# Presentation-only thresholds, in WC3 units/second. They never alter match state.
@export var walk_start_speed: float = 8.0
@export var walk_stop_speed: float = 4.0
@export var idle_delay: float = 0.06
@export var animation_blend: float = 0.10

var unit_code: String = ""
var _model: Wc3ModelScene
var _stand_clip: String = ""
var _walk_clip: String = ""
var _player: AnimationPlayer
var _from_position: Vector3 = Vector3.ZERO
var _to_position: Vector3 = Vector3.ZERO
var _from_facing: float = 0.0
var _to_facing: float = 0.0
var _initialized: bool = false
var _moving: bool = false
var _idle_elapsed: float = 0.0
@onready var _ring: MeshInstance3D = $SelectionRing


func configure(code: String, model: Wc3ModelScene) -> void:
	unit_code = code
	_model = model
	add_child(model)
	_model.play_logical("Stand")
	_player = _model.animation_player()
	_stand_clip = _prepare_loop("Stand")
	_walk_clip = _prepare_loop("Walk")


func accept_frame(wc3_position: Vector3, facing: float, radius: float, snap: bool) -> void:
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
		_reset_animation()
	_ring.scale = Vector3(radius * Wc3Coords.WORLD_SCALE, 1.0, radius * Wc3Coords.WORLD_SCALE)


func display(alpha: float, selected: bool, delta: float) -> void:
	var previous: Vector3 = position
	position = _from_position.lerp(_to_position, alpha)
	_model.rotation.y = lerp_angle(_from_facing, _to_facing, alpha)
	_ring.visible = selected
	if delta <= 0.0:
		return
	# Use the displayed planar displacement, including the final interpolated step.
	# Rotation, terrain height and snapshot jumps must not trigger walking.
	var distance: float = Vector2(position.x - previous.x, position.z - previous.z).length()
	var speed: float = distance / Wc3Coords.WORLD_SCALE / delta
	var threshold: float = walk_stop_speed if _moving else walk_start_speed
	if speed > threshold:
		_idle_elapsed = 0.0
		_set_walking(true, animation_blend)
	else:
		_idle_elapsed += delta
		if _idle_elapsed >= idle_delay:
			_set_walking(false, animation_blend)


## Snapshot discontinuities discard prior pose blending, even when already idle.
func _reset_animation() -> void:
	_moving = false
	_idle_elapsed = 0.0
	if _player == null or _stand_clip.is_empty():
		return
	_player.stop()
	_player.play(_stand_clip, 0.0)
	_player.advance(0.0)


func _set_walking(value: bool, blend: float) -> void:
	if value == _moving:
		return
	var clip: String = _walk_clip if value else _stand_clip
	if _player == null or clip.is_empty() or not _player.has_animation(clip):
		return
	_moving = value
	# Locomotion transitions must preserve AnimationPlayer blending. The general
	# model playback entry seeks frame zero immediately, which snaps the pose.
	_player.play(clip, blend)

## Locomotion loops are instance-owned; do not change the shared model template.
func _prepare_loop(logical: String) -> String:
	var clip: String = _model.resolve_logical(logical)
	if _player == null or clip.is_empty() or not _player.has_animation(clip):
		return ""
	var source: Animation = _player.get_animation(clip)
	if source.loop_mode != Animation.LOOP_LINEAR:
		var library_name: String = clip.get_slice("/", 0) if clip.contains("/") else ""
		var leaf: String = clip.get_slice("/", 1) if clip.contains("/") else clip
		var library: AnimationLibrary = _player.get_animation_library(library_name).duplicate() as AnimationLibrary
		var animation: Animation = source.duplicate() as Animation
		animation.loop_mode = Animation.LOOP_LINEAR
		library.remove_animation(leaf)
		library.add_animation(leaf, animation)
		_player.remove_animation_library(library_name)
		_player.add_animation_library(library_name, library)
	return clip
