extends SceneTree

## F10 山丘之王（Hmkg）：AHtb/AHtc/AHbh/AHav 数据、Catalog、状态效果。
## godot --headless --path . -s res://tests/unit/selftest_ability_mountain_king.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_slk()
	_test_catalog()
	_test_status_effects()
	_test_avatar_controller()
	if failed == 0:
		print("selftest_ability_mountain_king: PASS")
		quit(0)
	else:
		push_error("selftest_ability_mountain_king: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _abil(id: String) -> AbilityDataDef:
	var store := root.get_node_or_null("Wc3DefStore")
	if store == null:
		return null
	store.ensure_table(AbilityDataDef.TABLE_NAME)
	return store.get_row(AbilityDataDef.TABLE_NAME, id) as AbilityDataDef


func _test_slk() -> void:
	var tb := _abil("AHtb")
	if tb == null:
		_fail("AHtb 行应能从 AbilityData 读到")
		return
	if not is_equal_approx(tb.data_a1, 100.0):
		_fail("AHtb DataA1 应为 100，实际 %s" % tb.data_a1)
		return
	if not is_equal_approx(tb.cast_range_at(1), 600.0):
		_fail("AHtb 射程应为 600，实际 %s" % tb.cast_range_at(1))
		return
	var tc := _abil("AHtc")
	if tc == null:
		_fail("AHtc 行应能从 AbilityData 读到")
		return
	if not is_equal_approx(tc.data_a1, 70.0):
		_fail("AHtc DataA1 应为 70，实际 %s" % tc.data_a1)
		return
	if not is_equal_approx(tc.area_at(1), 250.0):
		_fail("AHtc Area1 应为 250，实际 %s" % tc.area_at(1))
		return
	var bh := _abil("AHbh")
	if bh == null:
		_fail("AHbh 行应能从 AbilityData 读到")
		return
	if not is_equal_approx(bh.data_a1, 15.0):
		_fail("AHbh DataA1（概率%）应为 15，实际 %s" % bh.data_a1)
		return
	if not is_equal_approx(bh.data_c1, 25.0):
		_fail("AHbh DataC1（额外伤害）应为 25，实际 %s" % bh.data_c1)
		return
	var av := _abil("AHav")
	if av == null:
		_fail("AHav 行应能从 AbilityData 读到")
		return
	if av.req_level < 6:
		_fail("AHav reqLevel 应 >= 6，实际 %s" % av.req_level)
		return
	if not is_equal_approx(av.data_a1, 5.0):
		_fail("AHav DataA1（护甲）应为 5，实际 %s" % av.data_a1)
		return
	if not is_equal_approx(av.data_b1, 500.0):
		_fail("AHav DataB1（生命）应为 500，实际 %s" % av.data_b1)
		return
	print("  slk OK")


func _test_catalog() -> void:
	for id in ["AHtb", "AHtc", "AHav"]:
		if not AbilityCatalog.is_supported(id):
			_fail("%s 应在 SUPPORTED_ORDERS 中" % id)
			return
	if AbilityCatalog.is_supported("AHbh"):
		_fail("AHbh 被动不应在 SUPPORTED_ORDERS")
		return
	if not AbilityCatalog.is_passive_ability("AHbh"):
		_fail("AHbh 应标记为被动")
		return
	if AbilityCatalog.target_kind("AHtb") != AbilityCatalog.TARGET_UNIT:
		_fail("AHtb 应为 TARGET_UNIT")
		return
	if AbilityCatalog.target_kind("AHtc") != AbilityCatalog.TARGET_SELF:
		_fail("AHtc 应为 TARGET_SELF")
		return
	if AbilityCatalog.target_kind("AHav") != AbilityCatalog.TARGET_SELF:
		_fail("AHav 应为 TARGET_SELF")
		return
	var ids := AbilityCatalog.ability_ids_for_unit("Hmkg")
	var want := {"AHtc": false, "AHtb": false, "AHbh": false, "AHav": false}
	for id in ids:
		if want.has(str(id)):
			want[str(id)] = true
	for k in want.keys():
		if not bool(want[k]):
			_fail("Hmkg 应含技能 %s" % k)
			return
	if AbilityCatalog.level_for_unit_type("Hmkg", "AHav", 5, {}) > 0:
		_fail("5 级 Hmkg 未学 AHav 时不应可用")
		return
	if AbilityCatalog.level_for_unit_type("Hmkg", "AHav", 6, {}) > 0:
		_fail("6 级 Hmkg 未学 AHav 时不应可用")
		return
	if AbilityCatalog.level_for_unit_type("Hmkg", "AHav", 6, {"AHav": 1}) != 1:
		_fail("6 级已学 AHav 应为 rank 1")
		return
	print("  catalog OK")


func _test_status_effects() -> void:
	var unit := Node3D.new()
	unit.name = "Dummy"
	root.add_child(unit)
	var nav := UnitNavigator.new()
	nav.name = "UnitNavigator"
	unit.add_child(nav)
	UnitStatusEffects.apply_stun(unit, 2.0)
	if not UnitStatusEffects.is_stunned(unit):
		_fail("apply_stun 后 is_stunned 应为 true")
		return
	UnitStatusEffects.apply_slow(unit, 3.0, 0.5)
	if nav.speed_mul > 0.55:
		_fail("减速后 speed_mul 应 <= 0.55，实际 %s" % nav.speed_mul)
		return
	UnitStatusEffects.set_bonus_armor(unit, 5.0)
	if not is_equal_approx(UnitStatusEffects.bonus_armor(unit), 5.0):
		_fail("bonus_armor 应为 5")
		return
	unit.queue_free()
	print("  status_effects OK")


func _test_avatar_controller() -> void:
	var hero := Node3D.new()
	hero.name = "Hmkg"
	hero.set_meta("unit_data", {"typeId": "Hmkg", "owner": 0})
	hero.set_meta(AbilityCatalog.META_HERO_LEVEL, 6)
	hero.set_meta(AbilityCatalog.META_ABILITY_LEVELS, {"AHav": 1})
	root.add_child(hero)
	UnitLife.ensure(hero)
	UnitLife.set_life(hero, 500.0)
	hero.set_meta(UnitLife.META_MAX_LIFE, 500.0)
	var ctrl := AvatarController.ensure_on(hero)
	if ctrl == null:
		_fail("Hmkg 应能挂 AvatarController")
		return
	if not ctrl.activate(1):
		_fail("Avatar activate 应成功")
		return
	if not ctrl.is_active():
		_fail("activate 后 is_active 应为 true")
		return
	if not is_equal_approx(UnitLife.get_max_life(hero), 1000.0):
		_fail("天神 +500 生命后 max 应为 1000，实际 %s" % UnitLife.get_max_life(hero))
		return
	if not is_equal_approx(UnitStatusEffects.bonus_armor(hero), 5.0):
		_fail("天神 +5 护甲")
		return
	ctrl._process(999.0)
	if ctrl.is_active():
		_fail("超时后天神应结束")
		return
	if not is_equal_approx(UnitLife.get_max_life(hero), 500.0):
		_fail("天神结束后 max 应恢复 500")
		return
	hero.queue_free()
	print("  avatar_controller OK")
