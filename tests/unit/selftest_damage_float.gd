extends SceneTree

## 受击飘字 Present selftest。
## godot --headless --path . -s res://tests/unit/selftest_damage_float.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_format_and_attach()
	_test_skip_not_ok()
	_test_kill_color()
	if failed == 0:
		print("selftest_damage_float: PASS")
		quit(0)
	else:
		push_error("selftest_damage_float: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_format_and_attach() -> void:
	var host := Node3D.new()
	host.name = "DummyUnit"
	root.add_child(host)
	var node := DamageFloatText.spawn(host, {
		"ok": true,
		"amount": 12.3,
		"killed": false,
	})
	if node == null or not is_instance_valid(node):
		_fail("spawn returned null")
		host.queue_free()
		return
	if node.get_parent() != host:
		_fail("float text not parented to target")
	var label := node.get_node_or_null("DamageFloatLabel") as Label3D
	if label == null:
		_fail("missing Label3D")
	elif label.text != "12.3":
		_fail("expected 12.3 got %s" % label.text)
	host.queue_free()


func _test_skip_not_ok() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var node := DamageFloatText.spawn(host, {
		"ok": false,
		"amount": 9.0,
		"killed": false,
	})
	if node != null:
		_fail("not-ok result should not spawn")
	host.queue_free()


func _test_kill_color() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var node := DamageFloatText.spawn(host, {
		"ok": true,
		"amount": 20.0,
		"killed": true,
	})
	if node == null:
		_fail("kill spawn null")
		host.queue_free()
		return
	var label := node.get_node_or_null("DamageFloatLabel") as Label3D
	if label == null:
		_fail("kill missing Label3D")
	elif label.text != "20":
		_fail("expected 20 got %s" % label.text)
	elif label.modulate != DamageFloatText.KILL_COLOR:
		_fail("kill color mismatch")
	host.queue_free()
