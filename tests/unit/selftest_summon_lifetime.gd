extends SceneTree

## SummonLifetime：到期回调 / 死亡管线挂钩。
## godot --headless --path . -s res://tests/unit/selftest_summon_lifetime.gd

var failed := 0
var _kill_cb_called := false


func _summon_test_kill(u: Node3D) -> void:
	_kill_cb_called = true
	u.set_meta("life", 0.0)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_expire_calls_kill_cb()
	_test_expire_skips_dead_host()
	if failed == 0:
		print("selftest_summon_lifetime: PASS")
		quit(0)
	else:
		push_error("selftest_summon_lifetime: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_expire_calls_kill_cb() -> void:
	_kill_cb_called = false
	var body := Node3D.new()
	body.name = "hwat"
	body.set_meta("unit_data", {"typeId": "hwat", "owner": 0})
	body.set_meta("life", 100.0)
	root.add_child(body)
	var life := SummonLifetime.new()
	life.name = "SummonLifetime"
	body.add_child(life)
	life.configure(0.06, Callable(self, "_summon_test_kill"))
	life.tick(0.07)
	if not _kill_cb_called:
		_fail("SummonLifetime 到期应调用 kill_cb")
		body.queue_free()
		return
	print("  expire_kill_cb OK")
	body.queue_free()


func _test_expire_skips_dead_host() -> void:
	var kill_calls := 0
	var body := Node3D.new()
	body.name = "hwat2"
	body.set_meta("unit_data", {"typeId": "hwat", "owner": 0})
	body.set_meta("life", 0.0)
	root.add_child(body)
	var life := SummonLifetime.new()
	body.add_child(life)
	life.configure(0.04, func(_u: Node3D) -> void:
		kill_calls += 1
	)
	life.tick(0.05)
	if kill_calls != 0:
		_fail("已死亡宿主不应再次 kill，实际 %d 次" % kill_calls)
		body.queue_free()
		return
	body.queue_free()
	print("  expire_skips_dead OK")
