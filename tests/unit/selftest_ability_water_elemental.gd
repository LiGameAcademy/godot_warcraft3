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
	if not is_equal_approx(ab.cast_range_at(1), 200.0):
		_fail("AHwe 施法距离应为 200（Area1），实际 %s" % ab.cast_range_at(1))
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
	if AbilityCatalog.level_for_unit_type("Hamg", "AHwe", 1) <= 0:
		_fail("1 级 Hamg 应能学 AHwe")
		return
	print("  catalog OK")


func _test_cast_rules() -> void:
	var caster := Node3D.new()
	caster.name = "TestHamg"
	caster.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	caster.set_meta(AbilityCatalog.META_HERO_LEVEL, 1)
	UnitMana.ensure(caster)
	if UnitMana.get_max_mana(caster) <= 0:
		_fail("Hamg 应有魔法上限（mana0）")
		caster.free()
		return
	# 距离过远
	var far := AbilityCastRules.can_cast_point(caster, "AHwe", Vector2(99999.0, 99999.0), 1)
	if bool(far.get("ok", true)):
		_fail("超距施法应失败")
		caster.free()
		return
	# 魔法不足
	UnitMana.spend(caster, float(UnitMana.get_mana(caster)))
	var no_mana := AbilityCastRules.can_cast_point(caster, "AHwe", Vector2.ZERO, 1)
	if bool(no_mana.get("ok", true)):
		_fail("无蓝施法应失败")
		caster.free()
		return
	caster.free()
	print("  cast_rules OK")
