extends Node

const GAME_MAIN_SCENE : PackedScene = preload("res://scenes/game_main.tscn")

func _ready() -> void:
	call_deferred("_start")

func _start() -> void:
	var packed := GAME_MAIN_SCENE as PackedScene
	if not is_instance_valid(packed):
		get_tree().quit(1)
		return
	var scene := packed.instantiate()
	var director = scene.get_node("GameDirector")
	if "--smoke-test" in OS.get_cmdline_user_args():
		director.spawn_opponent_base = true
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	if not "--smoke-test" in OS.get_cmdline_user_args():
		queue_free()
		return

	var deadline := Time.get_ticks_msec() + 180000
	while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not director.is_session_ready():
		push_error("Game startup timed out")
		get_tree().quit(1)
		return
	if director.get_session() == null or \
			director.map_root.get_unit_layer().get_child_count() < 12:
		push_error("Game startup did not create a playable match")
		get_tree().quit(1)
		return

	print("APP startup PASS: game")
	get_tree().quit(0)
