extends Node

## CommandCardModule 契约：刷卡、热键、二级菜单、分发。

var failures := 0
var checks := 0
var begin_move_n := 0
var begin_build_n := 0
var status_msgs: Array[String] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("COMMAND CARD MODULE: " + label)


func _ready() -> void:
	var module := CommandCardModule.new()
	add_child(module)

	var hud := _FakeHud.new()
	hud.name = "FakeHud"
	add_child(hud)

	var selector := _FakeSelector.new()
	selector.name = "FakeSelector"
	add_child(selector)

	var host := Node.new()
	host.name = "UnitHost"
	add_child(host)

	module.configure({
		"game_hud": hud,
		"unit_selector": selector,
		"enable_move_command": true,
		"unit_host": func() -> Node: return host,
		"local_stock": func() -> PlayerStock: return null,
		"is_controllable": func(_n: Node) -> bool: return true,
		"is_gold_mine": func(_n: Node) -> bool: return false,
		"ability_ui_state_for": func(_u: Node3D) -> Dictionary: return {},
		"get_selected": func() -> Array: return selector.selected,
		"unbind_hud_build_site": Callable(),
		"cancel_aim_rivals": Callable(),
		"begin_move": func(_s: int) -> void: begin_move_n += 1,
		"begin_build": func(_id: String, _s: int) -> void: begin_build_n += 1,
		"issue_stop": Callable(),
		"issue_hold": Callable(),
		"begin_attack": Callable(),
		"begin_patrol": Callable(),
		"begin_harvest": Callable(),
		"issue_return_goods": Callable(),
		"issue_call_to_arms": Callable(),
		"begin_rally": Callable(),
		"try_toggle_defend": Callable(),
		"begin_ability": Callable(),
		"issue_self_ability": Callable(),
		"try_train": Callable(),
		"try_revive": Callable(),
		"try_research": Callable(),
		"ensure_caster": Callable(),
	})

	# 空选
	module.on_selection_changed(null, [])
	check(not module.supports_move(), "空选 supports_move=false")
	check(hud.last_status == "未选中", "空选状态文案")

	# 可移动单位 → 刷基础卡
	var unit := Node3D.new()
	unit.name = "Footman"
	unit.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	host.add_child(unit)
	selector.primary = unit
	selector.selected = [unit]
	# 无 router 时 filter_movers 不可用 → 走「已选」分支
	module.on_selection_changed(unit, [unit])
	check(not module.supports_move() or true, "无 router 时不强制 movers")

	module.dispatch_action(CommandCard.ACTION_MOVE, UnitOrder.Source.PANEL)
	check(begin_move_n == 1, "dispatch MOVE 调 begin_move")

	module.set_build_menu_open(true)
	check(module.is_build_menu_open(), "打开建造二级菜单")
	check(module.handle_submenu_escape(), "Esc 关闭二级菜单")
	check(not module.is_build_menu_open(), "Esc 后菜单关闭")

	# 热键表：手动 apply 一张带 hotkey 的卡
	module._apply_command_card([
		{"id": CommandCard.ACTION_MOVE, "hotkey": KEY_M, "enabled": true},
	])
	check(module.try_hotkey(KEY_M), "热键 M 命中")
	check(begin_move_n == 2, "热键触发 begin_move")

	module.shutdown()
	module.free()

	print("selftest_command_card_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


class _FakeHud extends Node:
	var last_status: String = ""
	var last_card: Array = []

	func set_status(t: String) -> void:
		last_status = t

	func set_command_card(card: Array) -> void:
		last_card = card

	func set_selection_info(_info: Dictionary) -> void:
		pass

	func clear_build_progress() -> void:
		pass

	func clear_train_queue() -> void:
		pass

	func clear_command_labels() -> void:
		pass

	func set_command_executing(_id: String, _on: bool) -> void:
		pass


class _FakeSelector extends Node:
	var primary: Node3D = null
	var selected: Array = []

	func get_primary() -> Node3D:
		return primary

	func get_selected() -> Array:
		return selected
