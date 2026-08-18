extends SceneTree

## C2：weapTp 投送分类 + 弹道飞行时间。
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

	if ok:
		print("selftest_c_combat_projectile: PASS")
		quit(0)
	else:
		push_error("selftest_c_combat_projectile: FAIL")
		quit(1)


func _assert_eq(got: int, want: int, label: String) -> bool:
	if got != want:
		push_error("%s: got %s want %s" % [label, got, want])
		return false
	print("  %s → %s OK" % [label, got])
	return true
