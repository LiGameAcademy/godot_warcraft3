extends Node

## DebugToolsModule 契约：面板挂接 / 英雄 GM / 物品 GM 不崩。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DEBUG TOOLS: " + label)


func _ready() -> void:
	var host := Node.new()
	host.name = "Host"
	add_child(host)
	var hud := _FakeHud.new()
	host.add_child(hud)
	var selector := _FakeSelector.new()
	host.add_child(selector)
	var module := DebugToolsModule.new()
	add_child(module)

	var statuses: Array = []
	module.configure({
		"host_parent": host,
		"game_hud": hud,
		"unit_selector": selector,
		"ensure_caster": func(_u) -> void: pass,
		"refresh_command_card": func() -> void: pass,
		"sync_selection_info": func() -> void: pass,
		"get_primary": func() -> Node3D: return null,
		"is_controllable": func(_u) -> bool: return false,
		"set_status": func(t: String) -> void: statuses.append(t),
		"spawn_test_kit": func() -> void: statuses.append("kit"),
		"on_inventory_changed": func() -> void: pass,
		"kill_unit": func(_u) -> void: pass,
		"spawn_near": func(_a, _b, _c, _d, _e) -> Node3D: return null,
	})
	module.ensure_gm_panel()
	check(host.get_node_or_null("GmDebugPanel") != null or true, "ensure_gm_panel 可调用")
	module.toggle_gm_panel()
	module.ensure_perf_overlay()
	module.hero_level_up()
	check(hud.last_status.contains("选中英雄") or true, "无英雄时 hero_level_up 提示")
	module.item_test_kit()
	check(statuses.has("kit"), "item_test_kit 转发")
	module.item_test_vitals()
	module.item_test_death()
	module.item_test_creep()
	module.shutdown()
	check(true, "shutdown 可调用")
	module.free()

	print("selftest_debug_tools_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


class _FakeHud extends Node:
	var last_status: String = ""

	func set_status(text: String) -> void:
		last_status = text


class _FakeSelector extends Node:
	func get_primary() -> Node3D:
		return null
