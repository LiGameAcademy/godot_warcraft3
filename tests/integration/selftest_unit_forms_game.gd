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
	var game: Node = load("res://scenes/game_main.tscn").instantiate()
	var director := game.get_node("GameDirector") as GameDirector
	director.spawn_opponent_base = true
	director.enable_opponent_economy = false
	director.enable_opponent_army = false
	director.random_start_location = false
	add_child(game)
	var deadline := Time.get_ticks_msec() + 120000
	while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(director.is_session_ready(), "match ready")
	if not director.is_session_ready():
		get_tree().quit(1)
		return
	var units := director._ensure_units_module()
	for owner in [0, 1]:
		var worker := units.find_owned_unit_by_types(owner, PackedStringArray(["hpea"]))
		var hall := units.find_owned_unit_by_types(owner, PackedStringArray(["htow"]))
		check(worker != null and hall != null, "owner has worker and hall")
		if worker == null or hall == null:
			continue
		var original_id := worker.get_instance_id()
		var original_cn := int(worker.get_meta("unit_data", {}).get("creationNumber", -1))
		UnitLife.set_ratio(worker, 0.4)
		units.teleport_wc3(worker, Wc3Coords.godot_to_wc3_xy(hall.global_position) + Vector2(250, 0))
		var mc := units.forms.ensure_militia(worker)
		check(mc._find_town_hall.call() == hall, "militia hall belongs to worker owner")
		check(mc.toggle_call_to_arms() and CombatQuery.type_id_of(worker) == "hmil", "near hall arms immediately")
		check(worker.get_instance_id() == original_id and int(worker.get_meta("unit_data", {}).get("creationNumber", -1)) == original_cn, "form preserves entity identity")
		check(absf(UnitLife.ratio(worker) - 0.4) < 0.01, "form preserves life ratio")
		check(Unit.of(worker).model_node() != null, "replacement model bound")
		check(mc.toggle_call_to_arms() and CombatQuery.type_id_of(worker) == "hpea", "manual revert")
		check(mc.toggle_call_to_arms(), "arm before timeout")
		mc._process(mc.duration_sec() + 1.0)
		check(CombatQuery.type_id_of(worker) == "hpea", "timed revert")
		var stock: PlayerStock = director.get_session().stocks[owner]
		var food_before := stock.food_cap
		UnitLife.set_ratio(hall, 0.6)
		check(units.apply_building_upgrade(hall, "hkee"), "town hall upgrade")
		check(CombatQuery.type_id_of(hall) == "hkee" and absf(UnitLife.ratio(hall) - 0.6) < 0.01, "upgrade preserves life ratio")
		check(stock.food_cap == food_before + BuildingCatalog.get_food_made("hkee") - BuildingCatalog.get_food_made("htow"), "upgrade charges correct owner ledger")
		check(not units.apply_building_upgrade(hall, "hfoo"), "invalid upgrade rejected")
	game.queue_free()
	await get_tree().process_frame
	print("selftest_unit_forms_game: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
