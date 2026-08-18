extends SceneTree

## 金矿踩空：depleted 只发一次；Death 单次播放。
## godot --headless --path . -s res://tests/unit/selftest_gold_mine_depleted.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_last_take_emits_depleted()
	_test_depleted_rejects_enter()
	_test_play_death_once()
	if failed == 0:
		print("selftest_gold_mine_depleted: PASS")
		quit(0)
	else:
		push_error("selftest_gold_mine_depleted: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _make_mine(gold_amount: int) -> Node3D:
	var mine := Node3D.new()
	mine.set_meta("unit_data", {"typeId": "ngol", "goldAmount": gold_amount, "owner": 12})
	root.add_child(mine)
	return mine


func _test_last_take_emits_depleted() -> void:
	var mine := _make_mine(10)
	var peasant := Node3D.new()
	root.add_child(peasant)
	var rt := GoldMineRuntime.ensure(mine)
	if rt == null:
		_fail("ensure GoldMineRuntime 失败")
		mine.queue_free()
		peasant.queue_free()
		return
	var hits := [0]
	rt.depleted.connect(func() -> void: hits[0] = int(hits[0]) + 1)
	rt.enqueue(peasant)
	if not rt.try_enter(peasant):
		_fail("有储量时应能进矿")
	var taken := rt.exit_mine(peasant, 10)
	if taken != 10:
		_fail("末次应掏走 10，实际 %d" % taken)
	if int(hits[0]) != 1:
		_fail("depleted 应发 1 次，实际 %d" % int(hits[0]))
	if not rt.is_depleted():
		_fail("掏空后 is_depleted 应为 true")
	rt.exit_mine(peasant, 10)
	if int(hits[0]) != 1:
		_fail("depleted 不得重复发送")
	mine.queue_free()
	peasant.queue_free()


func _test_depleted_rejects_enter() -> void:
	var mine := _make_mine(0)
	var peasant := Node3D.new()
	root.add_child(peasant)
	var rt := GoldMineRuntime.ensure(mine)
	if rt == null:
		_fail("ensure 空矿失败")
		mine.queue_free()
		peasant.queue_free()
		return
	rt.enqueue(peasant)
	if rt.try_enter(peasant):
		_fail("空矿不应进矿")
	mine.queue_free()
	peasant.queue_free()


func _test_play_death_once() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var ap := AnimationPlayer.new()
	host.add_child(ap)
	var anim := Animation.new()
	anim.length = 0.4
	var lib := AnimationLibrary.new()
	lib.add_animation("Death", anim)
	ap.add_animation_library("", lib)
	var played: Dictionary = BuildingVisual.play_death(null, host, "ngol")
	if not bool(played.get("ok", false)):
		_fail("play_death 应成功")
		host.queue_free()
		return
	if not is_equal_approx(float(played.get("duration", 0.0)), 0.4):
		_fail("Death 时长应为 0.4")
	if str(ap.current_animation) != "Death":
		_fail("应在播 Death，实际 %s" % str(ap.current_animation))
	var clip := ap.get_animation("Death")
	if clip == null or clip.loop_mode != Animation.LOOP_NONE:
		_fail("Death 应为 LOOP_NONE")
	host.queue_free()
