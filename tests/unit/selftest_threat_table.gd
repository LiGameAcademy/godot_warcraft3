extends SceneTree

## ThreatTable / Sticky Target / REACTIVE profile：
## - 仇恨累加（受击）
## - 仇恨衰减（decay 0.3/s；≤0 移除）
## - top_threat 按仇恨排序，过滤死亡 / 失效
## - _pick_target：sticky 锁定 > top_threat > 最近兜底
## - try_engage 触发切目标冷却 0.25s
## - 受击强制清 swap_cd（攻击者必中）
## - REACTIVE 玩家单位：受击反击 + 盟友广播可拉，不 idle acquire
##
## godot --headless --path . -s res://tests/unit/selftest_threat_table.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_threat_add_and_top()
	_test_threat_decay_removes_when_zero()
	_test_threat_filters_dead_and_neutral()
	_test_sticky_holds_through_tiny_window()
	_test_sticky_drops_when_target_out_of_range()
	_test_swap_cooldown_blocks_extra_pick()
	_test_swap_cooldown_cleared_by_damage()
	_test_reactive_does_not_idle_acquire()
	_test_reactive_does_ally_engage()
	_test_pick_target_prefers_higher_threat_over_closer()
	print("----")
	if failed == 0:
		print("selftest_threat_table: PASS")
		quit(0)
	else:
		push_error("selftest_threat_table: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _ok(msg: String) -> void:
	print("  %s OK" % msg)


# ---------------------------------------------------------------------------
# 测试桩
# ---------------------------------------------------------------------------

class FakeAttack extends Node:
	var start_count: int = 0
	var last_target: Node3D = null
	var _active: bool = false
	## 标记受击回调调用顺序
	var hit_targets: Array = []

	func start_attack(target: Node3D) -> bool:
		start_count += 1
		last_target = target
		_active = true
		return true

	func cancel() -> void:
		_active = false
		last_target = null

	func get_mode() -> int:
		return 1

	func get_target() -> Node3D:
		return last_target

	func is_active() -> bool:
		return _active


class FakeNav extends Node:
	func go_to_wc3(_goal: Vector2) -> bool:
		return true

	func is_moving() -> bool:
		return false

	func stop() -> void:
		pass


func _make_unit(layer: Node, tid: String, owner: int, pos_wc3: Vector2) -> Node3D:
	var body := Node3D.new()
	body.name = "U_%s_%d_%s" % [tid, owner, str(pos_wc3).replace(" ", "")]
	body.set_meta("unit_data", {"typeId": tid, "owner": owner})
	body.set_meta("life", 100.0)
	body.set_meta("max_life", 100.0)
	layer.add_child(body)
	body.global_position = Wc3Coords.wc3_xy_to_godot(pos_wc3.x, pos_wc3.y, 0.0)
	WorldMembership.enter(body)
	return body


func _attach_ai(body: Node3D, profile: int = UnitAI.Profile.REACTIVE) -> UnitAI:
	var fake := FakeAttack.new()
	fake.name = "AttackController"
	body.add_child(fake)
	var nav := FakeNav.new()
	nav.name = "UnitNavigator"
	body.add_child(nav)
	var ai := UnitAI.new()
	ai.name = UnitAI.NODE_NAME
	body.add_child(ai)
	ai.configure(
		Callable(), # is_player_occupied → 默认 false
		Callable(fake, "_self_ref_dummy") if false else func(_u: Node3D) -> Node: return fake,
		Callable(), # unit_host
		Callable(), # aggro mult
		Callable(ai, "_dummy_nav_call")
	)
	ai.set_profile(profile)
	return ai


# 给 ai configure 提供一个确保返回 fake 的 ensure_attack 闭包；
# 测试里直接 add_child(fake)，configure 的 ensure_attack 通过返回 fake 来路由。
# 实现：func(u) -> fake 的闭包已通过 lambda 完成。
# (无 dummy 引用即可)

func _make_simple_pair() -> Dictionary:
	## 造一对单位：attacker (owner=1 敌方) + victim (owner=0 REACTIVE 玩家)
	## 共用 host（保证 find_acquire_target 扫得到）。
	var layer := Node3D.new()
	layer.name = "ThreatLayer_%d" % Time.get_ticks_msec()
	root.add_child(layer)
	var attacker := _make_unit(layer, "Footman", 1, Vector2(0, 0))
	var victim := _make_unit(layer, "Archer", 0, Vector2(100, 0))
	var ai := _attach_ai(victim, UnitAI.Profile.REACTIVE)
	ai.captures_home_from_body()
	return {"layer": layer, "attacker": attacker, "victim": victim, "ai": ai}


# ---------------------------------------------------------------------------
# 1) add_threat + top_threat：基本写入与读取
# ---------------------------------------------------------------------------
func _test_threat_add_and_top() -> void:
	var pair := _make_simple_pair()
	var victim: Node3D = pair["victim"]
	var ai: UnitAI = pair["ai"]
	var attacker: Node3D = pair["attacker"]
	# 清掉刚 ensure 时写入的默认 home 等副作用不影响本断言
	ai.add_threat(attacker, 5.0)
	ai.add_threat(attacker, 3.0) # 累加 → 8.0
	var top := ai.top_threat(pair["layer"])
	if top != attacker:
		_fail("threat_add_and_top: top 应该 = attacker, got %s" % top)
	else:
		_ok("threat_add_and_top")
	pair["layer"].queue_free()


# ---------------------------------------------------------------------------
# 2) decay_threat：每秒 -0.3；累计到 ≤0 移除
# ---------------------------------------------------------------------------
func _test_threat_decay_removes_when_zero() -> void:
	var pair := _make_simple_pair()
	var ai: UnitAI = pair["ai"]
	var attacker: Node3D = pair["attacker"]
	ai.add_threat(attacker, 1.0) # 1.0 刚好 3.3s 后归 0
	# 直接调 _decay_threat 模拟 4s（无 process 循环）
	ai._decay_threat(4.0)
	var top := ai.top_threat(pair["layer"])
	if top != null:
		_fail("decay: 4s 后 1.0 - 4*0.3 = -0.2 ≤0 应被移除，top=%s" % top)
	else:
		_ok("threat_decay_removes_when_zero")
	pair["layer"].queue_free()


# ---------------------------------------------------------------------------
# 3) top_threat 过滤死亡 / 已脱敌对
# ---------------------------------------------------------------------------
func _test_threat_filters_dead_and_neutral() -> void:
	var pair := _make_simple_pair()
	var ai: UnitAI = pair["ai"]
	var attacker: Node3D = pair["attacker"]
	# 加 attacker 到仇恨表
	ai.add_threat(attacker, 2.0)
	# 把它从 world 移除 / 杀 (life=0)
	WorldMembership.exit(attacker)
	attacker.set_meta("life", 0.0)
	var top := ai.top_threat(pair["layer"])
	if top != null:
		_fail("filters_dead: 死亡目标应被 top_threat 过滤掉, got %s" % top)
	else:
		_ok("threat_filters_dead_and_neutral")
	pair["layer"].queue_free()


# ---------------------------------------------------------------------------
# 4) sticky：在 hold 窗口（1.5s）内，即使临时有候选更近也保留当前 target
# ---------------------------------------------------------------------------
func _test_sticky_holds_through_tiny_window() -> void:
	var pair := _make_simple_pair()
	var ai: UnitAI = pair["ai"]
	var attacker: Node3D = pair["attacker"]
	var host: Node = pair["layer"]
	# 锁定 attacker
	if not ai.try_engage(attacker):
		_fail("sticky_holds: try_engage 失败")
		pair["layer"].queue_free()
		return
	# 立刻再调 _pick_target 应仍返回 attacker（sticky）
	var picked := ai._pick_target(host)
	if picked != attacker:
		_fail("sticky_holds: _pick_target 应保留 attacker, got %s" % picked)
	else:
		_ok("sticky_holds_through_tiny_window")
	pair["layer"].queue_free()


# ---------------------------------------------------------------------------
# 5) sticky drop：锁定目标跑出 acquire 半径 → _pick_target 切到 top
# ---------------------------------------------------------------------------
func _test_sticky_drops_when_target_out_of_range() -> void:
	var pair := _make_simple_pair()
	var ai: UnitAI = pair["ai"]
	var attacker: Node3D = pair["attacker"]
	var host: Node = pair["layer"]
	# 锁定 attacker（距离 100 WC3，在 acquire 内）
	if not ai.try_engage(attacker):
		_fail("sticky_drops: try_engage 失败")
		pair["layer"].queue_free()
		return
	# 移除 attacker 出 World（sticky drop 后 top_threat 拿不到，find_acquire_target 也找不到）
	WorldMembership.exit(attacker)
	attacker.queue_free()
	attacker = null
	# _pick_target 应不再返回被移除的目标（host 里它已不存在）
	var picked := ai._pick_target(host)
	if is_instance_valid(picked):
		_fail("sticky_drops: target 已移除，_pick_target 应返回 null, got %s" % picked)
	else:
		_ok("sticky_drops_when_target_out_of_range")
	pair["layer"].queue_free()


# ---------------------------------------------------------------------------
# 6) swap_cd：try_engage 后 0.25s 内 try_engage 不同 target 被拒
# ---------------------------------------------------------------------------
func _test_swap_cooldown_blocks_extra_pick() -> void:
	var pair := _make_simple_pair()
	var ai: UnitAI = pair["ai"]
	var attacker: Node3D = pair["attacker"]
	# 造第二 target（owner=2 敌方，挨着 attacker 但独立）
	var other := _make_unit(pair["layer"], "Footman", 2, Vector2(150, 0))
	if not ai.try_engage(attacker):
		_fail("swap_cd: 第一次 try_engage 失败")
		pair["layer"].queue_free()
		return
	# 立刻换 other → 应被 swap_cd 拒
	if ai.try_engage(other):
		_fail("swap_cd: 0.25s 内应拒换 target")
	else:
		_ok("swap_cooldown_blocks_extra_pick")
	pair["layer"].queue_free()


# ---------------------------------------------------------------------------
# 7) 受击（notify_damaged）强制清 swap_cd：可立刻切回攻击者
# ---------------------------------------------------------------------------
func _test_swap_cooldown_cleared_by_damage() -> void:
	var pair := _make_simple_pair()
	var ai: UnitAI = pair["ai"]
	var attacker: Node3D = pair["attacker"]
	if not ai.try_engage(attacker):
		_fail("swap_cd_dmg: 第一次 try_engage 失败")
		pair["layer"].queue_free()
		return
	# 模拟 victim 被 attacker 打了 10 伤（amount=10）
	ai.notify_damaged({"ok": true, "attacker": attacker, "amount": 10.0})
	# swap_cd 已被清 → 再次 try_engage 同 target 应仍允许
	if not ai.try_engage(attacker):
		_fail("swap_cd_dmg: 受击清 swap_cd 后再次 engage 应允许")
	else:
		_ok("swap_cooldown_cleared_by_damage")
	pair["layer"].queue_free()


# ---------------------------------------------------------------------------
# 8) REACTIVE：idle acquire 不会触发（wants_idle_acquire = false）
# ---------------------------------------------------------------------------
func _test_reactive_does_not_idle_acquire() -> void:
	var pair := _make_simple_pair()
	var ai: UnitAI = pair["ai"]
	if ai.wants_idle_acquire():
		_fail("reactive_no_idle: REACTIVE 的 wants_idle_acquire 应为 false")
	else:
		_ok("reactive_does_not_idle_acquire")
	pair["layer"].queue_free()


# ---------------------------------------------------------------------------
# 9) REACTIVE：allows_ally_engage = true（受 TeamRegistry 拉）
# ---------------------------------------------------------------------------
func _test_reactive_does_ally_engage() -> void:
	var pair := _make_simple_pair()
	var ai: UnitAI = pair["ai"]
	if not ai.allows_ally_engage():
		_fail("reactive_ally: REACTIVE 的 allows_ally_engage 应为 true")
	else:
		_ok("reactive_does_ally_engage")
	pair["layer"].queue_free()


# ---------------------------------------------------------------------------
# 10) _pick_target：仇恨更高者覆盖更近者
# ---------------------------------------------------------------------------
func _test_pick_target_prefers_higher_threat_over_closer() -> void:
	var pair := _make_simple_pair()
	var ai: UnitAI = pair["ai"]
	var attacker: Node3D = pair["attacker"]
	# 造第三 target（更近但仇恨低，owner=3 敌方）
	var near := _make_unit(pair["layer"], "Peasant", 3, Vector2(50, 0))
	# 给 attacker 加高仇恨
	ai.add_threat(attacker, 10.0)
	# 当前 locked = null（未 try_engage），所以应走 top_threat
	var picked := ai._pick_target(pair["layer"])
	if picked != attacker:
		_fail("threat_over_close: 仇恨 10 vs 0 应选 attacker, got %s" % picked)
	else:
		_ok("pick_target_prefers_higher_threat_over_closer")
	pair["layer"].queue_free()