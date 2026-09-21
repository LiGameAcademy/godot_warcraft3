extends SceneTree
## UnitRequiresCatalog + TechPresence 自测。
## godot --headless --path . -s res://tests/unit/selftest_tech_presence.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_requires_parse()
	_test_equiv_htow()
	_test_vertical_trains()
	_test_vertical_researches()
	_test_hbar_researches_csv()
	_test_hbla_researches_csv()
	_test_hrif_needs_hbla()
	_test_upgrade_stock()
	_test_upgrade_effects()
	_test_upgrade_level_costs()
	_test_adef_requires_rhde()
	_test_command_card_defend_and_research()
	_test_command_card_blacksmith()
	_test_building_upgrade_chain()
	if failed == 0:
		print("selftest_tech_presence: PASS")
		quit(0)
	else:
		push_error("selftest_tech_presence: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_requires_parse() -> void:
	var cat := UnitRequiresCatalog.get_shared()
	var hbla := cat.get_requires("hbla")
	if hbla.size() != 1 or str(hbla[0]) != "htow":
		_fail("hbla Requires 应为 [htow]，实际 %s" % str(hbla))
		return
	var hrif := cat.get_requires("hrif")
	if hrif.size() != 1 or str(hrif[0]) != "hbla":
		_fail("hrif Requires 应为 [hbla]，实际 %s" % str(hrif))
		return
	var hlum := cat.get_requires("hlum")
	if not hlum.is_empty():
		_fail("hlum 应无 Requires，实际 %s" % str(hlum))
		return
	# 英雄 Requires= 空，不能误吃 Requires1
	var hamg := cat.get_requires("Hamg")
	if not hamg.is_empty():
		_fail("Hamg Requires= 应空，实际 %s" % str(hamg))
		return
	print("  requires_parse OK")


func _test_equiv_htow() -> void:
	var owned_keep := {"hkee": 1}
	if not TechPresence.owns_requirement(owned_keep, "htow"):
		_fail("hkee 应满足 htow 需求")
		return
	if TechPresence.owns_requirement({"hlum": 1}, "htow"):
		_fail("hlum 不应满足 htow")
		return
	print("  equiv_htow OK")


func _test_vertical_trains() -> void:
	var raw := PackedStringArray(["Hamg", "Hmkg", "Hpal", "Hblm"])
	var filtered := TechPresence.filter_vertical_trains("halt", raw)
	if filtered.size() != 4:
		_fail("祭坛竖切应保留四人族英雄，实际 %s" % str(filtered))
		return
	var bar := TechPresence.filter_vertical_trains(
		"hbar", PackedStringArray(["hfoo", "hrif", "hkni"])
	)
	if bar.size() != 2 or str(bar[0]) != "hfoo" or str(bar[1]) != "hrif":
		_fail("兵营竖切应为 hfoo,hrif，实际 %s" % str(bar))
		return
	print("  vertical_trains OK")


func _test_vertical_researches() -> void:
	var raw := PackedStringArray(["Rhde", "Rhan", "Rhri"])
	var filtered := TechPresence.filter_vertical_researches("hbar", raw)
	if filtered.size() != 1 or str(filtered[0]) != "Rhde":
		_fail("兵营竖切研究应只留 Rhde，实际 %s" % str(filtered))
		return
	var bla := TechPresence.filter_vertical_researches(
		"hbla", PackedStringArray(["Rhme", "Rhar", "Rhla", "Rhra", "Rhac"])
	)
	if bla.size() != 4:
		_fail("铁匠竖切应留 Rhme/Rhar/Rhla/Rhra，实际 %s" % str(bla))
		return
	if str(bla[0]) != "Rhme" or str(bla[1]) != "Rhar" or str(bla[2]) != "Rhla" or str(bla[3]) != "Rhra":
		_fail("铁匠竖切顺序应为 Rhme,Rhar,Rhla,Rhra，实际 %s" % str(bla))
		return
	print("  vertical_researches OK")


func _test_hbar_researches_csv() -> void:
	var rs := CommandButtonCatalog.get_shared().get_researches("hbar")
	if rs.find("Rhde") < 0:
		_fail("hbar Researches 应含 Rhde，实际 %s" % str(rs))
		return
	print("  hbar_researches_csv OK")


func _test_hbla_researches_csv() -> void:
	var rs := CommandButtonCatalog.get_shared().get_researches("hbla")
	for want in ["Rhme", "Rhar", "Rhla", "Rhra"]:
		if rs.find(want) < 0:
			_fail("hbla Researches 应含 %s，实际 %s" % [want, str(rs)])
			return
	print("  hbla_researches_csv OK")


func _test_upgrade_stock() -> void:
	var s := PlayerStock.new()
	if s.has_upgrade("Rhde"):
		_fail("新库存不应已有 Rhde")
		return
	s.grant_upgrade("Rhde")
	if not s.has_upgrade("Rhde"):
		_fail("grant_upgrade 后应有 Rhde")
		return
	var missing := TechPresence.missing_requires({}, PackedStringArray(["Rhde"]), s.upgrade_map())
	if not missing.is_empty():
		_fail("已研究 Rhde 后 missing 应空，实际 %s" % str(missing))
		return
	print("  upgrade_stock OK")


func _test_upgrade_effects() -> void:
	var fx1 := TechPresence.upgrade_effect_bonus("Rhme", 1)
	if str(fx1.get("effect", "")) != "ratd" or absf(float(fx1.get("amount", 0.0)) - 1.0) > 0.01:
		_fail("Rhme L1 应为 ratd+1，实际 %s" % str(fx1))
		return
	var fx3 := TechPresence.upgrade_effect_bonus("Rhme", 3)
	if absf(float(fx3.get("amount", 0.0)) - 3.0) > 0.01:
		_fail("Rhme L3 应为 ratd+3，实际 %s" % str(fx3))
		return
	var arm := TechPresence.upgrade_effect_bonus("Rhar", 2)
	if str(arm.get("effect", "")) != "rarm" or absf(float(arm.get("amount", 0.0)) - 4.0) > 0.01:
		_fail("Rhar L2 应为 rarm+4，实际 %s" % str(arm))
		return
	var session := GameSession.new()
	TechPresence.bind_session(session)
	var stock := session.ensure_stock(0)
	stock.grant_upgrade("Rhme", 2)
	stock.grant_upgrade("Rhar", 1)
	var unit := Node3D.new()
	unit.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	# 不入树也可读 balance / stock
	var atk := TechPresence.unit_attack_bonus(unit)
	var def := TechPresence.unit_armor_bonus(unit)
	unit.free()
	TechPresence.bind_session(null)
	if absf(atk - 2.0) > 0.01:
		_fail("步兵 Rhme L2 攻击加成应为 2，实际 %s" % atk)
		return
	if absf(def - 2.0) > 0.01:
		_fail("步兵 Rhar L1 护甲加成应为 2，实际 %s" % def)
		return
	print("  upgrade_effects OK")


func _test_upgrade_level_costs() -> void:
	var g1 := TechPresence.upgrade_gold_at_level("Rhme", 1)
	var g2 := TechPresence.upgrade_gold_at_level("Rhme", 2)
	if g1 != 100:
		_fail("Rhme L1 金价应为 100，实际 %d" % g1)
		return
	if g2 != 175:
		_fail("Rhme L2 金价应为 175，实际 %d" % g2)
		return
	var req2 := TechPresence.upgrade_requires_for_level("Rhme", 2)
	if req2.size() != 1 or str(req2[0]) != "hkee":
		_fail("Rhme L2 应需 hkee，实际 %s" % str(req2))
		return
	var next := TechPresence.upgrade_next_level("Rhme", 3)
	if next != 0:
		_fail("Rhme 满级后 next 应为 0，实际 %d" % next)
		return
	print("  upgrade_level_costs OK")


func _test_hrif_needs_hbla() -> void:
	var missing := TechPresence.missing_requires(
		{"htow": 1, "hbar": 1},
		UnitRequiresCatalog.get_shared().get_requires("hrif")
	)
	if missing.size() != 1 or str(missing[0]) != "hbla":
		_fail("无铁匠时应缺 hbla，实际 %s" % str(missing))
		return
	var ok := TechPresence.missing_requires(
		{"htow": 1, "hbar": 1, "hbla": 1},
		UnitRequiresCatalog.get_shared().get_requires("hrif")
	)
	if not ok.is_empty():
		_fail("有铁匠后 hrif 应可训，实际缺 %s" % str(ok))
		return
	print("  hrif_needs_hbla OK")


func _test_adef_requires_rhde() -> void:
	var req := CommandButtonCatalog.get_shared().get_ability_requires("Adef")
	if req.find("Rhde") < 0:
		_fail("Adef Requires 应含 Rhde，实际 %s" % str(req))
		return
	var missing := TechPresence.missing_requires({}, req, {})
	if missing.find("Rhde") < 0:
		_fail("未研究时顶盾应缺 Rhde")
		return
	var ok := TechPresence.missing_requires({}, req, {"Rhde": 1})
	if not ok.is_empty():
		_fail("已研究 Rhde 后 Adef 应解锁，实际缺 %s" % str(ok))
		return
	print("  adef_requires_rhde OK")


func _card_entry(card: Array, action_id: String) -> Dictionary:
	for e in card:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d := e as Dictionary
		if str(d.get("id", "")) == action_id:
			return d
	return {}


func _test_command_card_defend_and_research() -> void:
	var locked := CommandCard.for_unit("hfoo", {"researched": {}})
	var adef := _card_entry(locked, CommandCard.ACTION_DEFEND)
	if adef.is_empty():
		_fail("步兵未研究时命令卡应有置灰顶盾格")
		return
	if bool(adef.get("enabled", true)):
		_fail("未研究 Rhde 时顶盾应置灰")
		return
	var unlocked := CommandCard.for_unit("hfoo", {"researched": {"Rhde": 1}})
	adef = _card_entry(unlocked, CommandCard.ACTION_DEFEND)
	if adef.is_empty() or not bool(adef.get("enabled", false)):
		_fail("已研究 Rhde 后场上/新训步兵顶盾应可点")
		return
	var on := CommandCard.for_unit(
		"hfoo", {"researched": {"Rhde": 1}, "defend_active": true}
	)
	adef = _card_entry(on, CommandCard.ACTION_DEFEND)
	var icon := str(adef.get("icon", "")).replace("\\", "/")
	if icon.find("DefendStop") < 0:
		_fail("开启顶盾后图标应切 Unart DefendStop，实际 %s" % icon)
		return
	var bar := CommandCard.for_unit("hbar", {"include_locomotion": false, "researched": {}})
	if _card_entry(bar, "research:Rhde").is_empty():
		_fail("兵营未研究时应有 Rhde 研究按钮")
		return
	var bar_done := CommandCard.for_unit(
		"hbar", {"include_locomotion": false, "researched": {"Rhde": 1}}
	)
	if not _card_entry(bar_done, "research:Rhde").is_empty():
		_fail("研究完成后兵营 Rhde 按钮应消失")
		return
	print("  command_card_defend_and_research OK")


func _test_command_card_blacksmith() -> void:
	var card := CommandCard.for_unit("hbla", {"include_locomotion": false, "researched": {}})
	for rid in ["Rhme", "Rhar", "Rhla", "Rhra"]:
		if _card_entry(card, "research:" + rid).is_empty():
			_fail("铁匠未研究时应有 %s 按钮" % rid)
			return
	var partial := CommandCard.for_unit(
		"hbla", {"include_locomotion": false, "researched": {"Rhme": 1}, "owned_buildings": {}}
	)
	var rhme := _card_entry(partial, "research:Rhme")
	if rhme.is_empty():
		_fail("Rhme L1 后应仍显示 L2 按钮")
		return
	if bool(rhme.get("enabled", true)):
		_fail("无 Keep 时 Rhme L2 应置灰")
		return
	var with_keep := CommandCard.for_unit(
		"hbla",
		{"include_locomotion": false, "researched": {"Rhme": 1}, "owned_buildings": {"hkee": 1}}
	)
	rhme = _card_entry(with_keep, "research:Rhme")
	if rhme.is_empty() or not bool(rhme.get("enabled", false)):
		_fail("有 Keep 时 Rhme L2 应可点")
		return
	var full := CommandCard.for_unit(
		"hbla", {"include_locomotion": false, "researched": {"Rhme": 3}}
	)
	if not _card_entry(full, "research:Rhme").is_empty():
		_fail("Rhme 满级后按钮应消失")
		return
	print("  command_card_blacksmith OK")


func _test_building_upgrade_chain() -> void:
	if TechPresence.building_upgrade_target("htow") != "hkee":
		_fail("htow Upgrade 目标应为 hkee")
		return
	if TechPresence.building_upgrade_target("hkee") != "hcas":
		_fail("hkee Upgrade 目标应为 hcas")
		return
	if not TechPresence.building_upgrade_target("hcas").is_empty():
		_fail("hcas 不应再升本")
		return
	var g := TechPresence.building_upgrade_gold("htow", "hkee")
	var l := TechPresence.building_upgrade_lumber("htow", "hkee")
	if g != 320 or l != 210:
		_fail("htow→hkee 差价应为 320金/210木，实际 %d/%d" % [g, l])
		return
	var t := TechPresence.building_upgrade_time("hkee")
	if t < 100.0:
		_fail("hkee 升本时间应约 140s，实际 %s" % t)
		return
	var card := CommandCard.for_unit("htow", {"include_locomotion": false, "researched": {}})
	if _card_entry(card, "upgrade:hkee").is_empty():
		_fail("主城命令卡应有升 Keep 按钮")
		return
	var keep_card := CommandCard.for_unit(
		"hkee", {"include_locomotion": false, "owned_buildings": {"hkee": 1}}
	)
	var up_cas := _card_entry(keep_card, "upgrade:hcas")
	if up_cas.is_empty():
		_fail("Keep 命令卡应有升 Castle 按钮")
		return
	if bool(up_cas.get("enabled", true)):
		_fail("无祭坛时升 Castle 应置灰")
		return
	var with_altar := CommandCard.for_unit(
		"hkee",
		{"include_locomotion": false, "owned_buildings": {"hkee": 1, "halt": 1}}
	)
	up_cas = _card_entry(with_altar, "upgrade:hcas")
	if up_cas.is_empty() or not bool(up_cas.get("enabled", false)):
		_fail("有祭坛时升 Castle 应可点")
		return
	print("  building_upgrade_chain OK")
