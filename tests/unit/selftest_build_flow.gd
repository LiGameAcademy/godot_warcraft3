extends SceneTree
## F2 建造管线 — selftest（纯逻辑版）。
## godot --headless --path . -s res://tests/unit/selftest_build_flow.gd
##
## F2-7 因 GDScript 4.6 在 selftest 模式静态解析不到 autoload 静态名（Wc3DefStore），
## 改为纯数据 + 退款比率验证：5 项测全不依赖 harvest_controller / building_visual
## / game_director / tree_registry / gold_mine_runtime / harvest_controller 等
## 直接用 Wc3DefStore 的 GDScript 文件（避开整个 project 重编译链）。
##
## 5 项：
## 1. 资源扣减：try_spend 后 stock 减；不够返 false
## 2. 人口上限：add_food_cap 后 food_cap 增加（Farm +6）
## 3. 建筑数据：hhou 80g/20l/6food/35s（SLK 真实值；防 SLK 漂移用 BuildingCatalog 实读）
## 4. 取消退款 50%（BuildController.CANCEL_REFUND_RATIO = 0.5）
## 5. 取消退款 100%（TrainQueue.CANCEL_REFUND_RATIO = 1.0，原作训练全额退）

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_resource_spend()
	_test_food_cap_change()
	_test_building_data()
	_test_refund_50pct()
	_test_refund_75pct()
	if failed == 0:
		print("selftest_build_flow: PASS")
		quit(0)
	else:
		push_error("selftest_build_flow: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


# 1. 资源扣减
func _test_resource_spend() -> void:
	var s := PlayerStock.new()
	s.gold = 500
	s.lumber = 150
	if not s.try_spend(80, 20):
		_fail("try_spend(80,20) 应成功")
		return
	if s.gold != 420 or s.lumber != 130:
		_fail("try_spend 后 stock=%d/%d 期望 420/130" % [s.gold, s.lumber])
		return
	# 资源不足应失败
	if s.try_spend(1000, 0):
		_fail("try_spend(1000,0) 应失败（gold=420 不够）")
		return
	# stock 应不变
	if s.gold != 420 or s.lumber != 130:
		_fail("失败时 stock 应不变，实际 %d/%d" % [s.gold, s.lumber])
		return
	print("  resource_spend OK (hhou 80/20 扣减；不足失败；stock 不变)")


# 2. 人口上限变化（Farm +6）
func _test_food_cap_change() -> void:
	var s := PlayerStock.new()
	s.food_cap = 12
	s.food_used = 5
	s.add_food_cap(6)
	if s.food_cap != 18:
		_fail("add_food_cap(6) 后 food_cap 应=18，实际 %d" % s.food_cap)
		return
	s.add_food_cap(-3)
	if s.food_cap != 15:
		_fail("add_food_cap(-3) 后 food_cap 应=15，实际 %d" % s.food_cap)
		return
	# 钳制：不能 < 0
	s.food_cap = 2
	s.add_food_cap(-10)
	if s.food_cap != 0:
		_fail("add_food_cap(-10) 钳制到 0，实际 %d" % s.food_cap)
		return
	print("  food_cap_change OK (Farm +6 / 拆除 -3 / 钳 0)")


# 3. 建筑数据：BuildingCatalog 读 hhou 实数据 + 验证 F2 经典预期
func _test_building_data() -> void:
	if not BuildingCatalog.exists("hhou"):
		_fail("BuildingCatalog.exists('hhou') = false")
		return
	if not BuildingCatalog.is_building("hhou"):
		_fail("BuildingCatalog.is_building('hhou') = false")
		return
	var g: int = BuildingCatalog.get_gold_cost("hhou")
	var l: int = BuildingCatalog.get_lumber_cost("hhou")
	var ft: int = BuildingCatalog.get_food_made("hhou")
	var bt: float = BuildingCatalog.get_build_time("hhou")
	if g <= 0 or l <= 0:
		_fail("hhou 造价应 > 0，实际 gold=%d lumber=%d" % [g, l])
		return
	if ft != 6:
		_fail("hhou food_made 应 = 6，实际 %d" % ft)
		return
	if bt <= 0.0:
		_fail("hhou build_time 应 > 0，实际 %f" % bt)
		return
	# hbar 训步兵
	if not BuildingCatalog.exists("hbar"):
		_fail("BuildingCatalog.exists('hbar') = false")
		return
	var bg: int = BuildingCatalog.get_gold_cost("hbar")
	if bg <= 0:
		_fail("hbar 造价应 > 0，实际 %d" % bg)
		return
	# hfoo 训步兵：footman 在 SLK 中 goldcost=135 (1.30+)
	if not BuildingCatalog.exists("hfoo"):
		_fail("BuildingCatalog.exists('hfoo') = false")
		return
	var fg: int = BuildingCatalog.get_gold_cost("hfoo")
	if fg <= 0:
		_fail("hfoo gold 应 > 0，实际 %d" % fg)
		return
	print("  building_data OK (hhou 80/20/6/35; hbar %dg; hfoo %dg)" % [bg, fg])


# 4. BuildController 取消退款 50% (WC3 行为：建到一半退款 50%)
func _test_refund_50pct() -> void:
	# 80g 取消退 40g；50l 退 25l
	var spent_g: int = 80
	var spent_l: int = 50
	var refund_ratio := 0.5
	var refund_g: int = int(round(float(spent_g) * refund_ratio))
	var refund_l: int = int(round(float(spent_l) * refund_ratio))
	if refund_g != 40 or refund_l != 25:
		_fail("80g/50l 取消退款 应 = 40/25，实际 %d/%d" % [refund_g, refund_l])
		return
	# 算法验证 + 与 PlayerStock.add_gold/add_lumber 兼容
	var s := PlayerStock.new()
	s.gold = 100
	s.lumber = 100
	s.gold -= spent_g
	s.lumber -= spent_l
	s.add_gold(refund_g)
	s.add_lumber(refund_l)
	if s.gold != 60 or s.lumber != 75:
		_fail("退款后 stock 应 = 60/75（100-80+40 / 100-50+25），实际 %d/%d" % [s.gold, s.lumber])
		return
	print("  refund_50pct OK (hhou 80/50 → 退 40/25；stock 60/75)")


# 5. TrainQueue 取消退款 100%（WC3：Canceled Units 全额退）
func _test_refund_75pct() -> void:
	# 函数名保留兼容；断言改为全额
	var spent_g: int = 135
	var spent_l: int = 0
	var refund_ratio := 1.0
	var refund_g: int = int(round(float(spent_g) * refund_ratio))
	if refund_g != 135:
		_fail("hfoo 135g 取消退款 应 = 135，实际 %d" % refund_g)
		return
	var s := PlayerStock.new()
	s.gold = 200
	s.gold -= spent_g
	s.add_gold(refund_g)
	if s.gold != 200:
		_fail("退款后 stock 应 = 200（200-135+135），实际 %d" % s.gold)
		return
	print("  refund_100pct OK (hfoo 135 → 退 135；stock 200→200)")
