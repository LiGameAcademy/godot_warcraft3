extends Node

## SmartCommandModule 契约：无选中时解析地面/空；format 不崩。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SMART COMMAND: " + label)


func _ready() -> void:
	var module := SmartCommandModule.new()
	add_child(module)
	module.configure({
		"ground_at_screen": func(_p: Vector2) -> Vector3: return Vector3.INF,
		"is_gold_mine": func(_n) -> bool: return false,
	})
	var t := module.resolve_smart_target(Vector2(10, 10), [])
	check(t == null, "无地面命中时 resolve 返回 null")
	var status := module.format_smart_status({
		"kind": "Item",
		"moved": 1,
		"goal_wc3": Vector2(1, 2),
	})
	check(status.contains("拾取"), "Item 状态文案")
	status = module.format_smart_status({
		"kind": "GoldMine",
		"harvested": 2,
		"moved": 0,
	})
	check(status.contains("采集金币"), "GoldMine 状态文案")
	check(module.selection_any_carrying([]) == false, "空选中无负重")
	module.flash_smart_interact_target(null)
	module.shutdown()
	check(true, "shutdown 可调用")
	module.free()

	print("selftest_smart_command_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
