extends SceneTree

## TeamRegistry：玩家 team / 中立 camp 聚类、home 重算、盟友挨打参战 / 闲站不参战。
## godot --headless --path . -s res://tests/unit/selftest_team_registry.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_player_team_by_owner()
	_test_neutral_cluster_and_home()
	_test_home_locked_after_death()
	_test_player_ally_engage_when_source_engaged()
	_test_player_idle_does_not_ally_engage()
	_test_camp_full_alert_when_source_attacked()
	_test_camp_radius_does_not_limit_full_alert()
	_test_player_team_uses_ally_radius()
	_test_home_bound_after_cluster()
	_test_new_spawn_joins_existing_camp()
	_test_home_does_not_drift_after_death()
	print("----")
	if failed == 0:
		print("selftest_team_registry: PASS")
		quit(0)
	else:
		push_error("selftest_team_registry: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


## 假 AttackController：仅记 start_attack 次数。
class FakeAttack extends Node:
	var start_count: int = 0
	var last_target: Node3D = null
	var _active: bool = false

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


func _make_unit(tid: String, owner: int, pos_wc3: Vector2) -> Node3D:
	return _make_unit_in_layer(root, tid, owner, pos_wc3)


func _make_unit_in_layer(layer: Node, tid: String, owner: int, pos_wc3: Vector2) -> Node3D:
	var body := Node3D.new()
	body.name = "U_%s_%d_%s" % [tid, owner, str(pos_wc3).replace(" ", "")]
	body.set_meta("unit_data", {"typeId": tid, "owner": owner})
	body.set_meta("life", 100.0)
	body.set_meta("max_life", 100.0)
	layer.add_child(body)
	# 入树后再设置全局坐标
	body.global_position = Wc3Coords.wc3_xy_to_godot(pos_wc3.x, pos_wc3.y, 0.0)
	WorldMembership.enter(body)
	return body


func _attach_ai(body: Node3D) -> UnitAI:
	var fake := FakeAttack.new()
	fake.name = "AttackController"
	body.add_child(fake)
	var ai := UnitAI.new()
	ai.name = UnitAI.NODE_NAME
	body.add_child(ai)
	var nav := FakeNav.new()
	nav.name = "UnitNavigator"
	body.add_child(nav)
	ai.configure(
		func() -> bool: return false,
		func(_u: Node3D) -> Node: return fake,
		Callable(),
		Callable(),
		func(_u: Node3D) -> Node: return nav
	)
	return ai


func _test_player_team_by_owner() -> void:
	var p0a := _make_unit("hfoo", 0, Vector2(1000, 1000))
	var p0b := _make_unit("hfoo", 0, Vector2(1100, 1000))
	var p1a := _make_unit("hfoo", 1, Vector2(2000, 1000))

	var reg := TeamRegistry.attach(root)
	reg.cluster_and_bind(root)

	var ga := reg.group_of(p0a)
	var gb := reg.group_of(p0b)
	var gc := reg.group_of(p1a)

	if ga != "p0":
		_fail("player 0 应得 team p0，实际 %s" % ga)
	if gb != "p0":
		_fail("player 0 第二个单位应同队 p0")
	if gc != "p1":
		_fail("player 1 应得 team p1，实际 %s" % gc)
	if reg.player_members_of("p0").size() != 2:
		_fail("p0 应有 2 个成员")
	if reg.player_members_of("p1").size() != 1:
		_fail("p1 应有 1 个成员")
	print("  player_team_by_owner OK")
	for u in [p0a, p0b, p1a]:
		u.queue_free()


func _test_neutral_cluster_and_home() -> void:
	var a := _make_unit("nvlw", 12, Vector2(0, 0))
	var b := _make_unit("nvlw", 12, Vector2(400, 0))
	var c := _make_unit("nvlw", 12, Vector2(1500, 0)) # 距 a/b 远，应单独成营

	var reg := TeamRegistry.attach(root)
	reg.cluster_and_bind(root)

	var ga := reg.group_of(a)
	var gb := reg.group_of(b)
	var gc := reg.group_of(c)

	if not ga.begins_with("c"):
		_fail("中立野怪应得 camp_id，实际 %s" % ga)
	if ga != gb:
		_fail("近距离野怪应同营地，实际 %s vs %s" % [ga, gb])
	if ga == gc:
		_fail("远距离野怪应不同营地")
	# 营地 home = 成员中心点
	var home := reg.home_of(ga)
	if home == Vector2.INF:
		_fail("营地 home 不应 INF")
	# a(0,0) b(400,0) 中心 (200,0)
	if absf(home.x - 200.0) > 1.0 or absf(home.y) > 1.0:
		_fail("营地 home 应接近 (200,0)，实际 %s" % str(home))
	print("  neutral_cluster_and_home OK")
	for u in [a, b, c]:
		u.queue_free()


func _test_home_locked_after_death() -> void:
	# 隔离环境：单挂一层 Node3D，避免其它测试残留污染
	var reg := TeamRegistry.attach(root)
	reg._reset()
	var layer := Node3D.new()
	layer.name = "TestLayer_Death"
	root.add_child(layer)
	var a := _make_unit_in_layer(layer, "nvlw", 12, Vector2(0, 0))
	var b := _make_unit_in_layer(layer, "nvlw", 12, Vector2(400, 0))

	reg.cluster_and_bind(layer)
	var gid_a := reg.group_of(a)
	var home_before := reg.home_of(gid_a)
	if absf(home_before.x - 200.0) > 1.0:
		_fail("初始 home 应 ≈ (200,0)，实际 %s" % str(home_before))

	# a 死亡 / 离场
	WorldMembership.exit(a)
	reg.on_unit_gone(a)

	if reg.group_of(a) != "":
		_fail("离场后 a 不应在 group")
	var home_after := reg.home_of(gid_a)
	if home_after == Vector2.INF:
		_fail("b 仍在场，营地 home 不应 INF")
	# home 锁定：成员死亡不重算（WC3 原作语义）
	if absf(home_after.x - 200.0) > 1.0 or absf(home_after.y) > 1.0:
		_fail("成员死亡后 home 应锁定在初始 (200,0)，不允许漂移到 b 单点 (400,0)，实际 %s" % str(home_after))
	print("  home_locked_after_death OK")
	layer.queue_free()


func _test_player_ally_engage_when_source_engaged() -> void:
	var p0a := _make_unit("hfoo", 0, Vector2(0, 0))
	var p0b := _make_unit("hfoo", 0, Vector2(200, 0)) # 在 ally 半径内
	var creep := _make_unit("nvlw", 12, Vector2(50, 0))
	var ai_a: UnitAI = _attach_ai(p0a)
	var ai_b: UnitAI = _attach_ai(p0b)
	ai_a.set_profile(UnitAI.Profile.TEAM_PLAYER)
	ai_b.set_profile(UnitAI.Profile.TEAM_PLAYER)

	var reg := TeamRegistry.attach(root)
	reg.cluster_and_bind(root)
	# 把 creep 也接进营地（cluster_and_bind 之前是中立未挂 AI；现在 attach_ai 后再 cluster）
	# 但 cluster_and_bind 已跑过，需要手工 bind creep 进已有营地——直接做：
	# 简化：creep 单独成一营；用 owner_distinguish 模式，p0a/creep 不是同 team → 走 fallback notify。
	# 这里改用更直接的路径：把 p0a、N1 都打成 ENGAGED 后，再让玩家单位 set_attack creep。
	# 1) creep 先 try_engage p0a → p0a 受击反击，ai_a ENGAGED
	var creep_ai: UnitAI = _attach_ai(creep)
	creep_ai.set_profile(UnitAI.Profile.CAMP_CREEP)
	if not creep_ai.try_engage(p0a):
		_fail("creep 应能 try_engage p0a")
	# 注：p0a 受击反击走 notify_damaged，这里我们手动调一下
	var dmg := {"ok": true, "attacker": creep}
	ai_a.notify_damaged(dmg)
	if not ai_a.is_engaged():
		_fail("p0a 受击反击后应 ENGAGED")

	# 现在触发盟友广播：源是 p0a（已 ENGAGED），attacker = creep
	var joined := reg.notify_ally_engaged(p0a, creep, TeamRegistry.ALLY_ALERT_RADIUS_WC3)
	if joined < 1:
		_fail("玩家盟友挨打广播应至少拉 1 人，实际 %d" % joined)
	if not ai_b.is_engaged():
		_fail("p0b 应被广播拉去打 creep")
	print("  player_ally_engage_when_source_engaged OK")
	for u in [p0a, p0b, creep]:
		u.queue_free()


func _test_player_idle_does_not_ally_engage() -> void:
	var p0a := _make_unit("hfoo", 0, Vector2(0, 0))
	var p0b := _make_unit("hfoo", 0, Vector2(200, 0))
	var creep := _make_unit("nvlw", 12, Vector2(50, 0))
	_attach_ai(p0a).set_profile(UnitAI.Profile.TEAM_PLAYER)
	var ai_b: UnitAI = _attach_ai(p0b)
	ai_b.set_profile(UnitAI.Profile.TEAM_PLAYER)

	var reg := TeamRegistry.attach(root)
	reg.cluster_and_bind(root)
	# p0a 是 IDLE，没 ENGAGED。广播应不拉。
	var joined := reg.notify_ally_engaged(p0a, creep, TeamRegistry.ALLY_ALERT_RADIUS_WC3)
	if joined != 0:
		_fail("全队 IDLE 时广播应拉 0 人，实际 %d" % joined)
	if ai_b.is_engaged():
		_fail("全队 IDLE 时 p0b 不应被自动拉去打")
	print("  player_idle_does_not_ally_engage OK")
	for u in [p0a, p0b, creep]:
		u.queue_free()


func _test_camp_full_alert_when_source_attacked() -> void:
	var a := _make_unit("nvlw", 12, Vector2(0, 0))
	var b := _make_unit("nvlw", 12, Vector2(300, 0))
	var c := _make_unit("nvlw", 12, Vector2(600, 0)) #  >900 仍可能在警报内
	var player_unit := _make_unit("hfoo", 0, Vector2(-100, 0))

	var ai_a := _attach_ai(a)
	var ai_b := _attach_ai(b)
	var ai_c := _attach_ai(c)
	ai_a.set_profile(UnitAI.Profile.CAMP_CREEP)
	ai_b.set_profile(UnitAI.Profile.CAMP_CREEP)
	ai_c.set_profile(UnitAI.Profile.CAMP_CREEP)

	var reg := TeamRegistry.attach(root)
	reg.cluster_and_bind(root)
	# 全部 IDLE：营地广播应全拉（营地不受 idle 限制）
	var joined := reg.notify_ally_engaged(a, player_unit, TeamRegistry.ALLY_ALERT_RADIUS_WC3)
	if joined < 2:
		_fail("营地广播应至少拉 2 个盟友，实际 %d" % joined)
	if not ai_b.is_engaged() or not ai_c.is_engaged():
		_fail("营地盟友 b、c 应被拉去打")
	print("  camp_full_alert_when_source_attacked OK")
	for u in [a, b, c, player_unit]:
		u.queue_free()


## Bug #3 修复：营地"全组拉"语义——成员距 source 远超 ALLY_ALERT_RADIUS 仍应被拉。
## 玩家 team 仍受半径限制（player_team_uses_ally_radius 测）。
func _test_camp_radius_does_not_limit_full_alert() -> void:
	# 隔离：单挂一层
	var reg := TeamRegistry.attach(root)
	reg._reset()
	var layer := Node3D.new()
	layer.name = "TestLayer_CampRadius"
	root.add_child(layer)
	var a := _make_unit_in_layer(layer, "nvlw", 12, Vector2(0, 0))
	# 离 source 远超 ALLY_ALERT_RADIUS_WC3 (= 900)：放 2000
	var b := _make_unit_in_layer(layer, "nvlw", 12, Vector2(2000, 0))
	var attacker := _make_unit_in_layer(layer, "hfoo", 0, Vector2(-100, 0))
	var ai_a: UnitAI = _attach_ai(a)
	var ai_b: UnitAI = _attach_ai(b)
	ai_a.set_profile(UnitAI.Profile.CAMP_CREEP)
	ai_b.set_profile(UnitAI.Profile.CAMP_CREEP)

	reg.cluster_and_bind(layer)
	# a, b 距 2000 > ALLY_ALERT_RADIUS_WC3，营地成员本应仍被拉
	var joined := reg.notify_ally_engaged(a, attacker, TeamRegistry.ALLY_ALERT_RADIUS_WC3)
	if joined < 1:
		_fail("营地成员 b 距 source 2000，仍应被拉（营地整组），实际 %d" % joined)
	if not ai_b.is_engaged():
		_fail("营地成员 b 应被全组拉去打")
	print("  camp_radius_does_not_limit_full_alert OK")
	layer.queue_free()


## 玩家 team 仍受 assist 半径限制（保留原 WC3 玩家 team 联防语义）。
func _test_player_team_uses_ally_radius() -> void:
	# 隔离
	var reg := TeamRegistry.attach(root)
	reg._reset()
	var layer := Node3D.new()
	layer.name = "TestLayer_PlayerTeamRadius"
	root.add_child(layer)
	var p0a := _make_unit_in_layer(layer, "hfoo", 0, Vector2(0, 0))
	# 玩家队友距 source 1500 > ALLY_ALERT_RADIUS_WC3 (= 900)，应不被拉
	var p0b := _make_unit_in_layer(layer, "hfoo", 0, Vector2(1500, 0))
	var attacker := _make_unit_in_layer(layer, "nvlw", 12, Vector2(-100, 0))
	var ai_a: UnitAI = _attach_ai(p0a)
	_attach_ai(p0b).set_profile(UnitAI.Profile.TEAM_PLAYER)
	ai_a.set_profile(UnitAI.Profile.TEAM_PLAYER)

	# a 先 ENGAGED
	var creep_ai: UnitAI = _attach_ai(attacker)
	creep_ai.set_profile(UnitAI.Profile.CAMP_CREEP)
	creep_ai.try_engage(p0a)
	ai_a.notify_damaged({"ok": true, "attacker": attacker})
	if not ai_a.is_engaged():
		_fail("p0a 受击后应 ENGAGED")

	reg.cluster_and_bind(layer)
	# 触发广播：玩家 team 距 source 1500 > 900，不应拉
	var joined := reg.notify_ally_engaged(p0a, attacker, TeamRegistry.ALLY_ALERT_RADIUS_WC3)
	if joined != 0:
		_fail("玩家 team 距 1500 > 900，应拉 0 人，实际 %d" % joined)
	# 验证：p0b 没有被拉
	# (p0a 自己被排除，所以 joined=0 是预期)
	print("  player_team_uses_ally_radius OK")
	layer.queue_free()


## Bug #1 修复：cluster_and_bind 后 UnitAI.home_wc3 / camp_id 应被回写到 camp 中心。
## 模拟 _wire_all_unit_ai 末尾的回写循环：再调 captures_home_from_body。
func _test_home_bound_after_cluster() -> void:
	var reg := TeamRegistry.attach(root)
	reg._reset()
	var layer := Node3D.new()
	layer.name = "TestLayer_HomeBound"
	root.add_child(layer)
	# 野怪距 400，camp 中心应为 (200, 0)
	var a := _make_unit_in_layer(layer, "nvlw", 12, Vector2(0, 0))
	var b := _make_unit_in_layer(layer, "nvlw", 12, Vector2(400, 0))
	# 模拟"ensure_unit_ai 时 reg 不存在"的旧 fallback：先写出生点
	var ai_a: UnitAI = _attach_ai(a)
	var ai_b: UnitAI = _attach_ai(b)
	ai_a.set_profile(UnitAI.Profile.CAMP_CREEP)
	ai_b.set_profile(UnitAI.Profile.CAMP_CREEP)
	# captures_home_from_body 此时 reg 不存在，会写出生点
	ai_a.captures_home_from_body()
	ai_b.captures_home_from_body()
	var home_a_old := ai_a.home_wc3
	if home_a_old != Vector2(0, 0):
		_fail("reg 不存在时 home 应退化为出生点 (0,0)，实际 %s" % str(home_a_old))
	# cluster 后回写
	reg.cluster_and_bind(layer)
	ai_a.captures_home_from_body()
	ai_b.captures_home_from_body()
	# 现在 home 应是 camp 中心 ≈ (200, 0)
	if absf(ai_a.home_wc3.x - 200.0) > 1.0 or absf(ai_a.home_wc3.y) > 1.0:
		_fail("回写后 ai_a.home_wc3 应 ≈ (200,0)，实际 %s" % str(ai_a.home_wc3))
	if ai_a.camp_id == &"":
		_fail("回写后 ai_a.camp_id 应非空")
	if not reg.is_camp(str(ai_a.camp_id)):
		_fail("ai_a.camp_id 应是 c<n> 营地，实际 %s" % str(ai_a.camp_id))
	# a, b 同营地
	if ai_a.camp_id != ai_b.camp_id:
		_fail("a, b 应同营地，实际 %s vs %s" % [str(ai_a.camp_id), str(ai_b.camp_id)])
	print("  home_bound_after_cluster OK")
	layer.queue_free()


## Bug #2 修复：新生成野怪 attach_to_nearest_camp 应并入最近营地。
func _test_new_spawn_joins_existing_camp() -> void:
	var reg := TeamRegistry.attach(root)
	reg._reset()
	var layer := Node3D.new()
	layer.name = "TestLayer_NewSpawn"
	root.add_child(layer)
	# 先建营地
	var a := _make_unit_in_layer(layer, "nvlw", 12, Vector2(0, 0))
	var b := _make_unit_in_layer(layer, "nvlw", 12, Vector2(200, 0))
	reg.cluster_and_bind(layer)
	var camp_id_before := reg.group_of(a)
	if not reg.is_camp(camp_id_before):
		_fail("cluster 后 a 应入营")

	# 训练出一只新野怪（距 a 150，阈值 900 内）→ 应入同一营
	var newcomer := _make_unit_in_layer(layer, "nvlw", 12, Vector2(150, 0))
	_attach_ai(newcomer).set_profile(UnitAI.Profile.CAMP_CREEP)
	if not reg.attach_to_nearest_camp(newcomer):
		_fail("新野怪距 150 应能入营")
	var camp_id_after := reg.group_of(newcomer)
	if camp_id_after != camp_id_before:
		_fail("新野怪应入同一营地，实际 %s vs %s" % [camp_id_after, camp_id_before])
	if reg.members_of(camp_id_before).size() != 3:
		_fail("入营后营地应有 3 成员，实际 %d" % reg.members_of(camp_id_before).size())

	# 距 1500（> 阈值 900）→ 不应入营（保持 ad-hoc 稳定边界）
	var outsider := _make_unit_in_layer(layer, "nvlw", 12, Vector2(1500, 0))
	_attach_ai(outsider).set_profile(UnitAI.Profile.CAMP_CREEP)
	if reg.attach_to_nearest_camp(outsider):
		_fail("距 1500 > 900 不应入营")
	if reg.group_of(outsider) != "":
		_fail("远距离野怪应不入任何营地")

	# 玩家单位：永远不入营
	var player_unit := _make_unit_in_layer(layer, "hfoo", 0, Vector2(50, 0))
	_attach_ai(player_unit).set_profile(UnitAI.Profile.TEAM_PLAYER)
	if reg.attach_to_nearest_camp(player_unit):
		_fail("玩家单位不应入中立营地")
	print("  new_spawn_joins_existing_camp OK")
	layer.queue_free()


## 营地 home 在成员死亡后**不**应漂移（WC3 原作语义：营地 home 固定）。
## 注意与 _test_home_recompute_after_death 的差异：旧测试依赖旧实现
## （on_unit_gone 重算 home），新实现锁定 home → 测试断言"不变"。
func _test_home_does_not_drift_after_death() -> void:
	# 隔离
	var reg := TeamRegistry.attach(root)
	reg._reset()
	var layer := Node3D.new()
	layer.name = "TestLayer_HomeLock"
	root.add_child(layer)
	var a := _make_unit_in_layer(layer, "nvlw", 12, Vector2(0, 0))
	var b := _make_unit_in_layer(layer, "nvlw", 12, Vector2(400, 0))
	var c := _make_unit_in_layer(layer, "nvlw", 12, Vector2(800, 0))

	reg.cluster_and_bind(layer)
	var gid := reg.group_of(a)
	# 初始 home = 三只中心 (400, 0)
	var home_before := reg.home_of(gid)
	if absf(home_before.x - 400.0) > 1.0 or absf(home_before.y > 1.0):
		_fail("初始 home 应 ≈ (400, 0)，实际 %s" % str(home_before))

	# a 离场（模拟被打死）
	WorldMembership.exit(a)
	reg.on_unit_gone(a)

	# 期望：home 保持 (400, 0)，不漂移到只剩 b/c 的中心 (600, 0)
	var home_after := reg.home_of(gid)
	if home_after == Vector2.INF:
		_fail("b/c 仍存活，营地 home 不应 INF")
	if absf(home_after.x - 400.0) > 1.0 or absf(home_after.y > 1.0):
		_fail("成员死亡后 home 应锁定在 (400, 0)，实际 %s（不允许漂移）" % str(home_after))

	# 全部离场后营地移除
	WorldMembership.exit(b)
	reg.on_unit_gone(b)
	WorldMembership.exit(c)
	reg.on_unit_gone(c)
	if reg.group_of(a) != "" or reg.home_of(gid) == home_after:
		_fail("全部离场后营地应被移除，home 不应保留")
	print("  home_does_not_drift_after_death OK")
	layer.queue_free()
