extends SceneTree

## UnitAI：Profile 门闩、睡眠挡索敌、U1 try_engage、U4 leash 归巢。
## godot --headless --path . -s res://tests/unit/selftest_unit_ai.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_profile_gates()
	_test_sleep_blocks_acquire()
	_test_try_engage()
	_test_player_occupied_blocks_engage()
	_test_leash_return()
	_test_target_lost_return()
	if failed == 0:
		print("selftest_unit_ai: PASS")
		quit(0)
	else:
		push_error("selftest_unit_ai: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


## 不继承 AttackController，避免 -s 时战斗脚本编译序问题。
class FakeAttack extends Node:
	var start_count: int = 0
	var cancel_count: int = 0
	var last_target: Node3D = null
	var _active: bool = false

	func start_attack(target: Node3D) -> bool:
		start_count += 1
		last_target = target
		_active = true
		return true

	func cancel() -> void:
		cancel_count += 1
		_active = false
		last_target = null

	func get_mode() -> int:
		return 1 ## AttackController.Mode.ATTACK

	func get_target() -> Node3D:
		return last_target

	func is_active() -> bool:
		return _active


class FakeNav extends Node:
	var go_count: int = 0
	var last_goal: Vector2 = Vector2.INF
	var moving: bool = false

	func go_to_wc3(goal: Vector2) -> bool:
		go_count += 1
		last_goal = goal
		moving = true
		return true

	func is_moving() -> bool:
		return moving

	func stop() -> void:
		moving = false


func _test_profile_gates() -> void:
	var ai := UnitAI.new()
	ai.set_profile(UnitAI.Profile.PASSIVE)
	if ai.wants_retaliate() or ai.wants_idle_acquire():
		_fail("PASSIVE 不应反击/索敌")
		ai.free()
		return
	ai.set_profile(UnitAI.Profile.CAMP_CREEP)
	if not ai.wants_retaliate() or not ai.wants_idle_acquire():
		_fail("CAMP_CREEP 应反击+索敌")
		ai.free()
		return
	ai.free()
	print("  profile_gates OK")


func _test_sleep_blocks_acquire() -> void:
	var ai := UnitAI.new()
	ai.set_profile(UnitAI.Profile.CAMP_CREEP)
	ai.set_asleep(true)
	if ai.wants_idle_acquire():
		_fail("睡觉时不应 idle 索敌")
		ai.free()
		return
	if not ai.wants_retaliate():
		_fail("睡觉时仍应允许反击门闩（由 try_wake 叫醒）")
		ai.free()
		return
	ai.set_asleep(false)
	if not ai.wants_idle_acquire():
		_fail("醒来后应恢复索敌")
		ai.free()
		return
	ai.free()
	print("  sleep_blocks_acquire OK")


func _make_pair() -> Array:
	var body := Node3D.new()
	body.name = "Creep"
	body.set_meta("unit_data", {"typeId": "hfoo", "owner": 12})
	body.set_meta("life", 100.0)
	body.set_meta("max_life", 100.0)
	root.add_child(body)
	WorldMembership.enter(body)

	var attacker := Node3D.new()
	attacker.name = "Footman"
	attacker.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	attacker.set_meta("life", 100.0)
	root.add_child(attacker)
	WorldMembership.enter(attacker)

	var fake := FakeAttack.new()
	fake.name = "AttackController"
	body.add_child(fake)

	var ai := UnitAI.new()
	ai.name = UnitAI.NODE_NAME
	body.add_child(ai)
	ai.set_profile(UnitAI.Profile.CAMP_CREEP)
	return [body, attacker, fake, ai]


func _test_try_engage() -> void:
	var pair: Array = _make_pair()
	var body: Node3D = pair[0]
	var attacker: Node3D = pair[1]
	var fake: FakeAttack = pair[2]
	var ai: UnitAI = pair[3]
	ai.configure(func() -> bool: return false, func(_u: Node3D) -> Node: return fake)

	if not ai.try_engage(attacker):
		_fail("try_engage 应成功")
	elif fake.start_count != 1 or fake.last_target != attacker:
		_fail("应对目标 start_attack，实际 count=%d" % fake.start_count)
	elif not ai.is_engaged():
		_fail("发 Attack 后应 ENGAGED")
	else:
		print("  try_engage OK")

	body.queue_free()
	attacker.queue_free()


func _test_player_occupied_blocks_engage() -> void:
	var pair: Array = _make_pair()
	var body: Node3D = pair[0]
	var attacker: Node3D = pair[1]
	var fake: FakeAttack = pair[2]
	var ai: UnitAI = pair[3]
	ai.configure(func() -> bool: return true, func(_u: Node3D) -> Node: return fake)

	if ai.try_engage(attacker):
		_fail("玩家占用时 try_engage 应失败")
	elif fake.start_count != 0:
		_fail("玩家占用时不应 start_attack")
	else:
		print("  player_occupied_blocks_engage OK")

	body.queue_free()
	attacker.queue_free()


func _test_leash_return() -> void:
	var pair: Array = _make_pair()
	var body: Node3D = pair[0]
	var attacker: Node3D = pair[1]
	var fake: FakeAttack = pair[2]
	var ai: UnitAI = pair[3]
	var nav := FakeNav.new()
	nav.name = "UnitNavigator"
	body.add_child(nav)

	ai.home_wc3 = Vector2.ZERO
	ai.leash_wc3 = 100.0
	body.global_position = Wc3Coords.wc3_xy_to_godot(500.0, 0.0)
	ai.configure(
		func() -> bool: return false,
		func(_u: Node3D) -> Node: return fake,
		Callable(),
		Callable(),
		func(_u: Node3D) -> Node: return nav
	)

	if not ai.is_beyond_leash():
		_fail("远离锚点应判定超 leash")
		body.queue_free()
		attacker.queue_free()
		return
	if not ai.try_engage(attacker):
		_fail("leash 测试：先要能接战")
		body.queue_free()
		attacker.queue_free()
		return

	ai._process(0.0)
	if ai.get_state() != UnitAI.State.RETURNING:
		_fail("超 leash 后应 RETURNING，实际 state=%d" % ai.get_state())
	elif fake.cancel_count < 1:
		_fail("归巢应 cancel Attack")
	elif nav.go_count < 1 or nav.last_goal != Vector2.ZERO:
		_fail("归巢应 go_to_wc3(home)")
	elif ai.try_engage(attacker):
		_fail("归巢途中不应再 try_engage")
	elif ai.wants_idle_acquire():
		_fail("归巢途中不应 idle 索敌")
	else:
		body.global_position = Wc3Coords.wc3_xy_to_godot(10.0, 0.0)
		nav.moving = false
		ai._process(0.0)
		if ai.get_state() != UnitAI.State.IDLE:
			_fail("回到锚点附近应变 IDLE，实际 state=%d" % ai.get_state())
		else:
			print("  leash_return OK")

	body.queue_free()
	attacker.queue_free()


func _test_target_lost_return() -> void:
	var pair: Array = _make_pair()
	var body: Node3D = pair[0]
	var attacker: Node3D = pair[1]
	var fake: FakeAttack = pair[2]
	var ai: UnitAI = pair[3]
	var nav := FakeNav.new()
	nav.name = "UnitNavigator"
	body.add_child(nav)

	ai.home_wc3 = Vector2.ZERO
	ai.leash_wc3 = 1000.0
	body.global_position = Wc3Coords.wc3_xy_to_godot(200.0, 0.0)
	ai.configure(
		func() -> bool: return false,
		func(_u: Node3D) -> Node: return fake,
		Callable(),
		Callable(),
		func(_u: Node3D) -> Node: return nav
	)
	if not ai.try_engage(attacker):
		_fail("目标丢失测试：应先接战")
		body.queue_free()
		attacker.queue_free()
		return
	fake.cancel()
	ai.notify_combat_target_lost(attacker)
	if ai.get_state() != UnitAI.State.RETURNING:
		_fail("目标死亡后应归巢 RETURNING，实际 state=%d" % ai.get_state())
	elif nav.go_count < 1 or nav.last_goal != Vector2.ZERO:
		_fail("目标死亡后应 go_to_wc3(home)")
	else:
		print("  target_lost_return OK")

	body.queue_free()
	attacker.queue_free()
