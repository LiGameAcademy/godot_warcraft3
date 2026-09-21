extends Node

## CommandInputModule 契约：无依赖时安全返回；瞄准查询；shutdown。

var failures := 0
var checks := 0
var status_text := ""


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("COMMAND INPUT: " + label)


func _ready() -> void:
	var hud_node := _HudNode.new()
	hud_node.owner_test = self
	hud_node.name = "StubHud"
	add_child(hud_node)

	var module := CommandInputModule.new()
	add_child(module)
	module.configure({
		"game_hud": hud_node,
		"get_selected": func() -> Array: return [],
		"ground_at_screen": func(_p: Vector2) -> Vector3: return Vector3.INF,
	})

	check(module.is_basic_aiming() == false, "无 Interaction 时 is_basic_aiming=false")
	check(module.try_handle_aim_input(InputEventKey.new()) == false, "非鼠标不消费")
	check(module.issue_stop() == false, "无 router 时 issue_stop=false")
	check(module.issue_hold() == false, "无 router 时 issue_hold=false")
	check(module.issue_move_at_screen(Vector2.ZERO, UnitOrder.Source.PANEL) == false, "无 router 时 issue_move=false")
	check(module.issue_smart_at_screen(Vector2.ZERO, UnitOrder.Source.SMART_RMB) == false, "无 smart 时 issue_smart=false")
	module.begin_move_targeting(UnitOrder.Source.PANEL)
	check(status_text.contains("无可用单位"), "begin_move 无单位写状态")
	module.try_toggle_defend()
	module.apply_rally_from_smart(null, null)
	module.shutdown()
	check(true, "shutdown 可调用")
	module.free()

	print("selftest_command_input_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


class _HudNode extends Node:
	var owner_test: Node

	func set_status(text: String) -> void:
		if owner_test != null:
			owner_test.status_text = text
