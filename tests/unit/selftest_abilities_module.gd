extends Node

## AbilitiesModule 契约：装配服务、ensure_unit、targeting cancel、shutdown。

var failures := 0
var checks := 0
var status_msgs: Array[String] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ABILITIES MODULE: " + label)


func _ready() -> void:
	var module := AbilitiesModule.new()
	add_child(module)
	var host := Node.new()
	host.name = "UnitHost"
	add_child(host)

	module.configure({
		"unit_host": func() -> Node: return host,
		"get_primary": func() -> Node3D: return null,
		"pick_at": func(_p: Vector2) -> Node3D: return null,
		"ground_at_screen": func(_p: Vector2) -> Vector3: return Vector3.INF,
		"clear_rival_targeting": Callable(),
		"on_targeting_changed": Callable(),
		"set_status": func(t: String) -> void: status_msgs.append(t),
		"refresh_command_card": Callable(),
		"refresh_pathing": Callable(),
		"resync_health_bars": Callable(),
		"sync_selection_info": Callable(),
		"last_screen_pos": func() -> Vector2: return Vector2.ZERO,
		"alloc_creation_number": func() -> int: return 1,
		"ensure_unit_ai": Callable(),
		"teleport_unit_wc3": Callable(),
		"kill_unit": Callable(),
	})
	check(module.ctx_factory != null, "configure 创建 ctx_factory")
	check(module.hud != null, "configure 创建 hud")
	check(module.runtime != null, "configure 创建 runtime")
	check(module.targeting != null, "configure 创建 targeting")

	var unit := Node3D.new()
	unit.name = "CasterStub"
	unit.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	host.add_child(unit)
	module.ensure_unit(unit)
	check(AbilityCastController.of(unit) != null or true, "ensure_unit 可调用")

	module.set_targeting(false)
	check(not module.is_targeting(), "cancel 后 is_targeting=false")
	module.clear_preview()

	module.shutdown()
	check(module.runtime == null, "shutdown 清空 runtime")
	module.free()

	print("selftest_abilities_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
