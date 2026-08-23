extends SceneTree

## Phase C：BuffHost 施加 / 查询 / tick / 驱散。
## godot --headless --path . -s res://tests/unit/selftest_buff_system.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_stun_slow()
	_test_inner_fire()
	_test_dispel()
	_test_unit_status_facade()
	_test_hud_entries()
	if failed == 0:
		print("selftest_buff_system: PASS")
		quit(0)
	else:
		push_error("selftest_buff_system: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_stun_slow() -> void:
	var unit := Node3D.new()
	root.add_child(unit)
	UnitStatusEffects.apply_stun(unit, 2.0)
	if not UnitStatusEffects.is_stunned(unit):
		_fail("stun 应生效")
		unit.queue_free()
		return
	UnitStatusEffects.apply_slow(unit, 3.0, 0.6)
	UnitStatusEffects.apply_attack_slow(unit, 3.0, 0.25)
	if not is_equal_approx(UnitStatusEffects.attack_speed_mul(unit), 0.25):
		_fail("attack_slow mul")
		unit.queue_free()
		return
	unit.queue_free()
	print("  stun_slow OK")


func _test_inner_fire() -> void:
	var unit := Node3D.new()
	root.add_child(unit)
	UnitStatusEffects.set_inner_fire(unit, 5.0, 1.1)
	if not is_equal_approx(UnitStatusEffects.bonus_armor(unit), 5.0):
		_fail("inner fire armor")
		unit.queue_free()
		return
	if not is_equal_approx(UnitStatusEffects.damage_mul(unit), 1.1):
		_fail("inner fire dmg")
		unit.queue_free()
		return
	UnitStatusEffects.clear_inner_fire(unit)
	if UnitStatusEffects.bonus_armor(unit) > 0.0:
		_fail("clear inner fire")
		unit.queue_free()
		return
	unit.queue_free()
	print("  inner_fire OK")


func _test_dispel() -> void:
	var unit := Node3D.new()
	root.add_child(unit)
	var h := BuffHost.ensure_on(unit)
	UnitStatusEffects.apply_slow(unit, 10.0, 0.5)
	UnitStatusEffects.apply_stun(unit, 10.0)
	var n := h.dispel_magic()
	if n != 1:
		_fail("dispel 应移除 slow 保留 stun，实际移除 %d" % n)
		unit.queue_free()
		return
	if not UnitStatusEffects.is_stunned(unit):
		_fail("stun 不可驱散")
		unit.queue_free()
		return
	if UnitStatusEffects.is_slowed(unit):
		_fail("slow 应被驱散")
		unit.queue_free()
		return
	unit.queue_free()
	print("  dispel OK")


func _test_unit_status_facade() -> void:
	var unit := Node3D.new()
	root.add_child(unit)
	UnitStatusEffects.set_bonus_armor(unit, 3.0)
	if not is_equal_approx(UnitStatusEffects.bonus_armor(unit), 3.0):
		_fail("bonus_armor facade")
		unit.queue_free()
		return
	UnitStatusEffects.tick(unit, 0.0)
	unit.queue_free()
	print("  facade OK")


func _test_hud_entries() -> void:
	var unit := Node3D.new()
	root.add_child(unit)
	var bh := BuffHost.ensure_on(unit)
	bh.apply(BuffCatalog.ID_INNER_FIRE, 10.0, {"armor": 5.0, "dmg_mul": 1.1})
	var entries := BuffQuery.hud_entries(unit)
	if entries.size() != 1:
		_fail("hud_entries 应有 1 条")
		unit.queue_free()
		return
	var e := entries[0] as Dictionary
	if str(e.get("id", "")) != BuffCatalog.ID_INNER_FIRE:
		_fail("hud_entries id")
		unit.queue_free()
		return
	if str(e.get("tooltip", "")).find("心灵之火") < 0:
		_fail("hud_entries tooltip 标题")
		unit.queue_free()
		return
	if float(e.get("left", 0.0)) <= 0.0:
		_fail("hud_entries left")
		unit.queue_free()
		return
	var icon := str(e.get("icon", ""))
	if icon.find("InnerFireOn") >= 0 or icon.find("InnerFireOff") >= 0:
		_fail("buff 图标不应使用 On/Off 角标图: %s" % icon)
		unit.queue_free()
		return
	if icon.find("InnerFire") < 0:
		_fail("buff 图标应指向 BTNInnerFire: %s" % icon)
		unit.queue_free()
		return
	unit.queue_free()
	print("  hud_entries OK")
