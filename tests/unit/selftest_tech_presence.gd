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
	_test_hrif_needs_hbla()
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
