extends Node

## InteractionModule 契约：互斥瞄准、光标模式、flash 不被 IDLE 掐死、重入安全。

var failures := 0
var checks := 0
var ability_cancelled := 0
var build_cancelled := 0
var ability_targeting := false
var build_targeting := false


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("INTERACTION MODULE: " + label)


func _ready() -> void:
	var module := InteractionModule.new()
	add_child(module)

	var cursor := Wc3GameCursor.new()
	cursor.enabled = false
	cursor.name = "StubCursor"
	add_child(cursor)

	var fake_sel := _FakeSelector.new()
	fake_sel.name = "StubSelector"
	add_child(fake_sel)

	module.configure({
		"cursor": cursor,
		"unit_selector": fake_sel,
		"cancel_ability": func() -> void:
			ability_cancelled += 1
			ability_targeting = false,
		"cancel_build": func() -> void:
			build_cancelled += 1
			build_targeting = false,
		"ability_target_kind": func() -> int: return AbilityCatalog.TARGET_ALLY,
		"is_ability_targeting": func() -> bool: return ability_targeting,
		"is_build_targeting": func() -> bool: return build_targeting,
	})

	module.begin_aim(InteractionModule.Aim.MOVE)
	check(module.is_move(), "begin_aim MOVE")
	check(not fake_sel.enabled, "瞄准时 selector.enabled=false")

	module.begin_aim(InteractionModule.Aim.ATTACK)
	check(module.is_attack(), "MOVE→ATTACK 互斥切换")
	check(not module.is_move(), "旧 MOVE 已退出")

	ability_targeting = true
	module.adopt_external_aim(InteractionModule.Aim.ABILITY, {"abil_id": "AHhb", "target_kind": AbilityCatalog.TARGET_ALLY})
	check(module.is_ability(), "adopt ABILITY")

	ability_cancelled = 0
	build_targeting = true
	module.begin_aim(InteractionModule.Aim.BUILD, {"building_id": "hhou"})
	check(module.is_build(), "begin BUILD")
	check(ability_cancelled == 1, "BUILD 取消 ability")

	module.begin_aim(InteractionModule.Aim.MOVE)
	module.flash_move_confirm()
	check(module.current_aim() == InteractionModule.Aim.NONE, "flash 后 aim=NONE")
	check(fake_sel.enabled, "flash 后 selector 恢复")

	build_targeting = true
	module.begin_aim(InteractionModule.Aim.BUILD)
	build_cancelled = 0
	module.on_selection_changed(null, [])
	check(module.current_aim() == InteractionModule.Aim.NONE, "selection 清瞄准")
	check(build_cancelled == 1, "selection 取消 build")

	build_targeting = false
	module.begin_aim(InteractionModule.Aim.BUILD)
	build_cancelled = 0
	module.acknowledge_external_end()
	check(module.current_aim() == InteractionModule.Aim.NONE, "acknowledge 清状态")
	check(build_cancelled == 0, "acknowledge 不回调 cancel_build")

	var reenter := InteractionModule.new()
	add_child(reenter)
	var boom := {"n": 0}
	reenter.configure({
		"cursor": cursor,
		"unit_selector": fake_sel,
		"cancel_ability": func() -> void:
			boom["n"] = int(boom["n"]) + 1
			reenter.cancel_aim("reenter"),
		"is_ability_targeting": func() -> bool: return false,
		"is_build_targeting": func() -> bool: return false,
		"ability_target_kind": func() -> int: return 0,
	})
	reenter.begin_aim(InteractionModule.Aim.ABILITY)
	reenter.cancel_aim("outer")
	check(reenter.current_aim() == InteractionModule.Aim.NONE, "重入 cancel 安全")
	check(int(boom["n"]) == 1, "cancel_ability 只调一次")

	module.shutdown()
	check(module.current_aim() == InteractionModule.Aim.NONE, "shutdown 清 aim")
	module.free()
	reenter.free()

	print("selftest_interaction_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


class _FakeSelector extends Node:
	var enabled: bool = true
