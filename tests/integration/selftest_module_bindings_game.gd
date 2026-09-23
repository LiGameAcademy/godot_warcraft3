extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	var game: Node = load("res://game/scenes/game_main.tscn").instantiate()
	var director := game.get_node("GameDirector") as GameDirector
	director.dev_spawn_archmage = false
	director.dev_spawn_priest = false
	director.random_start_location = false
	add_child(game)
	var deadline := Time.get_ticks_msec() + 120000
	while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(director.is_session_ready(), "match ready")
	if not director.is_session_ready():
		get_tree().quit(1)
		return
	director.rebind_modules()
	var counts := director.module_binding_counts()
	for i in range(100):
		director._ensure_match_input()
		director._ensure_units_module()
		director._ensure_abilities_module()
		director._ensure_combat_module()
		director._ensure_harvest_module()
		director._ensure_build_module()
		director._ensure_production_module()
		director._ensure_items_module()
	check(director.module_binding_counts() == counts, "hot getters do not rebuild dependencies")
	check(director._command_input._tree_registry == director._tree_registry, "commands bind current tree registry")
	var query := director._path_query
	var reservation := director._cell_reservation
	var units := director._units
	var tree_registry := director._tree_registry
	var old_selector := director.unit_selector
	var replacement := SelectorStub.new()
	game.add_child(replacement)
	director._interaction.begin_aim(InteractionModule.Aim.MOVE)
	director.unit_selector = replacement
	director.rebind_modules()
	var rebound := director.module_binding_counts()
	for key in counts:
		check(int(rebound[key]) == int(counts[key]) + 1, "explicit rebind once: " + str(key))
	check(director._match_input.unit_selector == replacement and director._feedback.unit_selector == replacement, "input and feedback use replacement selector")
	check(director._command_input._unit_selector == replacement and director._command_card._unit_selector == replacement, "command modules use replacement selector")
	check(not old_selector.is_connected("selection_changed", director._on_selection_changed), "old selector disconnected")
	check(replacement.is_connected("selection_changed", director._on_selection_changed), "new selector connected")
	check(director._interaction.is_move() and not replacement.enabled, "rebind preserves aim and selector exclusion")
	check(director._path_query == query and director._cell_reservation == reservation and director._units == units and director._tree_registry == tree_registry, "rebind preserves runtime services")
	check(director.game_hud.item_use.get_connections().size() == 1, "HUD rebind does not duplicate item signal")
	director._interaction.cancel_aim()
	game.queue_free()
	await get_tree().process_frame
	print("selftest_module_bindings_game: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
class SelectorStub extends Node:
	signal selection_changed(primary: Node3D, selected: Array)
	var enabled := true
	var owner_filter := -1
	var marquee_owner := 0
	var pick_extra := Callable()
	func setup(_camera: Camera3D, _layer: Node, _unused: Variant) -> void:
		pass
	func get_primary() -> Node3D:
		return null
	func get_selected() -> Array:
		return []
