extends SceneTree

## F9 顶盾：Adef DataA/DataC、开关移速、穿刺承受。
## godot --headless --path . -s res://tests/unit/selftest_defend.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_adef_data()
	_test_controller_toggle()
	_test_pierce_idle()
	if failed == 0:
		print("selftest_defend: PASS")
		quit(0)
	else:
		push_error("selftest_defend: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _adef() -> AbilityDataDef:
	var store := root.get_node_or_null("Wc3DefStore")
	if store == null:
		return null
	store.ensure_table(AbilityDataDef.TABLE_NAME)
	return store.get_row(AbilityDataDef.TABLE_NAME, "Adef") as AbilityDataDef


func _test_adef_data() -> void:
	var ab := _adef()
	if ab == null:
		_fail("Adef 行应能从 AbilityData 读到")
		return
	if not is_equal_approx(ab.data_a1, 0.3) or not is_equal_approx(ab.data_c1, 0.3):
		_fail("Adef DataA/C 应为 0.3，实际 %s / %s" % [ab.data_a1, ab.data_c1])
		return
	print("  adef_data OK")


func _test_controller_toggle() -> void:
	var dc := DefendController.new()
	if not is_equal_approx(dc.speed_mul(), 1.0):
		_fail("关闭顶盾时移速倍率应为 1")
		dc.free()
		return
	dc.set_active(true)
	if not dc.is_active():
		_fail("set_active(true) 后应开启")
		dc.free()
		return
	if not is_equal_approx(dc.speed_mul(), 0.7):
		_fail("开启顶盾移速应为 ×0.7，实际 %s" % dc.speed_mul())
		dc.free()
		return
	if not is_equal_approx(dc.data_pierce_taken(), 0.3):
		_fail("穿刺承受应为 0.3，实际 %s" % dc.data_pierce_taken())
		dc.free()
		return
	dc.set_active(false)
	if dc.is_active() or not is_equal_approx(dc.speed_mul(), 1.0):
		_fail("关闭后应恢复移速 1")
		dc.free()
		return
	dc.free()
	print("  controller_toggle OK")


func _test_pierce_idle() -> void:
	if not is_equal_approx(DefendController.pierce_taken_factor(null), 1.0):
		_fail("无单位时穿刺系数应为 1")
		return
	print("  pierce_idle OK")
