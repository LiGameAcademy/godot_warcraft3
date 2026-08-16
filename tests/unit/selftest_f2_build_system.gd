extends SceneTree
## F2 建造系统 selftest（按 BUILD_SYSTEM.md §9 钉死 6 维度）。
##
## 7/7：
##   1. F2-D Builds 列表：hpea 含 hhou；不含敌族建筑（halt 在人类 list）
##   2. F2-A Profile：human/orc/nightelf/undead 默认值正确
##   3. F2-B Human 单工：HUMAN profile 多工 + cancel 退款 0.75
##   4. F2-C 多工：0 人暂停；N 人速率 ∝ N（1/2/3 → 1x/2x/3x）
##   5. F2-A Profile Orc stub：supports_multi_builder == false + hides_builder == true
##   6. F2-D WorkerBuildListCatalog.can_build 一致性
##   7. Powerbuild 附加费按进度累计（非整次 join）：2 人全程 ≈ 造价×0.15
##
## godot --headless --path . -s res://tests/unit/selftest_f2_build_system.gd

var passed: int = 0
var total: int = 7


func _init() -> void:
	_test_f2d_builds_list()
	_test_f2a_profile_defaults()
	_test_f2b_human_single_worker()
	_test_f2c_multi_builder_speedup()
	_test_f2a_orc_profile_stub()
	_test_f2d_can_build_consistency()
	_test_powerbuild_cost_over_progress()

	if passed == total:
		print("selftest_f2_build_system: PASS")
		quit(0)
	else:
		push_error("selftest_f2_build_system: FAIL %d/%d" % [passed, total])
		quit(1)


# Test 1: F2-D Builds 列表：hpea 含 hhou；不含敌族建筑
func _test_f2d_builds_list() -> void:
	var catalog := WorkerBuildListCatalog.new()
	var builds := catalog.get_builds("hpea")
	# hpea 应能造 halt（人族祭坛）
	if not builds.has("halt"):
		push_error("test_1 FAIL: hpea should build halt, got %s" % str(builds))
		return
	# hpea 不应能造 ogr（兽族大厅）
	if builds.has("ogr"):
		push_error("test_1 FAIL: hpea should NOT build ogr")
		return
	# hpea 不应能造 etr（暗夜远古之树）
	if builds.has("etr"):
		push_error("test_1 FAIL: hpea should NOT build etr")
		return
	print("  F2-D Builds: hpea builds halt; excludes ogr/etr (correct)")
	passed += 1


# Test 2: F2-A Profile：human/orc/nightelf/undead 默认值正确
func _test_f2a_profile_defaults() -> void:
	var human := ConstructionProfile.human()
	if not human.supports_multi_builder():
		push_error("test_2 FAIL: human should support multi builder")
		return
	if human.hides_builder():
		push_error("test_2 FAIL: human should NOT hide builder")
		return
	if absf(human.cancel_refund_ratio - 0.75) > 0.001:
		push_error("test_2 FAIL: human cancel_refund_ratio=%f expected 0.75" % human.cancel_refund_ratio)
		return

	var orc := ConstructionProfile.orc()
	if orc.supports_multi_builder():
		push_error("test_2 FAIL: orc should NOT support multi builder")
		return
	if not orc.hides_builder():
		push_error("test_2 FAIL: orc should hide builder")
		return

	var ne := ConstructionProfile.nightelf()
	if ne.consume_builder_on_complete != true:
		push_error("test_2 FAIL: nightelf should consume builder on complete")
		return

	var und := ConstructionProfile.undead()
	if und.builder_slot_policy != ConstructionProfile.SlotPolicy.NONE_SUMMON:
		push_error("test_2 FAIL: undead slot_policy != NONE_SUMMON")
		return

	print("  F2-A Profiles: human/orc/ne/undead defaults correct (4 race)")
	passed += 1


# Test 3: F2-B Human 单工：profile 多工 + cancel 退款 0.75
func _test_f2b_human_single_worker() -> void:
	var human := ConstructionProfile.human()
	# human 支持多工
	if not human.supports_multi_builder():
		push_error("test_3 FAIL: human supports_multi_builder")
		return
	# 取消退款 0.75
	var order := BuildOrder.new()
	order.gold_spent = 100
	order.lumber_spent = 50
	var refund_g := int(round(100.0 * human.cancel_refund_ratio))
	var refund_l := int(round(50.0 * human.cancel_refund_ratio))
	if refund_g != 75:
		push_error("test_3 FAIL: refund_g=%d expected 75" % refund_g)
		return
	if refund_l != 38:
		# 0.75 * 50 = 37.5 → round = 38
		push_error("test_3 FAIL: refund_l=%d expected 38" % refund_l)
		return
	print("  F2-B Human single worker: 0.75 refund 100g/50l → 75/38 OK")
	passed += 1


