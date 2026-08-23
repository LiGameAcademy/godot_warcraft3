extends SceneTree

## P0 牧师/女巫：Ahea / Ainf / Aslo 数据、Catalog、友军/敌军目标。
## godot --headless --path . -s res://tests/unit/selftest_ability_support_units.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_slk()
	_test_catalog()
	_test_target_queries()
	_test_heal_logic()
	_test_inner_fire_logic()
	_test_slow_logic()
	if failed == 0:
		print("selftest_ability_support_units: PASS")
		quit(0)
	else:
		push_error("selftest_ability_support_units: FAIL (%d)" % failed)
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
	var heal := _abil("Ahea")
	if heal == null or not is_equal_approx(heal.data_a1, 20.0):
		_fail("Ahea DataA1 应为 20")
		return
	if not is_equal_approx(heal.rng1, 250.0):
		_fail("Ahea 射程应为 250")
		return
	var inf := _abil("Ainf")
	if inf == null or not is_equal_approx(inf.data_b1, 5.0):
		_fail("Ainf DataB1 护甲应为 5")
		return
	var slo := _abil("Aslo")
	if slo == null or not is_equal_approx(slo.data_a1, 0.6):
		_fail("Aslo DataA1 应为 0.6")
		return
	print("  slk OK")


func _test_catalog() -> void:
	for id in ["Ahea", "Ainf", "Aslo"]:
		if not AbilityCatalog.is_supported(id):
			_fail("%s 应在 SUPPORTED_ORDERS" % id)
			return
	if AbilityCatalog.target_kind("Ahea") != AbilityCatalog.TARGET_ALLY:
		_fail("Ahea 应为 TARGET_ALLY")
		return
	if AbilityCatalog.target_kind("Ainf") != AbilityCatalog.TARGET_ALLY:
		_fail("Ainf 应为 TARGET_ALLY")
		return
	if AbilityCatalog.target_kind("Aslo") != AbilityCatalog.TARGET_UNIT:
		_fail("Aslo 应为 TARGET_UNIT")
		return
	var pm := AbilityCatalog.ability_ids_for_unit("hmpr")
	var has_heal := false
	for id in pm:
		if str(id) == "Ahea":
			has_heal = true
	if not has_heal:
		_fail("hmpr 应含 Ahea")
		return
	print("  catalog OK")


func _test_target_queries() -> void:
	var caster := Node3D.new()
	caster.set_meta("unit_data", {"typeId": "hmpr", "owner": 0})
	var ally := Node3D.new()
	ally.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	ally.set_meta("life", 50.0)
	var building := Node3D.new()
	building.set_meta("unit_data", {"typeId": "htow", "owner": 0})
	building.set_meta("life", 1500.0)
	var foe := Node3D.new()
	foe.set_meta("unit_data", {"typeId": "hfoo", "owner": 1})
	foe.set_meta("life", 100.0)
	root.add_child(caster)
	root.add_child(ally)
	root.add_child(building)
	root.add_child(foe)
	if not CombatQuery.is_valid_ally_spell_target(caster, ally):
		_fail("同玩家友军应合法")
		return
	if CombatQuery.is_valid_ally_spell_target(caster, foe):
		_fail("敌军不应为友军技能目标")
		return
	if not CombatQuery.is_valid_hostile_spell_target(caster, foe):
		_fail("敌军应合法")
		return
	if not CombatQuery.is_valid_ability_unit_target(caster, ally, "Ainf"):
		_fail("Ainf 应对步兵合法")
		return
	caster.set_meta("life", 80.0)
	if not CombatQuery.is_valid_ability_unit_target(caster, caster, "Ahea"):
		_fail("Ahea 应对自身合法（targs 含 self）")
		return
	if CombatQuery.is_valid_ability_unit_target(caster, building, "Ainf"):
		_fail("Ainf 不应对城镇大厅施放")
		return
	if CombatQuery.is_valid_ability_unit_target(caster, building, "Ahea"):
		_fail("Ahea 不应对建筑施放")
		return
	if not CombatQuery.is_valid_ability_unit_target(caster, foe, "Aslo"):
		_fail("Aslo 应对敌军步兵合法")
		return
	if CombatQuery.is_valid_ability_unit_target(caster, building, "Aslo"):
		_fail("Aslo 不应对建筑施放")
		return
	caster.queue_free()
	ally.queue_free()
	building.queue_free()
	foe.queue_free()
	print("  target_queries OK")


func _test_heal_logic() -> void:
	var ab := _abil("Ahea")
	if ab == null:
		_fail("Ahea 数据缺失")
		return
	if not is_equal_approx(ab.data_a1, 20.0):
		_fail("治疗量应为 20")
		return
	print("  heal_logic OK")


func _test_inner_fire_logic() -> void:
	var ally := Node3D.new()
	ally.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	root.add_child(ally)
	UnitStatusEffects.set_inner_fire(ally, 5.0, 1.1)
	if not is_equal_approx(UnitStatusEffects.bonus_armor(ally), 5.0):
		_fail("心灵之火护甲")
		return
	if not is_equal_approx(UnitStatusEffects.damage_mul(ally), 1.1):
		_fail("心灵之火伤害倍率")
		return
	UnitStatusEffects.clear_inner_fire(ally)
	if UnitStatusEffects.bonus_armor(ally) > 0.0:
		_fail("清除心灵之火后护甲应为 0")
		return
	ally.queue_free()
	print("  inner_fire_logic OK")


func _test_slow_logic() -> void:
	var foe := Node3D.new()
	foe.set_meta("unit_data", {"typeId": "hfoo", "owner": 1})
	var nav := UnitNavigator.new()
	nav.name = "UnitNavigator"
	foe.add_child(nav)
	root.add_child(foe)
	UnitStatusEffects.apply_slow(foe, 60.0, 0.6)
	UnitStatusEffects.apply_attack_slow(foe, 60.0, 0.25)
	if nav.speed_mul > 0.65:
		_fail("减速移速")
		return
	if UnitStatusEffects.attack_speed_mul(foe) > 0.3:
		_fail("减速攻速")
		return
	foe.queue_free()
	print("  slow_logic OK")
