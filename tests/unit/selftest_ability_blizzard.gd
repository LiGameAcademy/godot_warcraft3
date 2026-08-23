extends SceneTree

## F10 暴风雪（AHbz）：SLK 数据、Catalog、区域查询。
## godot --headless --path . -s res://tests/unit/selftest_ability_blizzard.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ahbz_slk()
	_test_catalog()
	_test_hostile_radius()
	if failed == 0:
		print("selftest_ability_blizzard: PASS")
		quit(0)
	else:
		push_error("selftest_ability_blizzard: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _ahbz() -> AbilityDataDef:
	var store := root.get_node_or_null("Wc3DefStore")
	if store == null:
		return null
	store.ensure_table(AbilityDataDef.TABLE_NAME)
	return store.get_row(AbilityDataDef.TABLE_NAME, "AHbz") as AbilityDataDef


func _test_ahbz_slk() -> void:
	var ab := _ahbz()
	if ab == null:
		_fail("AHbz 行应能从 AbilityData 读到")
		return
	if not is_equal_approx(ab.cost1, 75.0):
		_fail("AHbz Cost1 应为 75，实际 %s" % ab.cost1)
		return
	if not is_equal_approx(ab.cool1, 6.0):
		_fail("AHbz Cool1 应为 6，实际 %s" % ab.cool1)
		return
	if not is_equal_approx(ab.data_a1, 6.0):
		_fail("AHbz DataA1（波数）应为 6，实际 %s" % ab.data_a1)
		return
	if not is_equal_approx(ab.data_b1, 30.0):
		_fail("AHbz DataB1（每波伤害）应为 30，实际 %s" % ab.data_b1)
		return
	if not is_equal_approx(ab.data_d1, 0.5):
		_fail("AHbz DataD1（间隔）应为 0.5，实际 %s" % ab.data_d1)
		return
	if not is_equal_approx(ab.cast_range_at(1), 800.0):
		_fail("AHbz 施法距离应为 800，实际 %s" % ab.cast_range_at(1))
		return
	if not is_equal_approx(ab.area_at(1), 200.0):
		_fail("AHbz Area1（半径）应为 200，实际 %s" % ab.area_at(1))
		return
	if not is_equal_approx(ab.cast_time_at(1), 1.0):
		_fail("AHbz Cast1 在 SLK 为 1（波次节奏字段）；引导时长用 DataA×DataD")
		return
	var waves := maxi(int(round(ab.data_a1)), 1)
	var interval := maxf(ab.data_d1, 0.05)
	var ch_dur := float(waves) * interval
	if not is_equal_approx(ch_dur, 3.0):
		_fail("AHbz 引导时长应为 3s（6×0.5），实际 %s" % ch_dur)
		return
	if not AbilityCastCatalog.is_channel_ability("AHbz"):
		_fail("AHbz 应标记为引导技能")
		return
	print("  ahbz_slk OK")


func _test_catalog() -> void:
	if AbilityCatalog.order_for("AHbz") != "blizzard":
		_fail("AHbz order 应为 blizzard，实际 %s" % AbilityCatalog.order_for("AHbz"))
		return
	if not AbilityCatalog.is_supported("AHbz"):
		_fail("AHbz 应在 SUPPORTED_ORDERS 中")
		return
	var ids := AbilityCatalog.ability_ids_for_unit("Hamg")
	var has_bz := false
	for id in ids:
		if str(id) == "AHbz":
			has_bz = true
			break
	if not has_bz:
		_fail("Hamg 应含英雄技能 AHbz")
		return
	print("  catalog OK")


func _test_hostile_radius() -> void:
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
	var victims := CombatQuery.units_blizzard_victims_in_radius(host, caster, center, 250.0)
	if victims.size() != 2:
		_fail("暴风雪半径内应命中友军+敌军，实际 %d" % victims.size())
		host.queue_free()
		return
	host.queue_free()
	print("  blizzard_victims OK")
