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
	_test_buff_apply_and_hud()
	_test_mana_regen_bonus()
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
	if AbilityCatalog.level_for_unit_type("Hamg", "AHab", 1, {}) != 0:
		_fail("1 级 Hamg 未学 AHab 时应为 0")
		return
	print("  catalog OK")


func _learn(unit: Node3D, abil_id: String) -> void:
	unit.set_meta(AbilityCatalog.META_HERO_LEVEL, 2)
	unit.set_meta(AbilityCatalog.META_ABILITY_LEVELS, {abil_id: 1})


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
	unit.set_meta(UnitMana.META_MAX_MANA, 100)
	unit.set_meta(UnitMana.META_MANA, 50)
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


func _test_buff_apply_and_hud() -> void:
	if BuffCatalog.buff_id_for_ability("AHab") != BuffCatalog.ID_BRILLIANCE:
		_fail("AHab 应映射到 brilliance Buff")
		return
	var unit_host := Node.new()
	unit_host.name = "UnitHost"
	root.add_child(unit_host)
	var caster := Node3D.new()
	caster.name = "Hamg"
	caster.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	caster.set_meta(UnitMana.META_MAX_MANA, 100)
	caster.set_meta(UnitMana.META_MANA, 50)
	_learn(caster, "AHab")
	unit_host.add_child(caster)
	var ally := Node3D.new()
	ally.name = "AllyMage"
	ally.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	ally.set_meta("life", 100.0)
	ally.set_meta(UnitMana.META_MAX_MANA, 100)
	ally.set_meta(UnitMana.META_MANA, 50)
	unit_host.add_child(ally)
	# 直接测 Controller 的 Buff 同步（不依赖 AbilityCatalog / SLK 进程帧）
	var ctrl := BrillianceAuraController.ensure_on(caster)
	ctrl._sync_buffs(caster, [caster, ally], 0.75)
	var bh_c := BuffHost.of(caster)
	var bh_a := BuffHost.of(ally)
	if bh_c == null or not bh_c.has_buff(BuffCatalog.ID_BRILLIANCE):
		_fail("施法者应有 brilliance Buff")
		unit_host.queue_free()
		return
	if bh_a == null or not bh_a.has_buff(BuffCatalog.ID_BRILLIANCE):
		_fail("范围内友军应有 brilliance Buff")
		unit_host.queue_free()
		return
	# 无魔法值单位（脚兵）不应挂 Buff
	var foot := Node3D.new()
	foot.name = "Footman"
	foot.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	foot.set_meta("life", 100.0)
	unit_host.add_child(foot)
	ctrl._sync_buffs(caster, [caster, ally, foot], 0.75)
	if BuffHost.of(foot) != null and BuffHost.of(foot).has_buff(BuffCatalog.ID_BRILLIANCE):
		_fail("无魔法值单位不应获得 brilliance Buff")
		unit_host.queue_free()
		return
	var p := bh_a.get_params(BuffCatalog.ID_BRILLIANCE)
	if not is_equal_approx(float(p.get("mana_regen", 0.0)), 0.75):
		_fail("Buff mana_regen 应为 0.75")
		unit_host.queue_free()
		return
	if not bool(p.get("aura", false)):
		_fail("Buff 应标记 aura=true")
		unit_host.queue_free()
		return
	var entries := BuffQuery.hud_entries(ally)
	var found := false
	for raw in entries:
		var e := raw as Dictionary
		if str(e.get("id", "")) != BuffCatalog.ID_BRILLIANCE:
			continue
		found = true
		if float(e.get("left", 0.0)) >= 0.0:
			_fail("光环 hud left 应为 -1（不闪烁）")
			unit_host.queue_free()
			return
		var tip := str(e.get("tooltip", ""))
		if not tip.contains("辉煌") and not tip.contains("魔法恢复"):
			_fail("光环 tooltip 应含名称或回蓝描述：%s" % tip)
			unit_host.queue_free()
			return
		break
	if not found:
		_fail("hud_entries 应含 brilliance")
		unit_host.queue_free()
		return
	# 离范围：第二帧 allies 不含 ally
	ctrl._sync_buffs(caster, [caster], 0.75)
	if BuffHost.of(ally) != null and BuffHost.of(ally).has_buff(BuffCatalog.ID_BRILLIANCE):
		_fail("离范围后应移除 brilliance")
		unit_host.queue_free()
		return
	if BuffHost.of(caster) == null or not BuffHost.of(caster).has_buff(BuffCatalog.ID_BRILLIANCE):
		_fail("施法者仍在范围应保留 brilliance")
		unit_host.queue_free()
		return
	unit_host.queue_free()
	print("  buff_apply_and_hud OK")


func _test_mana_regen_bonus() -> void:
	var unit := Node3D.new()
	unit.name = "Hamg"
	unit.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	root.add_child(unit)
	unit.set_meta(UnitMana.META_MAX_MANA, 100)
	unit.set_meta(UnitMana.META_MANA, 50)
	if not is_equal_approx(BuffQuery.mana_regen_bonus(unit), 0.0):
		_fail("无 Buff 时 mana_regen_bonus 应为 0")
		unit.queue_free()
		return
	BuffHost.ensure_on(unit).apply(BuffCatalog.ID_BRILLIANCE, 1.0, {
		"mana_regen": 0.75,
		"aura": true,
		"source_id": 1,
	})
	if not is_equal_approx(BuffQuery.mana_regen_bonus(unit), 0.75):
		_fail("mana_regen_bonus 应为 0.75，实际 %s" % BuffQuery.mana_regen_bonus(unit))
		unit.queue_free()
		return
	# 模拟 UnitRegen 叠加路径：bonus * delta 累积回蓝
	var before := UnitMana.get_mana(unit)
	UnitMana.regenerate(unit, BuffQuery.mana_regen_bonus(unit))
	UnitMana.regenerate(unit, BuffQuery.mana_regen_bonus(unit))
	if UnitMana.get_mana(unit) != before + 1:
		_fail("Buff 回蓝 1.5 应 +1，实际 %d→%d" % [before, UnitMana.get_mana(unit)])
		unit.queue_free()
		return
	var tip := BuffCatalog.tooltip_text(BuffCatalog.ID_BRILLIANCE, {"mana_regen": 0.75, "aura": true}, -1.0)
	if tip.contains("剩余"):
		_fail("光环 tooltip 不应含剩余时间：%s" % tip)
		unit.queue_free()
		return
	unit.queue_free()
	print("  mana_regen_bonus OK")
