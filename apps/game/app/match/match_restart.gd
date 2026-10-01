extends Node

var old_game: Node
var packed: PackedScene
var settings: Dictionary = {}
var players: Array = []

func _ready() -> void:
	call_deferred("_replace")

func _replace() -> void:
	if not is_instance_valid(old_game) or packed == null:
		queue_free()
		return
	var replacement := packed.instantiate()
	if replacement is GameMain:
		(replacement as GameMain).configure_match(settings)
	else:
		var director := replacement.get_node_or_null("GameDirector")
		if director != null:
			for key in settings:
				director.set(key, settings[key])
	var parent := old_game.get_parent()
	var tree := get_tree()
	var was_current := tree.current_scene == old_game
	var game_name := old_game.name
	# 先完成旧场景清理，再允许新场景初始化；避免旧节点清理污染新局。
	old_game.free()
	for player in players:
		HeroDeathRegistry.clear_owner(int(player))
	replacement.name = game_name
	parent.add_child(replacement)
	if was_current:
		tree.current_scene = replacement
	queue_free()
