extends SceneTree

## F10 水元素（AHwe）：SLK 数据、Catalog、施法规则。
## godot --headless --path . -s res://tests/unit/selftest_ability_water_elemental.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ahwe_slk()
	_test_catalog()
	_test_cast_rules()
	if failed == 0:
		print("selftest_ability_water_elemental: PASS")
		quit(0)
	else:
		push_error("selftest_ability_water_elemental: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _ahwe() -> AbilityDataDef:
	var store := root.get_node_or_null("Wc3DefStore")
	if store == null:
		return null
	store.ensure_table(AbilityDataDef.TABLE_NAME)
	return store.get_row(AbilityDataDef.TABLE_NAME, "AHwe") as AbilityDataDef


func _test_ahwe_slk() -> void:
	var ab := _ahwe()
	if ab == null:
		_fail("AHwe 行应能从 AbilityData 读到")
		return
	if not is_equal_approx(ab.cost1, 125.0):
		_fail("AHwe Cost1 应为 125，实际 %s" % ab.cost1)
		return
	if not is_equal_approx(ab.cool1, 20.0):
		_fail("AHwe Cool1 应为 20，实际 %s" % ab.cool1)
		return
	if not is_equal_approx(ab.dur1, 60.0):
		_fail("AHwe Dur1 应为 60，实际 %s" % ab.dur1)
		return
	if ab.summon_unit_id_at(1) != "hwat":
		_fail("AHwe UnitID1 应为 hwat，实际 %s" % ab.summon_unit_id_at(1))
		return
	if not is_equal_approx(ab.area_at(1), 200.0):
		_fail("AHwe Area1 应为 200（面前召唤偏移），实际 %s" % ab.area_at(1))
		return
	if not is_equal_approx(ab.cast_time_at(1), 0.0):
		_fail("AHwe Cast1 应为 0（即时），实际 %s" % ab.cast_time_at(1))
		return
	print("  ahwe_slk OK")


func _test_catalog() -> void:
	if AbilityCatalog.order_for("AHwe") != "waterelemental":
		_fail("AHwe order 应为 waterelemental，实际 %s" % AbilityCatalog.order_for("AHwe"))
		return
	if not AbilityCatalog.is_supported("AHwe"):
		_fail("AHwe 应在 SUPPORTED_ORDERS 中")
		return
	var ids := AbilityCatalog.ability_ids_for_unit("Hamg")
	var has_we := false
	for id in ids:
		if str(id) == "AHwe":
			has_we = true
			break
	if not has_we:
		_fail("Hamg 应含英雄技能 AHwe")
		return
	if AbilityCatalog.level_for_unit_type("Hamg", "AHwe", 1, {}) != 0:
		_fail("1 级 Hamg 未学 AHwe 时应为 0")
		return
	print("  catalog OK")


func _learn(caster: Node3D, abil_id: String) -> void:
	caster.set_meta(AbilityCatalog.META_HERO_LEVEL, 2)
	var m: Dictionary = {abil_id: 1}
	caster.set_meta(AbilityCatalog.META_ABILITY_LEVELS, m)


func _test_cast_rules() -> void:
	var caster := Node3D.new()
	caster.name = "TestHamg"
	caster.set_meta("unit_data", {"typeId": "Hamg", "owner": 0, "angle": 0.0})
	_learn(caster, "AHwe")
	UnitMana.ensure(caster)
	UnitMana.sync_hero_max(caster)
	if UnitMana.get_max_mana(caster) < 125:
		_fail("Hamg 魔法上限应 ≥125，实际 %d" % UnitMana.get_max_mana(caster))
		caster.free()
		return
	if AbilityCatalog.target_kind("AHwe") != AbilityCatalog.TARGET_SELF:
		_fail("AHwe 应为非指向即时召唤")
		caster.free()
		return
	var ok := AbilityCastRules.can_cast_self(caster, "AHwe", 1)
	if not bool(ok.get("ok", false)):
		_fail("满蓝应能施放水元素：%s" % ok.get("reason", ""))
		caster.free()
		return
	var goal := SummonUnitAbility.summon_goal_in_front(caster, "AHwe", 1)
	var caster_xy := Wc3Coords.godot_to_wc3_xy(caster.global_position)
	if caster_xy.distance_to(goal) < 50.0 or caster_xy.distance_to(goal) > 250.0:
		_fail("召唤落点应在面前 ~200，实际距离 %s" % caster_xy.distance_to(goal))
		caster.free()
		return
	UnitMana.spend(caster, float(UnitMana.get_mana(caster)))
	var no_mana := AbilityCastRules.can_cast_self(caster, "AHwe", 1)
	if bool(no_mana.get("ok", true)):
		_fail("无蓝施法应失败")
		caster.free()
		return
	caster.free()
	print("  cast_rules OK")
