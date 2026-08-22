extends SceneTree

## F10 辉煌光环（AHab）：SLK 数据、被动 Catalog、友军半径、回蓝。
## godot --headless --path . -s res://tests/unit/selftest_ability_brilliance.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ahab_slk()
	_test_catalog()
	_test_friendly_radius()
	_test_regenerate()
	if failed == 0:
		print("selftest_ability_brilliance: PASS")
		quit(0)
	else:
		push_error("selftest_ability_brilliance: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _ahab() -> AbilityDataDef:
	var store := root.get_node_or_null("Wc3DefStore")
	if store == null:
		return null
	store.ensure_table(AbilityDataDef.TABLE_NAME)
	return store.get_row(AbilityDataDef.TABLE_NAME, "AHab") as AbilityDataDef


func _test_ahab_slk() -> void:
	var ab := _ahab()
	if ab == null:
		_fail("AHab 行应能从 AbilityData 读到")
		return
	if not is_equal_approx(ab.data_a1, 0.75):
		_fail("AHab DataA1（回蓝/秒）应为 0.75，实际 %s" % ab.data_a1)
		return
	if not is_equal_approx(ab.data_a2, 1.5):
		_fail("AHab DataA2 应为 1.5，实际 %s" % ab.data_a2)
		return
	if not is_equal_approx(ab.data_a3, 2.25):
		_fail("AHab DataA3 应为 2.25，实际 %s" % ab.data_a3)
		return
	if not is_equal_approx(ab.area_at(1), 900.0):
		_fail("AHab Area1（半径）应为 900，实际 %s" % ab.area_at(1))
		return
	if not is_equal_approx(ab.cost_at(1), 0.0):
		_fail("AHab 被动无魔法消耗，Cost1 应为 0，实际 %s" % ab.cost_at(1))
		return
	if not is_equal_approx(ab.cool_at(1), 0.0):
		_fail("AHab 被动无 CD，Cool1 应为 0，实际 %s" % ab.cool_at(1))
		return
	print("  ahab_slk OK")


func _test_catalog() -> void:
	if not AbilityCatalog.is_passive_aura("AHab"):
		_fail("AHab 应标记为被动光环")
		return
	if AbilityCatalog.is_supported("AHab"):
		_fail("AHab 不应在 SUPPORTED_ORDERS（无 order）")
		return
	var ids := AbilityCatalog.ability_ids_for_unit("Hamg")
	var has_ab := false
	for id in ids:
		if str(id) == "AHab":
			has_ab = true
			break
	if not has_ab:
		_fail("Hamg 应含英雄技能 AHab")
		return
	if AbilityCatalog.level_for_unit_type("Hamg", "AHab", 1) <= 0:
		_fail("1 级 Hamg 应能学 AHab")
		return
	print("  catalog OK")


func _test_friendly_radius() -> void:
	var host := Node.new()
	host.name = "UnitHost"
	root.add_child(host)
	var caster := Node3D.new()
	caster.name = "Hamg"
	caster.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	host.add_child(caster)
	var ally := Node3D.new()
	ally.name = "Ally"
	ally.set_meta("unit_data", {"typeId": "hpea", "owner": 0})
	ally.set_meta("life", 100.0)
	host.add_child(ally)
	var foe := Node3D.new()
	foe.name = "Foe"
	foe.set_meta("unit_data", {"typeId": "hfoo", "owner": 1})
	foe.set_meta("life", 100.0)
	host.add_child(foe)
	var center := Vector2.ZERO
	var hits := CombatQuery.units_friendly_in_radius(host, caster, center, 900.0)
	if hits.size() != 2:
		_fail("900 半径内应命中 2 个友方（含自身），实际 %d" % hits.size())
		host.queue_free()
		return
	host.queue_free()
	print("  friendly_radius OK")


func _test_regenerate() -> void:
	var unit := Node3D.new()
	unit.name = "Hamg"
	unit.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	root.add_child(unit)
	UnitMana.ensure(unit)
	var before := UnitMana.get_mana(unit)
	# 0.75/s → 1.5s 应 +1 蓝（小数累积）
	UnitMana.regenerate(unit, 0.75)
	UnitMana.regenerate(unit, 0.75)
	if UnitMana.get_mana(unit) != before + 1:
		_fail("累积 1.5 蓝应 +1，实际 %d→%d" % [before, UnitMana.get_mana(unit)])
		unit.queue_free()
		return
	unit.queue_free()
	print("  regenerate OK")
