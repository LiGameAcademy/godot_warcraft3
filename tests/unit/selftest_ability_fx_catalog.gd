extends SceneTree

## Phase B：AbilityFxCatalog 路径与 fallback。
## godot --headless --path . -s res://tests/unit/selftest_ability_fx_catalog.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_fallback_paths()
	_test_buff_row()
	_test_ahab_brilliance_arts()
	if failed == 0:
		print("selftest_ability_fx_catalog: PASS")
		quit(0)
	else:
		push_error("selftest_ability_fx_catalog: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_fallback_paths() -> void:
	var cases := {
		"AHtb": "StormBoltTarget",
		"Ahea": "HealTarget",
		"AHbz": "BlizzardTarget",
		"AHmt": "MassTeleportTo",
	}
	for id in cases:
		var art := AbilityFxCatalog.hit_effect_art(id) if id != "AHbz" and id != "AHmt" else ""
		if id == "AHbz":
			art = AbilityFxCatalog.ground_effect_art(id)
		elif id == "AHmt":
			art = AbilityFxCatalog.ground_effect_art(id)
		if not art.contains(cases[id]):
			_fail("%s 特效路径应含 %s，实际 %s" % [id, cases[id], art])
			return
	if not AbilityFxCatalog.caster_art("AHtc").contains("ThunderClap"):
		_fail("AHtc caster 路径")
		return
	print("  fallback_paths OK")


func _test_buff_row() -> void:
	if AbilityFxCatalog.buff_row_id("AHab") != "BHab":
		_fail("AHab → BHab")
		return
	var art := AbilityFxCatalog.buff_beneficiary_art("AHab")
	if not art.contains("GeneralAuraTarget"):
		_fail("AHab 受益特效")
		return
	print("  buff_row OK")


func _test_ahab_brilliance_arts() -> void:
	# 施法者环：AHab Targetart=Brilliance.mdl（无独立 Casterart）
	var caster := AbilityFxCatalog.target_art("AHab")
	if not caster.contains("Brilliance"):
		_fail("AHab target_art 应为 Brilliance，实际 %s" % caster)
		return
	var attach := AbilityFxCatalog.target_attach("AHab")
	if attach != "origin":
		_fail("AHab/BHab Targetattach 应为 origin，实际 %s" % attach)
		return
	var path := RuntimeAssets.converted_path(caster)
	var scn := path.get_basename() + ".scn"
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(scn):
		_fail("Brilliance 转换资产缺失：%s" % path)
		return
	var tex := path.get_base_dir().path_join("TjShockwave2.png")
	if not FileAccess.file_exists(tex):
		_fail("Brilliance 同目录贴图缺失：%s（否则脚底白面片）" % tex)
		return
	var benef := AbilityFxCatalog.buff_beneficiary_art("AHab")
	var benef_path := RuntimeAssets.converted_path(benef)
	if not FileAccess.file_exists(benef_path) and not FileAccess.file_exists(benef_path.get_basename() + ".scn"):
		_fail("GeneralAuraTarget 转换资产缺失：%s" % benef_path)
		return
	print("  ahab_brilliance_arts OK")
