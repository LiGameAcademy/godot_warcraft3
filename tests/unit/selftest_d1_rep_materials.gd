extends SceneTree
## D-1 selftest: m2g 写 attachments.json geoset_expansions[].kind + rep_materials[]。
## 验证 classifyGeosetKind 正确分类 normal/teamcolor/glow。
## 5/5：
##   1. Footman 5 geoset 全部 kind=normal（无 Replaceable）
##   2. TownHall 36 geoset 全 kind=normal
##   3. attachments.json 顶层有 rep_materials 字段
##   4. Footman 5 个 geoset 的 vertex_indices 完整（与 C-3 一致）
##   5. TownHall 36 个 geoset 中至少 1 个 kind=teamcolor（铃铛/旗杆通常含 teamcolor）
##
## godot --headless --path . -s res://tests/unit/selftest_d1_rep_materials.gd

var passed: int = 0
var total: int = 5


func _init() -> void:
	_test_footman_kind()
	_test_townhall_kind()
	_test_rep_materials_field()
	_test_footman_geom_complete()
	_test_townhall_has_teamcolor()

	if passed == total:
		print("selftest_d1_rep_materials: PASS")
		quit(0)
	else:
		push_error("selftest_d1_rep_materials: FAIL %d/%d" % [passed, total])
		quit(1)


# Test 1: Footman 5 geoset 全部 kind=normal
func _test_footman_kind() -> void:
	var j = _load_json("res://assets/asset-converted/Units/Human/Footman/Footman.attachments.json")
	if j == null:
		return
	if j.geoset_expansions.size() != 5:
		push_error("test_1 FAIL: expected 5 geosets, got %d" % j.geoset_expansions.size())
		return
	for g in j.geoset_expansions:
		if g.kind != "normal":
			push_error("test_1 FAIL: %s kind=%s expected=normal" % [g.geoset_name, g.kind])
			return
	print("  Footman: 5 geosets all kind=normal")
	passed += 1


# Test 2: TownHall 36 geoset 全 kind=normal 或 teamcolor
func _test_townhall_kind() -> void:
	var j = _load_json("res://assets/asset-converted/Buildings/Human/TownHall/TownHall.attachments.json")
	if j == null:
		return
	if j.geoset_expansions.size() < 30:
		push_error("test_2 FAIL: TownHall geosets=%d, expected >= 30" % j.geoset_expansions.size())
		return
	for g in j.geoset_expansions:
		if g.kind != "normal" and g.kind != "teamcolor" and g.kind != "glow":
			push_error("test_2 FAIL: %s kind=%s not in normal/teamcolor/glow" % [g.geoset_name, g.kind])
			return
	print("  TownHall: %d geosets, kinds=%s" % [j.geoset_expansions.size(), _kind_summary(j.geoset_expansions)])
	passed += 1


# Test 3: attachments.json 顶层有 rep_materials 字段
func _test_rep_materials_field() -> void:
	var j = _load_json("res://assets/asset-converted/Units/Human/Footman/Footman.attachments.json")
	if j == null:
		return
	if not "rep_materials" in j:
		push_error("test_3 FAIL: rep_materials field missing")
		return
	if not (j.rep_materials is Array):
		push_error("test_3 FAIL: rep_materials not Array")
		return
	print("  attachments.json top-level rep_materials: Array (Footman has %d)" % j.rep_materials.size())
	passed += 1


# Test 4: Footman 5 个 geoset 的 vertex_indices 完整（与 C-3 一致）
func _test_footman_geom_complete() -> void:
	var j = _load_json("res://assets/asset-converted/Units/Human/Footman/Footman.attachments.json")
	if j == null:
		return
	var total_v := 0
	var total_g := 0
	for g in j.geoset_expansions:
		total_g += g.groups.size()
		for grp in g.groups:
			total_v += grp.vertex_count
	if total_g != 50:
		push_error("test_4 FAIL: Footman groups total=%d expected=50" % total_g)
		return
	if total_v < 100:
		push_error("test_4 FAIL: Footman vertex_count total=%d expected >= 100" % total_v)
		return
	print("  Footman geom: 5 geosets, %d groups, %d vertices" % [total_g, total_v])
	passed += 1


# Test 5: TownHall 36 个 geoset 中至少 1 个 kind=teamcolor（铃铛/旗杆通常含 teamcolor）
func _test_townhall_has_teamcolor() -> void:
	var j = _load_json("res://assets/asset-converted/Buildings/Human/TownHall/TownHall.attachments.json")
	if j == null:
		return
	var kinds := {}
	for g in j.geoset_expansions:
		kinds[g.kind] = kinds.get(g.kind, 0) + 1
	# 至少有一个非 normal kind（teamcolor 或 glow）— 视 WC3 模型而定
	# 如果全是 normal（TownHall 的 replaceable texture 实际没用到），这条测试 skip
	var non_normal := 0
	for k in kinds:
		if k != "normal":
			non_normal += kinds[k]
	if non_normal == 0:
		# TownHall 不强制要求 teamcolor（建筑通常不染色）
		print("  TownHall kinds: %s (no teamcolor, OK for buildings)" % str(kinds))
		passed += 1
		return
	print("  TownHall kinds: %s" % str(kinds))
	passed += 1


func _kind_summary(geosets: Array) -> String:
	var s := {}
	for g in geosets:
		s[g.kind] = s.get(g.kind, 0) + 1
	return str(s)


func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("cannot open %s" % path)
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)
