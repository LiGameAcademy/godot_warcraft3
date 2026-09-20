extends Node

## SelectionHudModule 契约：肖像配置、选中详情、buff tick。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SELECTION HUD MODULE: " + label)


func _ready() -> void:
	var module := SelectionHudModule.new()
	add_child(module)

	var hud := _FakeHud.new()
	add_child(hud)
	var selector := _FakeSelector.new()
	add_child(selector)
	var map_root := Node.new()
	map_root.name = "MapRoot"
	add_child(map_root)

	var sync_n := {"n": 0}
	module.configure({
		"game_hud": hud,
		"unit_selector": selector,
		"map_root": map_root,
		"sync_build_hud": func() -> void: sync_n["n"] = int(sync_n["n"]) + 1,
		"is_controllable": func(_n: Node) -> bool: return true,
	})

	module.setup_portrait()
	check(hud.portrait_configured, "setup_portrait 调 configure_portrait")

	var unit := Node3D.new()
	unit.name = "Stub"
	unit.set_meta("unit_data", {"typeId": "hfoo"})
	add_child(unit)
	UnitLife.ensure(unit)
	UnitLife.set_ratio(unit, 1.0)
	selector.primary = unit
	selector.selected = [unit]

	module.apply_selection_info(unit, [unit])
	check(hud.selection_info_set, "apply_selection_info")

	module.tick(0.016)
	check(hud.vitals_updated, "tick 刷 portrait vitals")
	check(hud.buff_updated, "tick 刷 buff strip")

	module.sync_panel()
	check(int(sync_n["n"]) == 1, "sync_panel 触发 sync_build_hud")

	module.bind_inventory_for(unit)
	check(hud.inventory_bound, "bind_inventory_for")

	module.shutdown()
	module.free()

	print("selftest_selection_hud_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


class _FakeHud extends Node:
	var portrait_configured := false
	var selection_info_set := false
	var vitals_updated := false
	var buff_updated := false
	var inventory_bound := false

	func configure_portrait(_cache, _catalog) -> void:
		portrait_configured = true

	func set_selection_info(_info: Dictionary) -> void:
		selection_info_set = true

	func update_portrait_vitals(_hp: int, _hp_max: int, _mana: int, _mana_max: int) -> void:
		vitals_updated = true

	func update_portrait_timed_life(_left: float, _total: float) -> void:
		pass

	func update_buff_strip(_entries: Array) -> void:
		buff_updated = true

	func update_combat_stat_chips(_atk: Dictionary, _armor: Dictionary) -> void:
		pass

	func bind_inventory(_inv) -> void:
		inventory_bound = true


class _FakeSelector extends Node:
	var primary: Node3D = null
	var selected: Array = []

	func get_primary() -> Node3D:
		return primary

	func get_selected() -> Array:
		return selected
