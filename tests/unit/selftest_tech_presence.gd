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
	_test_hrif_needs_hbla()
	_test_upgrade_stock()
	_test_adef_requires_rhde()
	_test_command_card_defend_and_research()
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
	if filtered.size() != 1 or str(filtered[0]) != "Hamg":
		_fail("祭坛竖切应只留 Hamg，实际 %s" % str(filtered))
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
	print("  vertical_researches OK")


func _test_hbar_researches_csv() -> void:
	var rs := CommandButtonCatalog.get_shared().get_researches("hbar")
	if rs.find("Rhde") < 0:
		_fail("hbar Researches 应含 Rhde，实际 %s" % str(rs))
		return
	print("  hbar_researches_csv OK")


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
