extends SceneTree

## Unit natural HP/mana regen selftest.
## godot --headless --path . -s res://tests/unit/selftest_unit_regen.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_allows_hp_regen()
	_test_rates_from_balance()
	_test_life_regenerate()
	_test_mana_regenerate_accum()
	if failed == 0:
		print("selftest_unit_regen: PASS")
		quit(0)
	else:
		push_error("selftest_unit_regen: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_allows_hp_regen() -> void:
	if not UnitRegen.allows_hp_regen("always"):
		_fail("always should allow hp regen")
		return
	if UnitRegen.allows_hp_regen("none"):
		_fail("none should block hp regen")
		return
	if UnitRegen.allows_hp_regen("blight"):
		_fail("blight deferred until blight system")
		return
	if UnitRegen.allows_hp_regen("night"):
		_fail("night deferred until day/night system")
		return
	print("  allows_hp_regen OK")


func _test_rates_from_balance() -> void:
	var bal := UnitBalanceDef.new()
	bal.regen_hp = 0.25
	bal.regen_type = "always"
	bal.regen_mana = 0.01
	bal.str_base = 14
	bal.st_rplus = 2.0
	bal.int_base = 19
	bal.in_tplus = 3.2
	var hp1 := UnitRegen.hp_rate_from_balance(bal, true, 1)
	var expect_hp1 := 0.25 + 14.0 * UnitRegen.HERO_HP_REGEN_PER_STR
	if not is_equal_approx(hp1, expect_hp1):
		_fail("hero lv1 hp regen expected %.4f got %.4f" % [expect_hp1, hp1])
		return
	var hp2 := UnitRegen.hp_rate_from_balance(bal, true, 2)
	var expect_hp2 := 0.25 + 16.0 * UnitRegen.HERO_HP_REGEN_PER_STR
	if not is_equal_approx(hp2, expect_hp2):
		_fail("hero lv2 hp regen expected %.4f got %.4f" % [expect_hp2, hp2])
		return
	var mana1 := UnitRegen.mana_rate_from_balance(bal, true, 1)
	var expect_mana1 := 0.01 + 19.0 * UnitRegen.HERO_MANA_REGEN_PER_INT
	if not is_equal_approx(mana1, expect_mana1):
		_fail("hero lv1 mana regen expected %.4f got %.4f" % [expect_mana1, mana1])
		return
	bal.regen_type = "none"
	if UnitRegen.hp_rate_from_balance(bal, false, 1) != 0.0:
		_fail("regenType=none must yield 0 hp rate")
		return
	bal.regen_type = "always"
	bal.regen_hp = 0.25
	if not is_equal_approx(UnitRegen.hp_rate_from_balance(bal, false, 1), 0.25):
		_fail("non-hero hp regen should be table value")
		return
	print("  rates_from_balance OK")


func _test_life_regenerate() -> void:
	var unit := Node3D.new()
	unit.name = "Footman"
	unit.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	unit.set_meta(UnitLife.META_MAX_LIFE, 420.0)
	unit.set_meta(UnitLife.META_LIFE, 100.0)
	root.add_child(unit)
	UnitLife.regenerate(unit, 12.5)
	var life := UnitLife.get_life(unit)
	if not is_equal_approx(life, 112.5):
		_fail("after +12.5 life expected 112.5 got %.2f" % life)
		unit.queue_free()
		return
	UnitLife.regenerate(unit, 9999.0)
	if not is_equal_approx(UnitLife.get_life(unit), 420.0):
		_fail("life regen must clamp to max")
		unit.queue_free()
		return
	unit.set_meta(UnitLife.META_LIFE, 0.0)
	UnitLife.regenerate(unit, 50.0)
	if not is_equal_approx(UnitLife.get_life(unit), 0.0):
		_fail("dead unit must not regen life")
		unit.queue_free()
		return
	unit.queue_free()
	print("  life_regenerate OK")


func _test_mana_regenerate_accum() -> void:
	var unit := Node3D.new()
	unit.name = "Caster"
	unit.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	unit.set_meta(UnitMana.META_MAX_MANA, 100)
	unit.set_meta(UnitMana.META_MANA, 50)
	root.add_child(unit)
	UnitMana.regenerate(unit, 0.75)
	UnitMana.regenerate(unit, 0.75)
	if UnitMana.get_mana(unit) != 51:
		_fail("1.5 mana accum should +1, got %d" % UnitMana.get_mana(unit))
		unit.queue_free()
		return
	unit.queue_free()
	print("  mana_regenerate_accum OK")
