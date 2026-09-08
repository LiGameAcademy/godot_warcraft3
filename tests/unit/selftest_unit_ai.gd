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
	_test_u3_player_stop_yields_engagement()
	_test_u3_re_engage_after_yield()
	_test_u3_leash_pulls_back_during_engagement()
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


## U3 场景 1: 野怪 ENGAGED 后玩家 Stop → 野怪让出进攻意图。
## yield_to_player 只清 _owns_engagement；AttackController.cancel 由 Router 在新命令来时负责。
func _test_u3_player_stop_yields_engagement() -> void:
	var body := Node3D.new()
	root.add_child(body)
	body.global_position = Wc3Coords.wc3_xy_to_godot(0, 0, 0.0)
	body.set_meta("unit_data", {"typeId": "nvlw", "owner": 12})
	body.set_meta("life", 100.0)
	body.set_meta("max_life", 100.0)
	WorldMembership.enter(body)
	var ai := UnitAI.new()
	ai.name = UnitAI.NODE_NAME
	body.add_child(ai)
	var fake := FakeAttack.new()
	fake.name = "AttackController"
	body.add_child(fake)
	ai.configure(
		Callable(self, "_u3_no_occupy"),
		func(_u: Node3D) -> Node: return fake,
		Callable(self, "_u3_host"),
		Callable(),
		Callable(self, "_u3_nav")
	)
	ai.set_profile(UnitAI.Profile.CAMP_CREEP)
	ai.captures_home_from_body()
	# 玩家单位
	var player_unit := Node3D.new()
	root.add_child(player_unit)
	player_unit.global_position = Wc3Coords.wc3_xy_to_godot(50, 0, 0.0)
	player_unit.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	player_unit.set_meta("life", 100.0)
	player_unit.set_meta("max_life", 100.0)
	WorldMembership.enter(player_unit)

	# 1) 野怪 engage 玩家
	if not ai.try_engage(player_unit):
		_fail("u3 野怪应能 try_engage 玩家")
	if not ai.is_engaged():
		_fail("u3 野怪应 ENGAGED")

	# 2) 玩家 Stop → yield_to_player（只清 AI 意图，不 cancel Attack）
	ai.yield_to_player()
	if ai.is_engaged():
		_fail("u3 yield 后野怪不应再 ENGAGED")
	if ai.get_state() != UnitAI.State.IDLE:
		_fail("u3 yield 后野怪应 IDLE，实际 state=%d" % ai.get_state())
	print("  u3_player_stop_yields_engagement OK")
	body.queue_free()
	player_unit.queue_free()


## U3 场景 2: yield 后野怪能再次 engage 同一目标（重新接战）。
func _test_u3_re_engage_after_yield() -> void:
	var body := Node3D.new()
	root.add_child(body)
	body.global_position = Wc3Coords.wc3_xy_to_godot(0, 0, 0.0)
	body.set_meta("unit_data", {"typeId": "nvlw", "owner": 12})
	body.set_meta("life", 100.0)
	body.set_meta("max_life", 100.0)
	WorldMembership.enter(body)
	var ai := UnitAI.new()
	ai.name = UnitAI.NODE_NAME
	body.add_child(ai)
	var fake := FakeAttack.new()
	fake.name = "AttackController"
	body.add_child(fake)
	ai.configure(
		Callable(self, "_u3_no_occupy"),
		func(_u: Node3D) -> Node: return fake,
		Callable(self, "_u3_host"),
		Callable(),
		Callable(self, "_u3_nav")
	)
	ai.set_profile(UnitAI.Profile.CAMP_CREEP)
	ai.captures_home_from_body()

	var player_unit := Node3D.new()
	root.add_child(player_unit)
	player_unit.global_position = Wc3Coords.wc3_xy_to_godot(50, 0, 0.0)
	player_unit.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	player_unit.set_meta("life", 100.0)
	player_unit.set_meta("max_life", 100.0)
	WorldMembership.enter(player_unit)

	# 1) engage → 2) yield → 3) 再次 engage
	if not ai.try_engage(player_unit):
		_fail("u3 re-engage 第一次应成功")
	ai.yield_to_player()
	if ai.is_engaged():
		_fail("u3 yield 后不应 ENGAGED")
	if not ai.try_engage(player_unit):
		_fail("u3 re-engage 第二次应成功")
	if not ai.is_engaged():
		_fail("u3 re-engage 后应 ENGAGED")
	print("  u3_re_engage_after_yield OK")
	body.queue_free()
	player_unit.queue_free()


## U3 场景 3: 野怪追出 leash → 自动停攻回 home（RETURNING）。
## 注意：is_beyond_leash() 判断**野怪自己**追出 home 半径（不是 target 远）。
func _test_u3_leash_pulls_back_during_engagement() -> void:
	var body := Node3D.new()
	root.add_child(body)
	# 出生在 (0, 0)，home 锁在 (0, 0)；先把野怪"追出去"到 1500
	body.global_position = Wc3Coords.wc3_xy_to_godot(0, 0, 0.0)
	body.set_meta("unit_data", {"typeId": "nvlw", "owner": 12})
	body.set_meta("life", 100.0)
	body.set_meta("max_life", 100.0)
	WorldMembership.enter(body)
	var ai := UnitAI.new()
	ai.name = UnitAI.NODE_NAME
	body.add_child(ai)
	var fake := FakeAttack.new()
	fake.name = "AttackController"
	body.add_child(fake)
	var nav := FakeNav.new()
	body.add_child(nav)
	ai.configure(
		Callable(self, "_u3_no_occupy"),
		func(_u: Node3D) -> Node: return fake,
		Callable(self, "_u3_host"),
		Callable(),
		func(_u: Node3D) -> Node: return nav
	)
	ai.set_profile(UnitAI.Profile.CAMP_CREEP)
	ai.captures_home_from_body()
	# home 锁在 (0, 0)；leash 默认 1000
	if ai.home_wc3 != Vector2.ZERO:
		_fail("u3 leash 拉回：home 应锁在 (0, 0)，实际 %s" % str(ai.home_wc3))

	# 把野怪本体移出 leash 半径（追到远处）
	body.global_position = Wc3Coords.wc3_xy_to_godot(1500, 0, 0.0)

	# 野怪强制 ENGAGED（绕开 _pick_target 距离判断，模拟"追出去后还在打"）
	ai._owns_engagement = true
	ai._set_state(UnitAI.State.ENGAGED)
	# 模拟一帧：tick_engaged → is_beyond_leash（1500 > 1000）→ _begin_return
	ai._process(0.016)
	if ai.get_state() != UnitAI.State.RETURNING:
		_fail("u3 leash 拉回：超 leash 应进入 RETURNING，实际 state=%d" % ai.get_state())
	if nav.go_count < 1:
		_fail("u3 leash 拉回：应 go_to_wc3(home)，go_count=%d" % nav.go_count)
	if nav.last_goal != Vector2.ZERO:
		_fail("u3 leash 拉回：目标应为 home (0,0)，实际 %s" % str(nav.last_goal))
	print("  u3_leash_pulls_back_during_engagement OK")
	body.queue_free()


## u3 helper：no player occupy
func _u3_no_occupy() -> bool:
	return false


func _u3_host() -> Node:
	return root


func _u3_nav(u: Node3D) -> Node:
	return u.get_node_or_null("UnitNavigator")
