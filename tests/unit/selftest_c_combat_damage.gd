extends SceneTree

## C0-1 战斗伤害公式 selftest（攻防表 + 护甲）。
## godot --headless --path . -s res://tests/unit/selftest_c_combat_damage.gd

var passed: int = 0
var total: int = 10


func _init() -> void:
	_test_pierce_vs_small()
	_test_normal_vs_medium()
	_test_siege_vs_fort()
	_test_pierce_vs_fort()
	_test_hero_vs_fort()
	_test_armor_factor_zero()
	_test_armor_positive()
	_test_armor_negative()
	_test_pipeline_roll_fixed()
	_test_min_damage_floor()

	if passed == total:
		print("selftest_c_combat_damage: PASS")
		quit(0)
	else:
		push_error("selftest_c_combat_damage: FAIL %d/%d" % [passed, total])
		quit(1)


func _ok(name: String, cond: bool) -> void:
	if cond:
		print("  %s OK" % name)
		passed += 1
	else:
		push_error("  %s FAIL" % name)


func _test_pierce_vs_small() -> void:
	_ok("pierce vs small = 2.0", is_equal_approx(CombatDamageTable.multiplier("pierce", "small"), 2.0))


func _test_normal_vs_medium() -> void:
	_ok("normal vs medium = 1.5", is_equal_approx(CombatDamageTable.multiplier("normal", "medium"), 1.5))


func _test_siege_vs_fort() -> void:
	_ok("siege vs fort = 1.5", is_equal_approx(CombatDamageTable.multiplier("siege", "fort"), 1.5))


func _test_pierce_vs_fort() -> void:
	_ok("pierce vs fort = 0.35", is_equal_approx(CombatDamageTable.multiplier("pierce", "fort"), 0.35))


func _test_hero_vs_fort() -> void:
	_ok("hero vs fort = 0.5", is_equal_approx(CombatDamageTable.multiplier("hero", "fort"), 0.5))


func _test_armor_factor_zero() -> void:
	_ok("armor 0 → factor 1", is_equal_approx(CombatDamageTable.armor_factor(0.0), 1.0))


func _test_armor_positive() -> void:
	# armor 5 → 1 - 0.3/(1+0.3) = 1 - 0.3/1.3 ≈ 0.76923
	var f := CombatDamageTable.armor_factor(5.0)
	_ok("armor 5 ≈ 0.769", absf(f - (1.0 - 0.3 / 1.3)) < 0.001)


func _test_armor_negative() -> void:
	# armor -5 → 1 - (-0.3)/(1+0.3) = 1 + 0.3/1.3 ≈ 1.23077
	var f := CombatDamageTable.armor_factor(-5.0)
	_ok("armor -5 ≈ 1.231", absf(f - (1.0 + 0.3 / 1.3)) < 0.001)


func _test_pipeline_roll_fixed() -> void:
	# 纯公式：dice 总和 + type + armor（不依赖 DefStore / 场景节点）
	var roll := 1.0 + 3.0 + 3.0 + 3.0 # dmgplus1 + 三个骰面
	var mult := CombatDamageTable.multiplier("normal", "medium")
	var after := roll * mult # 10 * 1.5 = 15
	var final_v := CombatDamageTable.apply_armor(after, 0.0)
	_ok("roll×type×armor(0) = 15", is_equal_approx(final_v, 15.0))


func _test_min_damage_floor() -> void:
	# Pipeline 规则：0 < amount < 1 → 至少 1（表本身可出小数）
	var tiny := CombatDamageTable.apply_armor(0.4, 0.0)
	_ok("table keeps 0.4", is_equal_approx(tiny, 0.4))
