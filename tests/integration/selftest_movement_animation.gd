extends SceneTree

class TestModel extends Wc3ModelScene:
	var player: AnimationPlayer = AnimationPlayer.new()
	var visual: Node3D = Node3D.new()

	func _enter_tree() -> void:
		pass

	func _ready() -> void:
		pass

	func setup() -> void:
		visual.name = "Visual"
		add_child(visual)
		add_child(player)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var library: AnimationLibrary = AnimationLibrary.new()
		for clip: String in ["Stand", "Walk"]:
			var animation: Animation = Animation.new()
			animation.length = 1.0
			animation.loop_mode = Animation.LOOP_NONE
			var track: int = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(track, NodePath("Visual:position"))
			animation.track_insert_key(track, 0.0, Vector3(10, 0, 0) if clip == "Walk" else Vector3.ZERO)
			library.add_animation(clip, animation)
		player.add_animation_library("", library)

	func animation_player() -> AnimationPlayer:
		return player

	func resolve_logical(logical_name: String) -> String:
		return logical_name

	func play_logical(logical: String, blend: float = 0.0, _cache: Variant = null,
		_activity_hint: int = 0, _fallbacks: Array = []) -> Dictionary:
		player.play(logical, blend)
		player.advance(0.0)
		return {"ok": true}

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/kernel_movement/movement_unit_view.tscn")
	var view: RtsMovementUnitView = scene.instantiate() as RtsMovementUnitView
	root.add_child(view)
	var model: TestModel = TestModel.new()
	model.setup()
	var template: Animation = model.player.get_animation("Walk")
	view.configure("test", model)
	_check(template.loop_mode == Animation.LOOP_NONE, "model template remains unchanged")
	_check(model.player.get_animation("Walk").loop_mode == Animation.LOOP_LINEAR, "walk loops on this instance")
	view.accept_frame(Vector3.ZERO, 0.0, 31.0, true)
	view.accept_frame(Vector3(9, 0, 0), 0.0, 31.0, false)
	view.display(1.0, false, 1.0 / 30.0)
	_check(model.player.current_animation == "Walk", "actual displacement starts walking")
	model.player.advance(0.025)
	model.player.advance(0.025)
	_check(model.visual.position.x > 0.0 and model.visual.position.x < 10.0, "walk blends instead of seeking first pose")
	view.accept_frame(Vector3(9, 0, 0), 0.0, 31.0, false)
	view.display(1.0, false, 1.0 / 30.0)
	_check(model.player.current_animation == "Walk", "one blocked tick does not restart animation")
	view.display(1.0, false, 1.0 / 30.0)
	_check(model.player.current_animation == "Stand", "continued wait enters idle")
	model.player.advance(0.2)
	for i: int in range(10):
		view.accept_frame(Vector3(9.0 + (i + 1) * 0.01, 0, 0), 0.0, 31.0, false)
		view.display(1.0, false, 1.0 / 30.0)
	_check(model.player.current_animation == "Stand", "tiny adjustments do not walk")
	view.accept_frame(Vector3(20, 0, 0), 0.0, 31.0, false)
	view.display(1.0, false, 1.0 / 30.0)
	_check(model.player.current_animation == "Walk", "motion resumes walking")
	view.accept_frame(Vector3(2000, 0, 0), 1.0, 31.0, true)
	view.display(1.0, false, 1.0 / 30.0)
	_check(model.player.current_animation == "Stand", "snapshot jump is not locomotion")
	view.queue_free()
	await process_frame
	print("MOVEMENT_ANIMATION_CHECKS failures=", failures)
	quit(0 if failures == 0 else 1)
