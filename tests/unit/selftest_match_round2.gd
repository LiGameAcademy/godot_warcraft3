extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	var r := PathCellReservation.new()
	var a := Vector2i(-2, 4)
	var b := Vector2i(3, 1)
	r.set_owner_cells(1, [a, a, b])
	r.set_owner_cells(2, [a])
	check(r.is_blocked_for(a.x, a.y, 2), "cannot steal reservation")
	r.set_owner_cells(1, [b])
	r.set_owner_cells(2, [a])
	check(r.is_blocked_for(a.x, a.y, 1), "unchanged request retries released cell")
	r.clear_owner(1)
	check(not r.is_blocked_for(b.x, b.y, 2), "clear only own cells")
	check(r.is_blocked_for(a.x, a.y, 1), "other owner survives clear")
	r.clear()
	check(not r.is_blocked_for(a.x, a.y, 1), "clear resets both indexes")
	var reference := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for step in range(1000):
		var owner := rng.randi_range(1, 12)
		for cell in reference.keys():
			if reference[cell] == owner:
				reference.erase(cell)
		var requested: Array = []
		for j in range(3):
			requested.append(Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3)))
		for cell in requested:
			if not reference.has(cell):
				reference[cell] = owner
		r.set_owner_cells(owner, requested)
		check(r._cells == reference, "reservation reference equivalence %d" % step)
	var corridor := Wc3PathingMap.new()
	corridor.width = 9
	corridor.height = 3
	corridor.cells.resize(27)
	corridor.cells.fill(Wc3PathingMap.FLAG_NO_WALK)
	for x in range(9):
		corridor.cells[9 + x] = 0
	var corridor_res := PathCellReservation.new()
	var query := PathQuery.new()
	query.bind_pathing(corridor)
	query.bind_reservation(corridor_res)
	var start := corridor.cell_center_wc3(1, 1)
	var goal := corridor.cell_center_wc3(7, 1)
	corridor_res.set_owner_cells(41, [Vector2i(4, 1)])
	check(query.find_path(start, goal, 0, 41).ok, "corridor owner can traverse own reservation")
	check(not query.find_path(start, goal, 0, 42).ok, "corridor blocks another agent")
	corridor_res.clear_owner(41)
	check(query.find_path(start, goal, 0, 42).ok, "corridor opens after reservation release")
	var moving_body := Node3D.new()
	add_child(moving_body)
	var navigator := UnitNavigator.new()
	moving_body.add_child(navigator)
	navigator.configure(null, null, null, r)
	r.set_owner_cells(moving_body.get_instance_id(), [a])
	navigator.stop()
	check(not r.is_blocked_for(a.x, a.y, 999), "navigator stop releases reservation")
	r.set_owner_cells(moving_body.get_instance_id(), [a])
	var next_reservation := PathCellReservation.new()
	navigator.configure(null, null, null, next_reservation)
	check(not r.is_blocked_for(a.x, a.y, 999), "reservation replacement releases old ownership")
	next_reservation.set_owner_cells(moving_body.get_instance_id(), [a])
	moving_body.free()
	check(not next_reservation.is_blocked_for(a.x, a.y, 999), "unit removal releases reservation")
	var target_host := Node3D.new()
	add_child(target_host)
	var attacker := Node3D.new()
	attacker.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	attacker.set_meta("life", 100.0)
	target_host.add_child(attacker)
	for index in range(40):
		var candidate := Node3D.new()
		candidate.set_meta("unit_data", {"typeId": "hfoo" if index % 3 else "htow", "owner": index % 2})
		candidate.set_meta("life", 100.0 if index % 7 else 0.0)
		target_host.add_child(candidate)
		candidate.position = Wc3Coords.wc3_xy_to_godot(index * 32.0, 0, 0)
	for step in range(50):
		attacker.position = Wc3Coords.wc3_xy_to_godot(step * 17.0, 0, 0)
		check(CombatQuery.find_acquire_target(attacker, target_host, 192.0) == reference_acquire(attacker, target_host, 192.0), "acquire equals original including buildings and dead/allied units")
	# Exact tie rule: last equally near valid child wins.
	for candidate in target_host.get_children():
		if candidate != attacker:
			candidate.free()
	attacker.position = Vector3.ZERO
	var tied: Node3D
	for index in range(2):
		tied = Node3D.new()
		tied.set_meta("unit_data", {"typeId": "hfoo", "owner": 1})
		tied.set_meta("life", 100.0)
		target_host.add_child(tied)
		tied.position = Wc3Coords.wc3_xy_to_godot(100, 0, 0)
	check(CombatQuery.find_acquire_target(attacker, target_host, 100.0) == tied, "inclusive boundary and last-child tie")
	check(CombatQuery.find_acquire_target(attacker, target_host, 99.0) == null, "outside exact boundary")
	target_host.free()
	var draw := PathDebugDraw.new()
	add_child(draw)
	draw.setup(null)
	var paths := [{"points": [Vector2.ZERO, Vector2(128, 0)]}]
	draw.redraw(paths)
	var mesh := draw._line_mi.mesh
	var material := mesh.surface_get_material(0)
	draw.redraw(paths)
	check(draw._line_mi.mesh == mesh, "unchanged path retains mesh")
	paths[0].points[0] = Vector2(16, 0)
	draw.redraw(paths)
	check(draw._line_mi.mesh == mesh and mesh.surface_get_material(0) == material, "moving path reuses resources")
	draw.set_enabled(false)
	check(draw._line_mi.mesh == null, "disabled clears visual")
	draw.set_enabled(true)
	draw.redraw(paths)
	check(draw._line_mi.mesh == mesh, "re-enable rebuilds same resources")
	draw.redraw([])
	draw.redraw([])
	check(mesh.get_surface_count() == 0 and draw._line_mi.mesh == null, "empty clears once")
	draw.free()
	var loads := {"n": 0}
	var panel := CommandPanel.new()
	var grid := GridContainer.new()
	panel.add_child(grid)
	var button := Button.new()
	grid.add_child(button)
	panel.attach_command_grid(grid)
	panel.set_icon_loader(func(_path: String) -> Texture2D:
		loads["n"] = int(loads["n"]) + 1
		return GradientTexture2D.new()
	)
	var card := [{"id": "ability:test", "icon": "test-icon", "enabled": false, "cooldown_ratio": 0.5, "keep_icon_on_cd": true}]
	panel.set_command_card(card)
	var overlay := button.get_node("CooldownOverlay")
	var icon := button.icon
	card[0].cooldown_ratio = 0.25
	panel.update_command_card_dynamic(card)
	check(is_equal_approx(float(overlay.get("_ratio")), 0.25) and overlay.visible, "partial update advances cooldown wedge")
	check(int(loads["n"]) == 1 and button.icon == icon, "cooldown does not reload icon")
	check(button.get_node("CooldownOverlay") == overlay, "partial update retains overlay")
	card[0].cooldown_ratio = 0.0
	card[0].enabled = true
	panel.update_command_card_dynamic(card)
	check(is_zero_approx(float(overlay.get("_ratio"))) and not overlay.visible, "finished cooldown hides wedge")
	check(not button.get_meta("_cmd_blocked"), "cooldown completion enables command")
	card[0].enabled = false
	panel.update_command_card_dynamic(card)
	check(button.get_meta("_cmd_blocked"), "mana block applied")
	panel.free()
	var module := CountingCard.new()
	var selector := Selector.new()
	var fake_hud := FakeHud.new()
	var hero := Node3D.new()
	hero.set_meta("unit_data", {"typeId": "Hamg"})
	selector.primary = hero
	var state := {"ability_cd": {"AHbz": 5.0}, "ability_mana_ok_map": {"AHbz": true}}
	module.configure({"game_hud": fake_hud, "unit_selector": selector,
		"ability_ui_state_for": func(_unit: Node3D) -> Dictionary: return state.duplicate(true)})
	module._card_supports_move = true
	module.refresh_move_executing_ui()
	var initial := module.full
	for i in range(60):
		state.ability_cd.AHbz -= 0.01
		module.refresh_move_executing_ui()
	check(module.full == initial, "numeric cooldown never rebuilds card")
	state.ability_cd.clear()
	module.refresh_move_executing_ui()
	check(module.partial == 1, "cooldown end updates immediately")
	state.ability_mana_ok_map.AHbz = false
	module.refresh_move_executing_ui()
	check(module.partial == 2, "mana transition updates immediately")
	state.hero_level = 2
	module.refresh_move_executing_ui()
	check(module.full == initial + 1, "hero level rebuilds structure")
	hero.set_meta("unit_data", {"typeId": "hpri"})
	state.ability_mana_ok_map.AHbz = true
	module._last_harvest_ui.clear()
	module.refresh_move_executing_ui()
	check(module.partial == 3, "nonhero availability transition survives simultaneous movement refresh")
	module.free()
	selector.free()
	fake_hud.free()
	hero.free()
	var director := GameDirector.new()
	director.game_hud = GameHud.new()
	director.unit_selector = Node.new()
	var cc := director._ensure_command_card_module()
	var selected_hud := director._ensure_selection_hud_module()
	# A sentinel callable survives ensure only if dependencies are not reconfigured.
	cc._begin_move = func(_source: int) -> void: pass
	var sentinel := cc._begin_move
	director._ensure_command_card_module()
	check(cc._begin_move == sentinel, "ensure does not rebuild callbacks")
	director._session = GameSession.new()
	director._ensure_command_card_module()
	check(cc._session == director._session and cc._begin_move != sentinel, "session replacement rebinds")
	var old_selector := director.unit_selector
	director.unit_selector = Node.new()
	director._ensure_selection_hud_module()
	check(selected_hud._unit_selector == director.unit_selector, "selection dependency replacement rebinds")
	selected_hud.shutdown()
	director._ensure_selection_hud_module()
	check(selected_hud._game_hud == director.game_hud, "shutdown module can rebind")
	old_selector.free()
	director.unit_selector.free()
	director.game_hud.free()
	director.free()
	var compared := 0
	for tid in ["Hamg", "hpri"]:
		for remaining in [5.0, 2.5, 0.0]:
			for enough_mana in [true, false]:
				var ui := {"hero_level": 3, "ability_levels": {"AHbz": 1, "AHwe": 1},
					"ability_cd": {"AHbz": remaining, "Ahea": remaining},
					"ability_cd_total": {"AHbz": 6.0, "Ahea": 1.0}, "ability_mana_ok": enough_mana}
				var previous := CommandCard.for_unit(tid, ui)
				var changed := CommandCard.update_ability_entries(previous, tid, ui, {}, {})
				var expected := CommandCard.for_unit(tid, ui)
				for entry in changed:
					var action := str(entry.get("id", ""))
					if action.begins_with(CommandCard.ACTION_ABILITY_PREFIX):
						for full_entry in expected:
							if full_entry.get("id", "") == action:
								compared += 1
								check(entry == full_entry, "partial ability matches full card %s" % action)
	check(compared > 0, "ability comparison exercised visible skills")
	MatchHotpathMetrics.enabled = true
	for i in range(5000):
		MatchHotpathMetrics.finish(&"test", MatchHotpathMetrics.begin())
	check(MatchHotpathMetrics._windows[&"test"].samples.size() == MatchHotpathMetrics.CAPACITY, "metrics bounded")
	var stats := MatchHotpathMetrics.drain()
	check(stats[&"test"].calls == 5000 and MatchHotpathMetrics._windows.is_empty(), "metrics counts and resets")
	MatchHotpathMetrics.enabled = false
	print("selftest_match_round2: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

func reference_acquire(attacker: Node3D, host: Node, limit: float) -> Node3D:
	var best: Node3D
	var distance := limit
	for candidate in host.get_children():
		if not candidate is Node3D or not CombatQuery.is_auto_acquire_target(attacker, candidate):
			continue
		var d := CombatQuery.weapon_distance_wc3(attacker, candidate)
		if d <= distance:
			distance = d
			best = candidate
	return best


class CountingCard extends CommandCardModule:
	var full := 0
	var partial := 0
	func refresh() -> void:
		full += 1
	func _refresh_dynamic() -> void:
		partial += 1

class Selector extends Node:
	var primary: Node3D
	func get_primary() -> Node3D:
		return primary
	func get_selected() -> Array:
		return [primary]


class FakeHud extends Node:
	func set_command_executing(_action: String, _executing: bool) -> void:
		pass
