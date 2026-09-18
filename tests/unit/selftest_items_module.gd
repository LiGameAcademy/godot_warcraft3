extends Node

## ItemsModule 契约：装配 ItemService、use/drop 无主控不崩、shutdown。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ITEMS MODULE: " + label)


func _ready() -> void:
	var module := ItemsModule.new()
	add_child(module)
	var ground_parent := Node3D.new()
	ground_parent.name = "World"
	add_child(ground_parent)

	module.configure({
		"ground_parent": ground_parent,
		"map_dir": "",
		"set_status": Callable(),
		"get_primary": func() -> Node3D: return null,
		"is_controllable": func(_u: Node3D) -> bool: return false,
		"on_inventory_ui_refresh": Callable(),
		"get_model_cache": Callable(),
	})
	check(module.item_service != null, "configure 创建 ItemService")
	check(module.ground_host() != null, "configure 创建 GroundItems host")
	check(module.ground_host().get_parent() == ground_parent, "GroundItems 挂在注入 parent 下")

	module.use_slot(0)
	module.drop_slot(0)
	module.swap_slots(0, 1)
	check(true, "无主控时 use/drop/swap 不崩")

	module.shutdown()
	check(module.item_service == null, "shutdown 清空 item_service")
	module.free()

	print("selftest_items_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
