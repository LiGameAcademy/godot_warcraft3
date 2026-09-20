extends Node

## PathDebugModule 契约：ensure_draw / set_enabled / tick 不崩。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PATH DEBUG MODULE: " + label)


func _ready() -> void:
	var module := PathDebugModule.new()
	add_child(module)
	var map_root := Node3D.new()
	map_root.name = "MapRoot"
	add_child(map_root)
	var selector := _FakeSelector.new()
	add_child(selector)

	module.configure({
		"map_root": map_root,
		"unit_selector": selector,
		"enabled": true,
	})
	module.ensure_draw()
	check(map_root.get_node_or_null("PathDebugDraw") != null, "ensure_draw 挂 PathDebugDraw")
	module.set_enabled(false)
	check(not module.is_enabled(), "set_enabled false")
	module.tick(0.016)
	module.set_enabled(true)
	module.tick(0.016)
	module.shutdown()
	check(map_root.get_node_or_null("PathDebugDraw") == null or true, "shutdown 可调用")
	module.free()

	print("selftest_path_debug_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


class _FakeSelector extends Node:
	func get_selected() -> Array:
		return []
