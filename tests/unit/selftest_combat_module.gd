extends Node

## CombatModule 契约：服务装配、AttackController、kill、shutdown。

var failures := 0
var checks := 0
var dying_seen := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("COMBAT MODULE: " + label)


func _ready() -> void:
	var module := CombatModule.new()
	add_child(module)

	var host := Node3D.new()
	host.name = "UnitHost"
	add_child(host)

	module.configure({
		"unit_host": func() -> Node: return host,
		"ensure_navigator": Callable(),
		"ensure_unit_visual": Callable(),
		"release_food": Callable(),
		"terminate_production": Callable(),
		"prepare_hero_death": Callable(),
		"deselect_unit": Callable(),
		"get_primary": Callable(),
		"get_selected": func() -> Array: return [],
		"apply_selection_info": Callable(),
		"refresh_command_card": Callable(),
	})
	check(module.damage_pipeline != null, "configure 创建 DamagePipeline")
	check(module.death_service != null, "configure 创建 DeathService")
	check(module.projectile_service != null, "configure 创建 ProjectileService")
	check(module.damage_pipeline.death == module.death_service, "pipeline.death 指向 DeathService")
	check(module.projectile_service.pipeline == module.damage_pipeline, "projectile.pipeline 指向 DamagePipeline")

	var unit := Node3D.new()
	unit.name = "FootmanStub"
	unit.set_meta("unit_data", {"typeId": "hfoo", "owner": 0, "creationNumber": 1})
	host.add_child(unit)
	UnitLife.ensure(unit)
	UnitLife.set_ratio(unit, 1.0)

	var ac := module.ensure_attack_controller(unit)
	check(ac != null, "ensure_attack_controller 返回实例")
	check(unit.get_node_or_null("AttackController") == ac, "AttackController 挂在单位下")
	var ac2 := module.ensure_attack_controller(unit)
	check(ac2 == ac, "重复 ensure 返回同一实例")

	module.death_service.on_before_exit = func(u: Node3D) -> void:
		dying_seen += 1
		check(u == unit, "on_before_exit 传入正确单位")
	module.kill(unit)
	check(dying_seen == 1, "kill 触发 on_before_exit")

	module.shutdown()
	check(module.damage_pipeline == null, "shutdown 清空 pipeline")
	check(module.death_service == null, "shutdown 清空 death_service")
	module.free()

	print("selftest_combat_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
