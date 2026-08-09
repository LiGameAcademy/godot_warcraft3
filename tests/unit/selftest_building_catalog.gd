extends SceneTree
## F2 建造管线 — BuildingCatalog 数据自测。
## godot --headless --path . -s res://tests/unit/selftest_building_catalog.gd
##
## 验证：
## 1. 3 建筑（hhou/halt/hbar）is_building=true + exists
## 2. 3 建筑 goldcost/lumbercost > 0
## 3. hhou 唯独提供人口（fmade=6）；halt/hbar fmade=0
## 4. hpea（农民）/ hfoo（步兵）is_building=false
## 5. 3 建筑 footprint 解析非 0
## 6. F2_BUILDING_IDS 常量锁死 3 个
##
## 不硬编码具体数值（防 SLK 漂移；只验"非零/合法范围"）。

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_f2_ids_locked()
	_test_three_buildings_basic()
	_test_food_made_only_farm()
	_test_non_building_excluded()
	_test_footprint_parsed()
	if failed == 0:
		print("selftest_building_catalog: PASS")
		quit(0)
	else:
		push_error("selftest_building_catalog: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


# 1. F2_BUILDING_IDS 锁死 3 个
func _test_f2_ids_locked() -> void:
	if BuildingCatalog.F2_BUILDING_IDS.size() != 3:
		_fail("F2_BUILDING_IDS 应为 3 个，实际 %d" % BuildingCatalog.F2_BUILDING_IDS.size())
		return
	for id in ["hhou", "halt", "hbar"]:
		if not BuildingCatalog.F2_BUILDING_IDS.has(id):
			_fail("F2_BUILDING_IDS 缺 %s" % id)
			return
	print("  f2_ids_locked OK")


# 2. 3 建筑 is_building + exists + 造价 > 0
func _test_three_buildings_basic() -> void:
	for id in ["hhou", "halt", "hbar"]:
		if not BuildingCatalog.exists(id):
			_fail("exists(%s) = false" % id)
			return
		if not BuildingCatalog.is_building(id):
			_fail("is_building(%s) = false" % id)
			return
		var g: int = BuildingCatalog.get_gold_cost(id)
		var l: int = BuildingCatalog.get_lumber_cost(id)
		if g <= 0 or l <= 0:
			_fail("%s 造价不合法 gold=%d lumber=%d" % [id, g, l])
			return
		var t: float = BuildingCatalog.get_build_time(id)
		if t <= 0.0:
			_fail("%s 建造时间 %f <= 0" % [id, t])
			return
	print("  three_buildings_basic OK")


# 3. Farm 唯独提供人口
func _test_food_made_only_farm() -> void:
	var farm_food: int = BuildingCatalog.get_food_made("hhou")
	if farm_food <= 0:
		_fail("Farm fmade 应 > 0，实际 %d" % farm_food)
		return
	for id in ["halt", "hbar"]:
		var f: int = BuildingCatalog.get_food_made(id)
		if f != 0:
			_fail("%s fmade 应 = 0，实际 %d" % [id, f])
			return
	print("  food_made_only_farm OK (hhou=%d)" % farm_food)


# 4. 非建筑（农民/步兵）排除
func _test_non_building_excluded() -> void:
	for id in ["hpea", "hfoo", "hkni", "hamg"]:
		if BuildingCatalog.is_building(id):
			_fail("is_building(%s) 应 = false（不是建筑）" % id)
			return
	print("  non_building_excluded OK")


# 5. footprint 解析（hhou=4x4, halt=10x10, hbar=12x12；WC3 1.30+ 实际值）
func _test_footprint_parsed() -> void:
	var exp := {
		"hhou": Vector2i(4, 4),
		"halt": Vector2i(10, 10),
		"hbar": Vector2i(12, 12),
	}
	for id in exp.keys():
		var fp: Vector2i = BuildingCatalog.get_footprint(id)
		var want: Vector2i = exp[id]
		if fp != want:
			_fail("%s footprint 应=%s, 实际=%s" % [id, want, fp])
			return
		var tex: String = BuildingCatalog.get_path_tex(id)
		if tex.is_empty() or tex.to_lower() == "none":
			_fail("%s path_tex 应非空：%s" % [id, tex])
			return
	print("  footprint_parsed OK (hhou=4x4 halt=10x10 hbar=12x12)")
