extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed: PackedScene = load("res://boot.tscn") as PackedScene
	var boot: Node = packed.instantiate()
	var tree: SceneTree = get_tree()
	tree.root.add_child(boot)
	tree.current_scene = boot
	var deadline: int = Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if tree.current_scene is GameMain and not is_instance_valid(boot):
			var game: GameMain = tree.current_scene as GameMain
			if game.is_session_ready() and game.has_playable_match():
				print("selftest_normal_startup: PASS (loading completed, playable match ready)")
				tree.quit(0)
				return
	push_error("Normal startup did not finish loading within 180 seconds")
	tree.quit(1)
