extends SceneTree

## 英雄技能点 / 学习。
## godot --headless --path . -s res://tests/unit/selftest_hero_skill.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_points_and_levels()
	_test_command_card_hidden()
	_test_req_level()
	_test_hero_mana()
	_test_skill_menu_layout()
	if failed == 0:
		print("selftest_hero_skill: PASS")
		quit(0)
	else:
		push_error("selftest_hero_skill: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _hero(level: int = 1) -> Node3D:
	var u := Node3D.new()
	u.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	u.set_meta(AbilityCatalog.META_HERO_LEVEL, level)
	u.set_meta(AbilityCatalog.META_ABILITY_LEVELS, {})
	return u


func _test_points_and_levels() -> void:
	var u1 := _hero(1)
	root.add_child(u1)
	if HeroSkill.points_available(u1) != 1:
		_fail("1 级英雄应有 1 技能点，实际 %d" % HeroSkill.points_available(u1))
		u1.queue_free()
		return
	u1.queue_free()
	var u2 := _hero(2)
	root.add_child(u2)
	if HeroSkill.points_available(u2) != 2:
		_fail("2 级未学应有 2 技能点，实际 %d" % HeroSkill.points_available(u2))
		u2.queue_free()
		return
	var levels := {"AHwe": 1}
	u2.set_meta(AbilityCatalog.META_ABILITY_LEVELS, levels)
	if HeroSkill.points_available(u2) != 1:
		_fail("2 级学 1 后应有 1 技能点")
		u2.queue_free()
		return
	u2.queue_free()
	print("  points_levels OK")


func _test_command_card_hidden() -> void:
	var levels := {"AHwe": 1}
	var lv_we := AbilityCatalog.level_for_unit_type("Hamg", "AHwe", 2, levels)
	var lv_bz := AbilityCatalog.level_for_unit_type("Hamg", "AHbz", 2, levels)
	if lv_we != 1 or lv_bz != 0:
		_fail("命令卡等级：已学=%d 未学=%d" % [lv_we, lv_bz])
		return
	print("  card_levels OK")


func _test_req_level() -> void:
	var store := root.get_node_or_null("Wc3DefStore")
	if store == null:
		print("  req_level SKIP (no Wc3DefStore)")
		return
	store.ensure_table(AbilityDataDef.TABLE_NAME)
	var ab := store.get_row(AbilityDataDef.TABLE_NAME, "AHwe") as AbilityDataDef
	if ab == null:
		print("  req_level SKIP (no AHwe)")
		return
	if ab.required_hero_level_for_rank(0) < 1:
		_fail("AHwe rank1 req hero level 应 >= 1")
		return
	print("  req_level OK")


func _test_hero_mana() -> void:
	var u := _hero(1)
	root.add_child(u)
	UnitMana.ensure(u)
	var mx := UnitMana.get_max_mana(u)
	# Hamg INT=19 → 19×12=228
	if mx < 125:
		_fail("1 级 Hamg 魔法上限应 ≥125（水元素耗蓝），实际 %d" % mx)
		u.queue_free()
		return
	if not UnitMana.can_spend(u, 125.0):
		_fail("1 级 Hamg 满蓝应能支付 125 耗蓝")
		u.queue_free()
		return
	u.queue_free()
	print("  hero_mana OK")


func _test_skill_menu_layout() -> void:
	var card := CommandCard.for_hero_skill_menu(
		"Hamg",
		{"hero_level": 6, "ability_levels": {}, "hero_skill_points": 1}
	)
	var slots: Dictionary = {}
	var has_ultimate := false
	for entry in card:
		var aid := str(entry.get("id", ""))
		if aid.begins_with(CommandCard.ACTION_LEARN_PREFIX):
			var abil := aid.substr(CommandCard.ACTION_LEARN_PREFIX.length())
			slots[abil] = int(entry.get("slot", -1))
			if abil == "AHmt":
				has_ultimate = true
	if not has_ultimate:
		_fail("6 级技能面板应显示终极技能 AHmt")
		return
	# Researchbuttonpos：AHbz=0,0 AHwe=1,0 AHab=2,0 AHmt=3,0 → slot 0..3（第一行）
	var want := {"AHbz": 0, "AHwe": 1, "AHab": 2, "AHmt": 3}
	for abil in want:
		if int(slots.get(abil, -1)) != want[abil]:
			_fail("技能 %s 应在 slot %d，实际 %d" % [abil, want[abil], int(slots.get(abil, -1))])
			return
	print("  skill_menu_layout OK")
