extends Node

func _ready() -> void:
	call_deferred("_start")

func _start() -> void:
	var packed := load("res://scenes/editor_main.tscn") as PackedScene
	if packed == null:
		get_tree().quit(1)
		return
	var scene := packed.instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	if not "--smoke-test" in OS.get_cmdline_user_args():
		queue_free()
		return

	await get_tree().process_frame
	if scene.get_node_or_null("Editor") == null:
		get_tree().quit(1)
		return

	print("APP startup PASS: map_editor")
	get_tree().quit(0)
