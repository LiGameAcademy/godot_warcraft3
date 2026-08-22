extends SceneTree

## 民兵 Amil：Duration + 形态 ID 常量；MilitiaController 武装/收回。
## godot --headless --path . -s res://tests/unit/selftest_militia.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_amil_duration()
	_test_controller_toggle_forms()
	await _test_auto_revert_timeout()
	if failed == 0:
		print("selftest_militia: PASS")
		quit(0)
	else:
		push_error("selftest_militia: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_amil_duration() -> void:
	var store := root.get_node_or_null("Wc3DefStore")
	if store == null:
		_fail("Wc3DefStore 缺失")
		return
	store.ensure_table(AbilityDataDef.TABLE_NAME)
	var ab := store.get_row(AbilityDataDef.TABLE_NAME, "Amil") as AbilityDataDef
	if ab == null:
		_fail("AbilityData 应有 Amil")
		return
	if ab.dur1 < 40.0 or ab.dur1 > 50.0:
		_fail("Amil Dur1 应约 45，实际 %s" % ab.dur1)
		return
	print("  amil_duration OK (%s)" % ab.dur1)


func _test_controller_toggle_forms() -> void:
	var applied: Array[String] = []
	var body := Node3D.new()
	body.set_meta("unit_data", {"typeId": "hpea", "owner": 0})
	root.add_child(body)

	var mc := MilitiaController.new()
	mc.name = MilitiaController.NODE_NAME
	body.add_child(mc)
	var apply := func(u: Node3D, tid: String) -> bool:
		var d: Dictionary = u.get_meta("unit_data", {}).duplicate(true)
		d["typeId"] = tid
		u.set_meta("unit_data", d)
		applied.append(tid)
		return true
	mc.configure(apply, 45.0)

	if not mc.toggle_call_to_arms():
		_fail("农民应能武装为民兵")
		body.queue_free()
		return
	if not mc.is_militia() or applied.is_empty() or applied[0] != "hmil":
		_fail("武装后 type 应为 hmil")
		body.queue_free()
		return
	if not mc.toggle_call_to_arms():
		_fail("民兵应能收回为农民")
		body.queue_free()
		return
	if mc.is_militia() or applied.size() < 2 or applied[1] != "hpea":
		_fail("收回后 type 应为 hpea")
		body.queue_free()
		return
	print("  controller_toggle_forms OK")
	body.queue_free()


func _test_auto_revert_timeout() -> void:
	var applied: Array[String] = []
	var body := Node3D.new()
	body.set_meta("unit_data", {"typeId": "hpea", "owner": 0})
	root.add_child(body)
	var mc := MilitiaController.new()
	mc.name = MilitiaController.NODE_NAME
	body.add_child(mc)
	var apply := func(u: Node3D, tid: String) -> bool:
		var d: Dictionary = u.get_meta("unit_data", {}).duplicate(true)
		d["typeId"] = tid
		u.set_meta("unit_data", d)
		applied.append(tid)
		return true
	mc.configure(apply, 0.08)
	if not mc.toggle_call_to_arms():
		_fail("武装应成功")
		body.queue_free()
		return
	if str(body.get_meta("unit_data", {}).get("typeId", "")) != "hmil":
		_fail("武装后应为 hmil")
		body.queue_free()
		return
	await create_timer(0.15).timeout
	if mc.is_militia():
		_fail("0.08s 后应自动收回为农民")
		body.queue_free()
		return
	if str(body.get_meta("unit_data", {}).get("typeId", "")) != "hpea":
		_fail("超时后 typeId 应为 hpea")
		body.queue_free()
		return
	if applied.size() < 2 or applied[1] != "hpea":
		_fail("应记录 hmil→hpea 形态切换")
		body.queue_free()
		return
	print("  auto_revert_timeout OK")
	body.queue_free()