# Test 4: F2-C 多工：0 人暂停；速率 1+(N-1)×0.6（Ahrp Powerbuild）
func _test_f2c_multi_builder_speedup() -> void:
	var site := BuildSite.new()
	var order := BuildOrder.new()
	order.building_id = "halt"
	order.site_wc3 = Vector2(0, 0)
	order.build_time_sec = 10.0
	site.start(order, 0)
	# 没 builder：speedup = 0（暂停）
	if not is_equal_approx(site._process_speedup(), 0.0):
		push_error("test_4 FAIL: speedup with 0 builders should be 0.0, got %f" % site._process_speedup())
		return
	# 1 builder：1.0
	var peasant1 := Node3D.new()
	site.add_builder(peasant1)
	if not is_equal_approx(site._process_speedup(), 1.0):
		push_error("test_4 FAIL: speedup with 1 builder should be 1.0, got %f" % site._process_speedup())
		return
	# 2 builders：1.6
	var peasant2 := Node3D.new()
	site.add_builder(peasant2)
	if not is_equal_approx(site._process_speedup(), 1.6):
		push_error("test_4 FAIL: speedup with 2 builders should be 1.6, got %f" % site._process_speedup())
		return
	# 3 builders：2.2
	var peasant3 := Node3D.new()
	site.add_builder(peasant3)
	if not is_equal_approx(site._process_speedup(), 2.2):
		push_error("test_4 FAIL: speedup with 3 builders should be 2.2, got %f" % site._process_speedup())
		return
	# remove 1 后：1.6
	site.remove_builder(peasant2)
	if not is_equal_approx(site._process_speedup(), 1.6):
		push_error("test_4 FAIL: after remove 1, speedup should be 1.6, got %f" % site._process_speedup())
		return
	# 全部离开 → 0
	site.remove_builder(peasant1)
	site.remove_builder(peasant3)
	if not is_equal_approx(site._process_speedup(), 0.0):
		push_error("test_4 FAIL: after all leave, speedup should be 0.0, got %f" % site._process_speedup())
		return
	if not site.is_paused():
		push_error("test_4 FAIL: site should be paused with 0 builders")
		return
	print("  F2-C Multi-builder: 0/1/2/3 → 0x/1x/1.6x/2.2x + pause (Powerbuild)")
	peasant1.queue_free()
	peasant2.queue_free()
	peasant3.queue_free()
	site.queue_free()
	passed += 1


# Test 5: F2-A Profile Orc stub：supports_multi_builder == false + hides_builder == true
func _test_f2a_orc_profile_stub() -> void:
	var orc := ConstructionProfile.orc()
	if orc.supports_multi_builder():
		push_error("test_5 FAIL: orc should NOT support multi builder")
		return
	if not orc.hides_builder():
		push_error("test_5 FAIL: orc should hide builder")
		return
	if orc.max_builders != 1:
		push_error("test_5 FAIL: orc max_builders should be 1, got %d" % orc.max_builders)
		return
	# human strategy 不应用 orc：HumanConstructionStrategy 对 orc 仍返 true（try_join）
	# 这正是 stub 行为；正确路径是 orc 写自己的 Strategy stub
	# selftest 只验 profile 字段
	print("  F2-A Orc stub: no multi + hide builder + max 1 (correct)")
	passed += 1


# Test 6: F2-D WorkerBuildListCatalog.can_build 一致性
func _test_f2d_can_build_consistency() -> void:
	var catalog := WorkerBuildListCatalog.new()
	if not catalog.can_build("hpea", "halt"):
		push_error("test_6 FAIL: hpea should can_build halt")
		return
	if catalog.can_build("hpea", "ogr"):
		push_error("test_6 FAIL: hpea should NOT can_build ogr")
		return
	# 未知 unit_id 返 false
	if catalog.can_build("hxxx", "halt"):
		push_error("test_6 FAIL: unknown unit hxxx should NOT can_build halt")
		return
	# 空参数返 false
	if catalog.can_build("", "halt"):
		push_error("test_6 FAIL: empty unit should NOT can_build halt")
		return
	if catalog.can_build("hpea", ""):
		push_error("test_6 FAIL: hpea should NOT can_build empty")
		return
	print("  F2-D can_build: hpea/alt ✓, hpea/ogr ✗, unknown/empty all ✗ (consistent)")
	passed += 1


# Test 7: Powerbuild 附加费按 Δ进度累计；2 人全程 ≈ gold×0.15 / lumber×0.15
func _test_powerbuild_cost_over_progress() -> void:
	var session := GameSession.new()
	var stock := PlayerStock.new()
	stock.set_all(1000, 1000, 0, 100)
	session.set_stock(0, stock)
	var site := BuildSite.new()
	site.configure_session(session)
	var order := BuildOrder.new()
	order.building_id = "hhou"
	order.site_wc3 = Vector2.ZERO
	order.build_time_sec = 10.0
	order.gold_spent = 80
	order.lumber_spent = 20
	site.start(order, 0)
	site._powerbuild_cost = 0.15
	site._powerbuild_rate = 0.6
	var p1 := Node3D.new()
	var p2 := Node3D.new()
	site.add_builder(p1)
	site.add_builder(p2)
	# 模拟进度 0→1（2 人）：应累计扣 80*0.15=12 金、20*0.15=3 木
	var steps := 40
	for i in range(steps):
		var prev := float(i) / float(steps)
		var nxt := float(i + 1) / float(steps)
		site._settle_powerbuild_cost(prev, nxt, 2)
	var spent_g := 1000 - stock.gold
	var spent_l := 1000 - stock.lumber
	# 允许 ±1（floor 累计尾数）
	if spent_g < 11 or spent_g > 12:
		push_error("test_7 FAIL: powerbuild gold spent=%d expected ~12" % spent_g)
		p1.queue_free()
		p2.queue_free()
		site.queue_free()
		return
	if spent_l < 2 or spent_l > 3:
		push_error("test_7 FAIL: powerbuild lumber spent=%d expected ~3" % spent_l)
		p1.queue_free()
		p2.queue_free()
		site.queue_free()
		return
	# join 瞬间不应再扣一笔：再 settle 同一 ratio 不变
	var g2 := stock.gold
	site._settle_powerbuild_cost(1.0, 1.0, 2)
	if stock.gold != g2:
		push_error("test_7 FAIL: settle at same ratio should not spend")
		p1.queue_free()
		p2.queue_free()
		site.queue_free()
		return
	print("  Powerbuild cost: 2 workers full progress → ~12g/3l periodic (not lump-sum join)")
	p1.queue_free()
	p2.queue_free()
	site.queue_free()
	passed += 1
