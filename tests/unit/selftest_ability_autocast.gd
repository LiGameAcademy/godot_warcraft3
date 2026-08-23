extends SceneTree

## 自动施法：UnitAbilities.auto + Unart + 切换。
## godot --headless --path . -s res://tests/unit/selftest_ability_autocast.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_supports()
	_test_defaults()
	_test_toggle()
	if failed == 0:
		print("selftest_ability_autocast: PASS")
		quit(0)
	else:
		push_error("selftest_ability_autocast: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_supports() -> void:
	for id in ["Ahea", "Ainf", "Aslo"]:
		if not AbilityAutoCast.supports(id):
			_fail("%s 应支持自动施法切换（有 Unart）" % id)
			return
	if AbilityAutoCast.supports("AHwe"):
		_fail("AHwe 不应支持 autocast")
		return
	print("  supports OK")


func _test_defaults() -> void:
	var priest := Node3D.new()
	priest.set_meta("unit_data", {"typeId": "hmpr", "owner": 0})
	root.add_child(priest)
	AbilityAutoCast.ensure_defaults(priest)
	if not AbilityAutoCast.supports("Ahea"):
		print("  defaults SKIP (catalog)")
		priest.queue_free()
		return
	if not AbilityAutoCast.is_enabled(priest, "Ahea"):
		_fail("hmpr 默认应开启 Ahea 自动施法")
		return
	if AbilityAutoCast.is_enabled(priest, "Ainf"):
		_fail("hmpr 默认应关闭 Ainf 自动施法")
		return
	var sorc := Node3D.new()
	sorc.set_meta("unit_data", {"typeId": "hsor", "owner": 0})
	root.add_child(sorc)
	AbilityAutoCast.ensure_defaults(sorc)
	if not AbilityAutoCast.is_enabled(sorc, "Aslo"):
		_fail("hsor 默认应开启 Aslo 自动施法")
		return
	priest.queue_free()
	sorc.queue_free()
	print("  defaults OK")


func _test_toggle() -> void:
	var u := Node3D.new()
	u.set_meta("unit_data", {"typeId": "hmpr", "owner": 0})
	root.add_child(u)
	AbilityAutoCast.ensure_defaults(u)
	var was := AbilityAutoCast.is_enabled(u, "Ainf")
	AbilityAutoCast.toggle(u, "Ainf")
	if AbilityAutoCast.is_enabled(u, "Ainf") == was:
		_fail("toggle 应改变 Ainf 状态")
		return
	# 开启 Ainf 时应关掉默认的 Ahea（互斥）
	if AbilityAutoCast.is_enabled(u, "Ainf") and AbilityAutoCast.is_enabled(u, "Ahea"):
		_fail("开启 Ainf 后 Ahea 应关闭（互斥）")
		return
	AbilityAutoCast.set_enabled(u, "Ahea", true)
	if not AbilityAutoCast.is_enabled(u, "Ahea"):
		_fail("应能开启 Ahea")
		return
	if AbilityAutoCast.is_enabled(u, "Ainf"):
		_fail("开启 Ahea 后 Ainf 应关闭（互斥）")
		return
	AbilityAutoCast.set_enabled(u, "Ahea", false)
	if AbilityAutoCast.is_enabled(u, "Ahea") or AbilityAutoCast.is_enabled(u, "Ainf"):
		_fail("关闭后应可全关")
		return
	u.queue_free()
	print("  toggle OK")
