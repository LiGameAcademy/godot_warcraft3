extends SceneTree

## C2：weapTp 投送分类 + 弹道飞行时间 + UnitFunc（Hamg/hrif）。
## godot --headless --path . -s res://tests/unit/selftest_c_combat_projectile.gd

func _init() -> void:
	var ok := true
	ok = _assert_eq(
		CombatQuery.classify_weap_tp("instant"), CombatQuery.Delivery.INSTANT, "instant"
	) and ok
	ok = _assert_eq(
		CombatQuery.classify_weap_tp("normal"), CombatQuery.Delivery.INSTANT, "normal"
	) and ok
	ok = _assert_eq(
		CombatQuery.classify_weap_tp(""), CombatQuery.Delivery.INSTANT, "empty"
	) and ok
	ok = _assert_eq(
		CombatQuery.classify_weap_tp("missile"), CombatQuery.Delivery.MISSILE, "missile"
	) and ok
	ok = _assert_eq(
		CombatQuery.classify_weap_tp("mbounce"), CombatQuery.Delivery.MISSILE, "mbounce"
	) and ok
	ok = _assert_eq(
		CombatQuery.classify_weap_tp("msplash"), CombatQuery.Delivery.MISSILE, "msplash"
	) and ok
	ok = _assert_eq(
		CombatQuery.classify_weap_tp("artillery"), CombatQuery.Delivery.ARTILLERY, "artillery"
	) and ok

	var t := CombatQuery.travel_time_sec(1900.0, 1900.0)
	if absf(t - 1.0) > 0.001:
		push_error("travel_time 1900/1900 应为 1，得 %s" % t)
		ok = false
	else:
		print("  travel_time OK")

	t = CombatQuery.travel_time_sec(400.0, 1900.0)
	if t <= 0.0 or t >= 1.0:
		push_error("hrif 典型射程飞行时间应在 (0,1)，得 %s" % t)
		ok = false
	else:
		print("  hrif-ish travel OK (%.3fs)" % t)

	ok = _test_unit_func_missile() and ok

	if ok:
		print("selftest_c_combat_projectile: PASS")
		quit(0)
	else:
		push_error("selftest_c_combat_projectile: FAIL")
		quit(1)


func _test_unit_func_missile() -> bool:
	var ok := true
	var hamg_art := CombatQuery.missile_art_for_type("Hamg")
	if hamg_art.findn("FireBallMissile") < 0:
		push_error("Hamg missile art 应为 FireBall，得 %s" % hamg_art)
		ok = false
	else:
		print("  Hamg missile_art OK (%s)" % hamg_art)
	var hamg_spd := CombatQuery.missile_speed_for_type("Hamg")
	if absf(hamg_spd - 900.0) > 0.1:
		push_error("Hamg Missilespeed 应为 900，得 %s" % hamg_spd)
		ok = false
	else:
		print("  Hamg missilespeed OK")
	var hamg_arc := CombatQuery.missile_arc_for_type("Hamg")
	if absf(hamg_arc - 0.15) > 0.001:
		push_error("Hamg Missilearc 应为 0.15，得 %s" % hamg_arc)
		ok = false
	else:
		print("  Hamg missilearc OK")

	var hrif_impact := CombatQuery.impact_art_for_type("hrif")
	if hrif_impact.findn("RifleImpact") < 0:
		push_error("hrif impact art 应为 RifleImpact，得 %s" % hrif_impact)
		ok = false
	else:
		print("  hrif impact_art OK (%s)" % hrif_impact)
	var hrif_spd := CombatQuery.missile_speed_for_type("hrif")
	if absf(hrif_spd - 1900.0) > 0.1:
		push_error("hrif Missilespeed 应为 1900，得 %s" % hrif_spd)
		ok = false
	else:
		print("  hrif missilespeed OK")

	var hwat_art := CombatQuery.missile_art_for_type("hwat")
	if hwat_art.findn("WaterElementalMissile") < 0:
		push_error("hwat missile art 应为 WaterElementalMissile，得 %s" % hwat_art)
		ok = false
	else:
		print("  hwat missile_art OK (%s)" % hwat_art)
	var hwat_spd := CombatQuery.missile_speed_for_type("hwat")
	if absf(hwat_spd - 1300.0) > 0.1:
		push_error("hwat Missilespeed 应为 1300，得 %s" % hwat_spd)
		ok = false
	else:
		print("  hwat missilespeed OK")
	var hwat_path := RuntimeAssets.converted_path(hwat_art)
	if not FileAccess.file_exists(hwat_path) and not FileAccess.file_exists(hwat_path.get_basename() + ".scn"):
		push_error("hwat 飞弹资产缺失：%s" % hwat_path)
		ok = false
	else:
		print("  hwat missile asset OK")

	var norm := CombatQuery.normalize_model_art(
		"Abilities\\Weapons\\FireBallMissile\\FireBallMissile.mdl"
	)
	if norm != "Abilities/Weapons/FireBallMissile/FireBallMissile.gltf":
		push_error("normalize_model_art 失败：%s" % norm)
		ok = false
	else:
		print("  normalize_model_art OK")
	return ok


func _assert_eq(got: int, want: int, label: String) -> bool:
	if got != want:
		push_error("%s: got %s want %s" % [label, got, want])
		return false
	print("  %s → %s OK" % [label, got])
	return true
