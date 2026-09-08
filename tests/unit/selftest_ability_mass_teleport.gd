extends SceneTree

## F10 群体传送（AHmt）：SLK 数据、Catalog、友军筛选。
## godot --headless --path . -s res://tests/unit/selftest_ability_mass_teleport.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ahmt_slk()
	_test_catalog()
	_test_gather()
	if failed == 0:
		print("selftest_ability_mass_teleport: PASS")
		quit(0)
	else:
		push_error("selftest_ability_mass_teleport: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _ahmt() -> AbilityDataDef:
	var store := root.get_node_or_null("Wc3DefStore")
	if store == null:
		return null
	store.ensure_table(AbilityDataDef.TABLE_NAME)
	return store.get_row(AbilityDataDef.TABLE_NAME, "AHmt") as AbilityDataDef


func _test_ahmt_slk() -> void:
	var ab := _ahmt()
	if ab == null:
		_fail("AHmt 行应能从 AbilityData 读到")
		return
	if not is_equal_approx(ab.cost1, 100.0):
		_fail("AHmt Cost1 应为 100，实际 %s" % ab.cost1)
		return
	if not is_equal_approx(ab.cool1, 15.0):
		_fail("AHmt Cool1 应为 15，实际 %s" % ab.cool1)
		return
	if not is_equal_approx(ab.cast_time_at(1), 0.0):
		_fail("AHmt Cast1 应为 0（SLK），实际 %s" % ab.cast_time_at(1))
		return
	if not is_equal_approx(ab.data_b1, 3.0):
		_fail("AHmt DataB1 应为 3（玩法读条秒），实际 %s" % ab.data_b1)
		return
	# 与 AbilityCastCatalog.cast_time_sec 规则一致：Cast=0 时用 DataB
	var gameplay_cast := ab.cast_time_at(1)
	if gameplay_cast <= 0.01:
		gameplay_cast = ab.data_b_at(1)
	if not is_equal_approx(gameplay_cast, 3.0):
		_fail("AHmt 玩法读条应为 3s，实际 %s" % gameplay_cast)
		return
	if ab.req_level != 6:
		_fail("AHmt reqLevel 应为 6（大招），实际 %d" % ab.req_level)
		return
	if not is_equal_approx(ab.area_at(1), 700.0):
		_fail("AHmt Area1（选人半径）应为 700，实际 %s" % ab.area_at(1))
		return
	if not is_equal_approx(ab.cast_range_at(1), 99999.0):
		_fail("AHmt 施法距离应为 99999，实际 %s" % ab.cast_range_at(1))
		return
	if not is_equal_approx(ab.data_a1, 24.0):
		_fail("AHmt DataA1（最多单位）应为 24，实际 %s" % ab.data_a1)
		return
	print("  ahmt_slk OK")


func _test_catalog() -> void:
	if AbilityCatalog.order_for("AHmt") != "massteleport":
		_fail("AHmt order 应为 massteleport，实际 %s" % AbilityCatalog.order_for("AHmt"))
		return
	if not AbilityCatalog.is_supported("AHmt"):
		_fail("AHmt 应在 SUPPORTED_ORDERS 中")
		return
	if AbilityCatalog.level_for_unit_type("Hamg", "AHmt", 5) > 0:
		_fail("5 级 Hamg 不应学 AHmt")
		return
	if AbilityCatalog.level_for_unit_type("Hamg", "AHmt", 6) <= 0:
		_fail("6 级 Hamg 应能学 AHmt")
		return
	var art := AbilityCastCatalog.ground_effect_art("AHmt")
	if art.is_empty() or not art.contains("MassTeleport"):
		_fail("AHmt 落点特效应含 MassTeleport，实际 %s" % art)
		return
	var special := AbilityFxCatalog.special_art("AHmt")
	if special.is_empty() or not special.contains("MassTeleportTarget"):
		_fail("AHmt specialart 应含 MassTeleportTarget，实际 %s" % special)
		return
	var caster_art := AbilityFxCatalog.caster_art("AHmt")
	if caster_art.is_empty() or not caster_art.contains("MassTeleportCaster"):
		_fail("AHmt casterart 应含 MassTeleportCaster，实际 %s" % caster_art)
		return
	print("  catalog OK")


func _test_gather() -> void:
	var host := Node.new()
	host.name = "UnitHost"
	root.add_child(host)
	var caster := Node3D.new()
	caster.name = "Hamg"
	caster.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	caster.set_meta("life", 500.0)
	host.add_child(caster)
	var foot := Node3D.new()
	foot.name = "Foot"
	foot.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	foot.set_meta("life", 100.0)
	host.add_child(foot)
	var bldg := Node3D.new()
	bldg.name = "TownHall"
	bldg.set_meta("unit_data", {"typeId": "htow", "owner": 0})
	bldg.set_meta("life", 2000.0)
	host.add_child(bldg)
	var picks := MassTeleportAbility._gather_candidates(host, caster, Vector2.ZERO, 700.0)
	if picks.size() != 2:
		_fail("700 半径应选中 2 个可传送单位（排除建筑），实际 %d" % picks.size())
		host.queue_free()
		return
	host.queue_free()
	print("  gather OK")
