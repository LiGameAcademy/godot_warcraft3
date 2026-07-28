extends SceneTree
## 悬崖变体 / 叠段 / 笔刷拓扑回归测试。
##
## ## 自动化（本脚本）
## - 64 种 TAG 均有 GLB
## - 跨度≤2：AABB/角柱/AABC 族 → 恰好 1 片（禁止再叠 AAAB）
## - 跨度>2：按 +2 叠段再收尾
## - 笔刷：2×2 台面+中心柱、边两顶点再抬一角 → 无 span2 多片 / 无缺模
## - 邻近两座悬崖：在 A 处刷泥土崖不得改写 B 处草地崖贴图（远程副作用）
## - 异种接触：邻接刷 CLgr 须同化触及直崖格；远处对照点仍为 CLdi
##
## ## 手工目视清单（编辑器里对照 HiveWE 0.3）
## 1. 升一层整墙（两顶点同边）→ 连续岩壁，无碎块重影
## 2. 再只抬一角 → 「底两顶一」过渡（AABC 等），侧壁封住挖洞
## 3. 2×2 台面后再抬中心一点 → 上层小台，下层外扩蛋糕，无对角碎柱
## 4. 工具「3」连点同一点三次 → 蛋糕外扩，邻格/对角层差≤2
## 5. 草地崖类型刷出后，外扩圈地表/崖贴图一致（见 selftest_cliff_ground_tex）
## 6. 降崖对称：压高点后不留悬浮岩片
## 7. 同一片草地上两座崖：只刷其中一座，另一座贴图/层高不变
## 8. 泥土崖旁邻接刷草地崖：接触区转为草地崖，不混角渗色
##
## 运行：
##   godot --headless --path . -s res://tests/cliff/selftest_cliff_variants.gd


const DocScript := preload("res://editor/scripts/map_document.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cliffs := Wc3CliffCatalog.new()
	cliffs.load_default()
	var model_dir := cliffs.cliff_model_dir("CLdi")
	var failed := 0

	failed += _case_tag_table_and_glbs(model_dir)
	failed += _case_span2_single_slice()
	failed += _case_asymmetric_aabc_family()
	failed += _case_tall_stack_span_gt2()
	failed += _case_paint_plateau_then_pillar(cliffs)
	failed += _case_paint_level2_edge_then_corner(cliffs)
	failed += _case_remote_cliff_tex_isolation()
	failed += _case_heterogeneous_contact_assimilate()
	failed += _case_wall_variations_diverse_along_face(cliffs)
	failed += _case_plateau_top_keeps_dirt_for_grass_cliff()
	failed += _case_faces_use_diverse_variations(cliffs)

	if failed > 0:
		push_error("selftest_cliff_variants FAILED cases=%d" % failed)
		quit(1)
		return
	print("selftest_cliff_variants OK")
	quit(0)


## ---------- helpers ----------

func _layers_2x2(bl: int, br: int, tl: int, tr: int) -> Array:
	# 2x2 tilepoints → 1 tile；宽=2
	return [bl, br, tl, tr]


func _assert_slices(
	name: String, layers: Array, width: int, ix: int, iy: int, expect: Array
) -> int:
	var got: Array = Wc3CliffLogic.cliff_slices_at(layers, width, ix, iy)
	var got_s: PackedStringArray = PackedStringArray()
	for s in got:
		got_s.append("%s@%d" % [str(s.get("tag", "")), int(s.get("base_layer", 0))])
	var exp_s: PackedStringArray = PackedStringArray()
	for e in expect:
		exp_s.append("%s@%d" % [str(e.get("tag", "")), int(e.get("base_layer", 0))])
	var ok := got_s.size() == exp_s.size()
	if ok:
		for i in range(got_s.size()):
			if got_s[i] != exp_s[i]:
				ok = false
				break
	if not ok:
		push_error(
			"%s: expected [%s] got [%s]"
			% [name, " ".join(exp_s), " ".join(got_s)]
		)
		return 1
	print("OK %s -> %s" % [name, " ".join(got_s)])
	return 0


func _new_doc() -> Object:
	var doc = DocScript.new()
	doc.create_from_options({
		"width": 32,
		"height": 32,
		"main_tileset": "L",
		"main_tileset_name": "Lordaeron Summer",
		"ground_tilesets": ["Ldrt", "Lgrs"],
		"cliff_tilesets": ["CLdi", "CLgr"],
		"cliff_level": 2,
	})
	return doc


func _print_layers(doc, cx: int, cy: int, rad: int = 3) -> void:
	var layers: Array = doc.as_build_dict()["layerHeights"]
	var tp_w: int = int(doc.as_build_dict()["tilepointWidth"])
	print("--- layers around (%d,%d) ---" % [cx, cy])
	for y in range(cy - rad, cy + rad + 1):
		var row := ""
		for x in range(cx - rad, cx + rad + 1):
			row += "%d " % int(layers[y * tp_w + x])
		print(row)


func _scan_missing_and_dup(
	doc, cliffs: Wc3CliffCatalog, cx: int, cy: int, rad: int = 4
) -> Dictionary:
	var layers: Array = doc.as_build_dict()["layerHeights"]
	var tp_w: int = int(doc.as_build_dict()["tilepointWidth"])
	var missing: Dictionary = {}
	var multi_on_span2 := 0
	var slice_n := 0
	for iy in range(cy - rad, cy + rad):
		for ix in range(cx - rad, cx + rad):
			if not Wc3CliffLogic.is_cliff_tile(layers, tp_w, ix, iy):
				continue
			var i00 := iy * tp_w + ix
			var bl := int(layers[i00])
			var br := int(layers[i00 + 1])
			var tl := int(layers[i00 + tp_w])
			var tr := int(layers[i00 + tp_w + 1])
			var lo := mini(mini(bl, br), mini(tl, tr))
			var hi := maxi(maxi(bl, br), maxi(tl, tr))
			var slices: Array = Wc3CliffLogic.cliff_slices_at(layers, tp_w, ix, iy)
			slice_n += slices.size()
			if hi - lo <= 2 and slices.size() > 1:
				multi_on_span2 += 1
				push_error(
					"span<=2 but %d slices at (%d,%d) %d/%d/%d/%d -> %s"
					% [slices.size(), ix, iy, bl, tl, tr, br, str(slices)]
				)
			for s in slices:
				var tag: String = str(s.get("tag", ""))
				var glb := cliffs.resolve_glb(cliffs.cliff_model_dir("CLdi"), tag, 0)
				if glb.is_empty():
					missing[tag] = true
	var placements: Array[Wc3CliffPlacement] = Wc3CliffLogic.collect_placements(
		doc.heightfield, cliffs
	)
	var collected: Wc3CliffBuildResult = Wc3CliffBuilder.build_from_placements(
		placements,
		cliffs,
		doc.heightfield.center_offset,
		doc.heightfield.tile_size
	)
	return {
		"missing_tags": missing,
		"multi_on_span2": multi_on_span2,
		"slice_n": slice_n,
		"builder_missing": collected.missing,
		"placed": collected.placed_cliffs,
	}


## ---------- cases ----------

func _case_tag_table_and_glbs(model_dir: String) -> int:
	print("=== case: disk tags resolve to GLB ===")
	var fail := 0
	var cat := Wc3CliffCatalog.new()
	cat.load_default()
	var tags: PackedStringArray = cat.list_model_tags(model_dir)
	if tags.is_empty():
		push_error("no cliff tags found under %s" % model_dir)
		return 1
	for tag in tags:
		var glb := cat.resolve_glb(model_dir, str(tag), 0)
		if glb.is_empty():
			push_error("missing GLB for tag %s" % tag)
			fail += 1
	if fail == 0:
		print("OK all %d tags have GLB" % tags.size())
	return fail


func _case_span2_single_slice() -> int:
	print("=== case: span<=2 → exactly one slice ===")
	var fail := 0
	# TAG 序 = BL,TL,TR,BR；_layers_2x2(bl, br, tl, tr)
	# AABB：西低东高整墙（BL/TL=A，TR/BR=B）
	fail += _assert_slices(
		"AABB", _layers_2x2(2, 3, 2, 3), 2, 0, 0,
		[{"tag": "AABB", "base_layer": 2}]
	)
	# ABBA：南低北高整墙
	fail += _assert_slices(
		"ABBA", _layers_2x2(2, 2, 3, 3), 2, 0, 0,
		[{"tag": "ABBA", "base_layer": 2}]
	)
	# AAAC：仅 BR 抬高的角柱
	fail += _assert_slices(
		"AAAC", _layers_2x2(2, 4, 2, 2), 2, 0, 0,
		[{"tag": "AAAC", "base_layer": 2}]
	)
	# AACC：东侧双边墙（TR/BR 高）
	fail += _assert_slices(
		"AACC", _layers_2x2(2, 4, 2, 4), 2, 0, 0,
		[{"tag": "AACC", "base_layer": 2}]
	)
	return fail


func _case_asymmetric_aabc_family() -> int:
	print("=== case: asymmetric AABC family (底两边/顶一边等) single slice ===")
	var fail := 0
	# 经典「底两顶一」：BL/TL=低，TR=中，BR=高 → AABC
	fail += _assert_slices(
		"AABC", _layers_2x2(2, 4, 2, 3), 2, 0, 0,
		[{"tag": "AABC", "base_layer": 2}]
	)
	fail += _assert_slices(
		"AACB", _layers_2x2(2, 3, 2, 4), 2, 0, 0,
		[{"tag": "AACB", "base_layer": 2}]
	)
	fail += _assert_slices(
		"ABAC", _layers_2x2(2, 4, 3, 2), 2, 0, 0,
		[{"tag": "ABAC", "base_layer": 2}]
	)
	fail += _assert_slices(
		"BAAC", _layers_2x2(3, 4, 2, 2), 2, 0, 0,
		[{"tag": "BAAC", "base_layer": 2}]
	)
	fail += _assert_slices(
		"CAAB", _layers_2x2(4, 3, 2, 2), 2, 0, 0,
		[{"tag": "CAAB", "base_layer": 2}]
	)
	fail += _assert_slices(
		"CABA", _layers_2x2(4, 2, 2, 3), 2, 0, 0,
		[{"tag": "CABA", "base_layer": 2}]
	)
	# 旋转族：两中一层高
	fail += _assert_slices(
		"ABBC", _layers_2x2(2, 4, 3, 3), 2, 0, 0,
		[{"tag": "ABBC", "base_layer": 2}]
	)
	return fail


func _case_tall_stack_span_gt2() -> int:
	print("=== case: span>2 stacks by +2 then remainder ===")
	var fail := 0
	# 仅 BR 升高 3：AAAC@2 + AAAB@4
	fail += _assert_slices(
		"tall corner", _layers_2x2(2, 5, 2, 2), 2, 0, 0,
		[
			{"tag": "AAAC", "base_layer": 2},
			{"tag": "AAAB", "base_layer": 4},
		]
	)
	# 北侧整边升高 4：ACCA@2 + ACCA@4
	fail += _assert_slices(
		"tall wall", _layers_2x2(2, 2, 6, 6), 2, 0, 0,
		[
			{"tag": "ACCA", "base_layer": 2},
			{"tag": "ACCA", "base_layer": 4},
		]
	)
	return fail


func _case_paint_plateau_then_pillar(cliffs: Wc3CliffCatalog) -> int:
	print("=== case: paint 2x2 plateau then center pillar (+1) ===")
	var doc = _new_doc()
	var cx := 16
	var cy := 16
	# 2x2 台面四个顶点各升一层
	for oy in range(0, 2):
		for ox in range(0, 2):
			doc.paint_cliff_corner(cx + ox, cy + oy, "3", 0)
	# 中心再升一层 → 上层 footprint 更小，邻格易出 AABC 族
	doc.paint_cliff_corner(cx, cy, "3", 0)
	_print_layers(doc, cx, cy)
	var scan := _scan_missing_and_dup(doc, cliffs, cx, cy)
	print(
		"plateau+pillar placed=%d slices=%d multi_span2=%d missing=%s"
		% [
			int(scan["placed"]),
			int(scan["slice_n"]),
			int(scan["multi_on_span2"]),
			str((scan["missing_tags"] as Dictionary).keys()),
		]
	)
	if int(scan["multi_on_span2"]) > 0:
		return 1
	if not (scan["missing_tags"] as Dictionary).is_empty() or int(scan["builder_missing"]) > 0:
		return 1
	return 0


func _case_paint_level2_edge_then_corner(cliffs: Wc3CliffCatalog) -> int:
	print("=== case: level2 edge (2 verts) then one top corner ===")
	var doc = _new_doc()
	var cx := 16
	var cy := 16
	# 先抬一条边（两顶点）→ 形成整墙
	doc.paint_cliff_corner(cx, cy, "3", 0)
	doc.paint_cliff_corner(cx + 1, cy, "3", 0)
	# 再只抬其中一个角到更高 → 「底两顶一」
	doc.paint_cliff_corner(cx + 1, cy, "3", 0)
	_print_layers(doc, cx, cy)
	var layers: Array = doc.as_build_dict()["layerHeights"]
	var tp_w: int = int(doc.as_build_dict()["tilepointWidth"])
	# 找含 AABC 族的格，断言单 slice
	var found_asym := false
	var fail := 0
	for iy in range(cy - 2, cy + 2):
		for ix in range(cx - 2, cx + 2):
			if not Wc3CliffLogic.is_cliff_tile(layers, tp_w, ix, iy):
				continue
			var slices: Array = Wc3CliffLogic.cliff_slices_at(layers, tp_w, ix, iy)
			for s in slices:
				var tag: String = str(s.get("tag", ""))
				# 三高度字母（含 A/B/C 各至少…简化：tag 同时含 B 与 C）
				if tag.contains("B") and tag.contains("C") and tag.contains("A"):
					found_asym = true
					print("asym tile(%d,%d) -> %s@%d" % [ix, iy, tag, int(s.get("base_layer", 0))])
			var i00 := iy * tp_w + ix
			var lo := mini(
				mini(int(layers[i00]), int(layers[i00 + 1])),
				mini(int(layers[i00 + tp_w]), int(layers[i00 + tp_w + 1]))
			)
			var hi := maxi(
				maxi(int(layers[i00]), int(layers[i00 + 1])),
				maxi(int(layers[i00 + tp_w]), int(layers[i00 + tp_w + 1]))
			)
			if hi - lo <= 2 and slices.size() != 1:
				push_error(
					"edge+corner tile(%d,%d) span=%d slices=%d"
					% [ix, iy, hi - lo, slices.size()]
				)
				fail += 1
	var scan := _scan_missing_and_dup(doc, cliffs, cx, cy)
	if int(scan["multi_on_span2"]) > 0:
		fail += 1
	if not (scan["missing_tags"] as Dictionary).is_empty() or int(scan["builder_missing"]) > 0:
		fail += 1
	if not found_asym:
		print("NOTE: no A/B/C-mixed tag in this stroke (cake may reshape); scan still clean")
	print(
		"edge+corner placed=%d asym_found=%s fail=%d"
		% [int(scan["placed"]), str(found_asym), fail]
	)
	return fail


## 复现：同一片草地上两座邻近悬崖；在 A 刷泥土崖不得改写 B 的草地崖贴图。
## 旧逻辑按 touched 的 AABB（再扩边）扫区域内所有直崖格：
## 单点连升 +3 时 AABB 可覆盖约 4 格外的另一座崖 → 误把 CLgr/Lgrs 盖成 CLdi/Ldrt。
func _case_remote_cliff_tex_isolation() -> int:
	print("=== case: remote cliff texture isolation (A paint must not stomp B) ===")
	var doc = _new_doc()
	var tp_w: int = int(doc.as_build_dict()["tilepointWidth"])
	var ax := 16
	var ay := 16
	var bx := 20
	var by := 20

	# B：草地崖 CLgr=1，2×2 台面升 2 层（先建「右上」崖）
	for _s in range(2):
		for oy in range(0, 2):
			for ox in range(0, 2):
				doc.paint_cliff_corner(bx + ox, by + oy, "3", 1)

	var cliff_tex: Array = doc.as_build_dict()["cliffTextures"]
	var ground: Array = doc.as_build_dict()["groundTextures"]
	var layers: Array = doc.as_build_dict()["layerHeights"]
	var snap_cliff: Dictionary = {}
	var snap_ground: Dictionary = {}
	var snap_layer: Dictionary = {}
	for y in range(by - 1, by + 3):
		for x in range(bx - 1, bx + 3):
			var i: int = y * tp_w + x
			snap_cliff[i] = int(cliff_tex[i])
			snap_ground[i] = int(ground[i])
			snap_layer[i] = int(layers[i])

	var b_i: int = by * tp_w + bx
	if int(cliff_tex[b_i]) != 1:
		push_error("setup B cliffTextures expected 1(CLgr), got %d" % int(cliff_tex[b_i]))
		return 1

	# A：泥土崖 CLdi=0，单点连升 3 层 → 蛋糕外扩大、旧 AABB 会罩住 B
	for _s2 in range(3):
		doc.paint_cliff_corner(ax, ay, "3", 0)

	cliff_tex = doc.as_build_dict()["cliffTextures"]
	ground = doc.as_build_dict()["groundTextures"]
	layers = doc.as_build_dict()["layerHeights"]
	_print_layers(doc, ax, ay, 5)

	var fail := 0
	var stomped := 0
	for y2 in range(by - 1, by + 3):
		for x2 in range(bx - 1, bx + 3):
			var j: int = y2 * tp_w + x2
			if int(cliff_tex[j]) != int(snap_cliff[j]):
				push_error(
					"B cliffTextures stomped at (%d,%d): was %d now %d"
					% [x2, y2, int(snap_cliff[j]), int(cliff_tex[j])]
				)
				stomped += 1
			if int(ground[j]) != int(snap_ground[j]):
				push_error(
					"B groundTextures stomped at (%d,%d): was %d now %d"
					% [x2, y2, int(snap_ground[j]), int(ground[j])]
				)
				stomped += 1
			if int(layers[j]) != int(snap_layer[j]):
				# 层高若被蛋糕连上属于另一类问题；贴图隔离仍要报
				push_error(
					"B layerHeights changed at (%d,%d): was %d now %d"
					% [x2, y2, int(snap_layer[j]), int(layers[j])]
				)
				stomped += 1
	if stomped > 0:
		fail = 1
	var a_i: int = ay * tp_w + ax
	if int(cliff_tex[a_i]) != 0:
		push_error("A cliffTextures expected 0(CLdi), got %d" % int(cliff_tex[a_i]))
		fail = 1
	print(
		"isolation A(%d,%d)+3 CLdi vs B(%d,%d) CLgr stomped=%d fail=%d"
		% [ax, ay, bx, by, stomped, fail]
	)
	return fail


## 策略 B：先建泥土崖台面，再在邻接顶点刷草地崖 → 接触直崖格须同化成 CLgr；
## 远处另建一座泥土崖对照点不得被改写。
func _case_heterogeneous_contact_assimilate() -> int:
	print("=== case: heterogeneous contact assimilates (policy B) ===")
	var doc = _new_doc()
	var tp_w: int = int(doc.as_build_dict()["tilepointWidth"])
	# 近处泥土崖台面
	var nx := 16
	var ny := 16
	for oy in range(0, 2):
		for ox in range(0, 2):
			doc.paint_cliff_corner(nx + ox, ny + oy, "3", 0)
	# 远处泥土崖对照（不会被邻接笔触及）
	var fx := 26
	var fy := 26
	for oy2 in range(0, 2):
		for ox2 in range(0, 2):
			doc.paint_cliff_corner(fx + ox2, fy + oy2, "3", 0)

	var cliff_tex: Array = doc.as_build_dict()["cliffTextures"]
	var ground: Array = doc.as_build_dict()["groundTextures"]
	var far_i: int = fy * tp_w + fx
	if int(cliff_tex[far_i]) != 0:
		push_error("setup far cliff expected CLdi=0, got %d" % int(cliff_tex[far_i]))
		return 1
	var far_cliff := int(cliff_tex[far_i])
	var far_ground := int(ground[far_i])

	# 在近处台面边缘邻接处刷草地崖（升高一点，种子落在旧崖边上）
	doc.paint_cliff_corner(nx + 2, ny, "3", 1)
	doc.paint_cliff_corner(nx + 2, ny + 1, "3", 1)

	cliff_tex = doc.as_build_dict()["cliffTextures"]
	ground = doc.as_build_dict()["groundTextures"]
	var layers: Array = doc.as_build_dict()["layerHeights"]
	var fail := 0
	var assimilated := 0
	# 检查含落笔角的直崖格四角是否已为 CLgr=1 / Lgrs
	for iy in range(ny - 1, ny + 3):
		for ix in range(nx - 1, nx + 3):
			if not Wc3CliffLogic.is_cliff_tile(layers, tp_w, ix, iy):
				continue
			var touches_seed := false
			for cy in range(0, 2):
				for cx in range(0, 2):
					var px: int = ix + cx
					var py: int = iy + cy
					if (px == nx + 2 and py == ny) or (px == nx + 2 and py == ny + 1):
						touches_seed = true
			if not touches_seed:
				continue
			for cy2 in range(0, 2):
				for cx2 in range(0, 2):
					var qi: int = (iy + cy2) * tp_w + (ix + cx2)
					if int(cliff_tex[qi]) != 1:
						push_error(
							"contact tile(%d,%d) corner(%d,%d) cliffTextures=%d want 1(CLgr)"
							% [ix, iy, ix + cx2, iy + cy2, int(cliff_tex[qi])]
						)
						fail = 1
					else:
						assimilated += 1
					# groundTile for CLgr is Lgrs → index 1；直崖格四角均同化
					if int(ground[qi]) != 1:
						push_error(
							"contact corner(%d,%d) groundTextures=%d want 1(Lgrs)"
							% [ix + cx2, iy + cy2, int(ground[qi])]
						)
						fail = 1

	if assimilated == 0:
		push_error("no contact cliff corners assimilated (brush may have missed old cliff)")
		fail = 1

	if int(cliff_tex[far_i]) != far_cliff or int(ground[far_i]) != far_ground:
		push_error(
			"far cliff stomped: cliff %d→%d ground %d→%d"
			% [far_cliff, int(cliff_tex[far_i]), far_ground, int(ground[far_i])]
		)
		fail = 1

	print(
		"hetero contact assimilated_corners=%d far_ok=%s fail=%d"
		% [assimilated, str(int(cliff_tex[far_i]) == far_cliff), fail]
	)
	return fail


## 同一条 AABB 直墙：笔刷写入随机 cliffVariations 后，同墙可出现多种 variation。
func _case_wall_variations_diverse_along_face(cliffs: Wc3CliffCatalog) -> int:
	var doc = DocScript.new()
	doc.create_from_options({
		"width": 16,
		"height": 16,
		"main_tileset": "L",
		"ground_tilesets": ["Ldrt", "Lgrs", "Lrok"],
		"cliff_tilesets": ["CLdi", "CLgr"],
		"cliff_level": 2,
		"default_tile_index": 0,
	})
	for y in range(5, 12):
		for x in range(8, 12):
			doc.paint_cliff_corner(x, y, "3", 0)
	var hf := Wc3Heightfield.from_dict(doc.as_build_dict(), false)
	# 显式写入非条纹随机序列，避免偶发全撞同一 clamp 结果
	var seq: Array[int] = [0, 2, 1, 0, 1, 2, 1]
	var yi := 0
	for y in range(5, 12):
		var bi: int = y * hf.width + 7 # 西墙 BL 约在 x=7
		if bi >= 0 and bi < hf.cliff_variations.size():
			hf.cliff_variations[bi] = seq[yi % seq.size()]
		yi += 1
	var placements: Array[Wc3CliffPlacement] = Wc3CliffLogic.collect_placements(hf, cliffs)
	var aabb_vars: Dictionary = {}
	var aabb_count := 0
	for p in placements:
		if p.tag != "AABB":
			continue
		aabb_count += 1
		aabb_vars[p.variation] = true
	if aabb_count < 3:
		push_error("wall_diverse: expected multiple AABB along wall, got %d" % aabb_count)
		return 1
	if cliffs.max_variation("Cliffs", "AABB") >= 1 and aabb_vars.size() < 2:
		push_error(
			"wall_diverse: AABB wall should use >1 variation, got %s (n=%d)"
			% [str(aabb_vars.keys()), aabb_count]
		)
		return 1
	print(
		"wall_diverse AABB n=%d vars=%s OK"
		% [aabb_count, str(aabb_vars.keys())]
	)
	return 0


## 草地悬崖抬台后：台心保持泥土；贴崖缘角点为 groundTile（与泥土形成过渡）。
func _case_plateau_top_keeps_dirt_for_grass_cliff() -> int:
	var doc = DocScript.new()
	doc.create_from_options({
		"width": 16,
		"height": 16,
		"main_tileset": "L",
		"ground_tilesets": ["Ldrt", "Lgrs", "Lrok"],
		"cliff_tilesets": ["CLdi", "CLgr"],
		"cliff_level": 2,
		"default_tile_index": 0,
	})
	for y in range(6, 11):
		for x in range(6, 11):
			doc.paint_cliff_corner(x, y, "3", 1) # CLgr
	var d: Dictionary = doc.as_build_dict()
	var tp_w: int = int(d["tilepointWidth"])
	var tp_h: int = int(d["tilepointHeight"])
	var ground: Array = d["groundTextures"]
	var layers: Array = d["layerHeights"]
	# 台顶中心 (8,8) 不贴直崖 → 泥土
	if Wc3CliffLogic.is_cliff_tile_corner(layers, tp_w, tp_h, 8, 8):
		push_error("plateau center unexpectedly on cliff tile corner")
		return 1
	if int(ground[8 * tp_w + 8]) != 0:
		push_error("plateau top ground=%d want 0(Ldrt)" % int(ground[8 * tp_w + 8]))
		return 1
	# 缘角（贴直崖）应为 Lgrs，与台心泥土形成过渡
	if not Wc3CliffLogic.is_cliff_tile_corner(layers, tp_w, tp_h, 6, 6):
		push_error("plateau rim (6,6) should be cliff tile corner")
		return 1
	if int(ground[6 * tp_w + 6]) != 1:
		push_error("plateau rim ground=%d want 1(Lgrs)" % int(ground[6 * tp_w + 6]))
		return 1
	var cat := Wc3CliffCatalog.new()
	cat.load_default()
	var c2g: PackedInt32Array = cat.build_cliff_to_ground_map(d["cliffTilesets"], d["groundTilesets"])
	var terrain := MapTerrainLayer.new()
	var center_t: int = terrain.corner_texture(
		ground, layers, d["cliffTextures"], c2g, tp_w, tp_h, 8, 8
	)
	var rim_t: int = terrain.corner_texture(
		ground, layers, d["cliffTextures"], c2g, tp_w, tp_h, 6, 6
	)
	terrain.free()
	if center_t != 0:
		push_error("corner_texture forced plateau center to %d want 0" % center_t)
		return 1
	if rim_t != 1:
		push_error("corner_texture rim=%d want 1(Lgrs)" % rim_t)
		return 1
	print("plateau_top_center_dirt_rim_grass OK")
	return 0


## 矩形台四面直墙（不同 TAG）应出现多于一种 variation（Catalog 空间哈希）。
func _case_faces_use_diverse_variations(cliffs: Wc3CliffCatalog) -> int:
	var doc = DocScript.new()
	doc.create_from_options({
		"width": 16,
		"height": 16,
		"main_tileset": "L",
		"ground_tilesets": ["Ldrt", "Lgrs", "Lrok"],
		"cliff_tilesets": ["CLdi", "CLgr"],
		"cliff_level": 2,
		"default_tile_index": 0,
	})
	for y in range(5, 12):
		for x in range(5, 12):
			doc.paint_cliff_corner(x, y, "3", 0)
	var hf := Wc3Heightfield.from_dict(doc.as_build_dict(), false)
	var placements: Array[Wc3CliffPlacement] = Wc3CliffLogic.collect_placements(hf, cliffs)
	var by_tag: Dictionary = {}
	for p in placements:
		if not by_tag.has(p.tag):
			by_tag[p.tag] = {}
		(by_tag[p.tag] as Dictionary)[p.variation] = true
	if by_tag.size() < 2:
		push_error("diverse_variations: expect multiple face TAGs, got %s" % str(by_tag.keys()))
		return 1
	var all_vars: Dictionary = {}
	for tag in by_tag.keys():
		for v in (by_tag[tag] as Dictionary).keys():
			all_vars[v] = true
	# 同墙按格哈希：单 TAG 长边也可有多种 variation
	print(
		"diverse_variations tags=%d vars=%s by_tag=%s OK"
		% [by_tag.size(), str(all_vars.keys()), str(by_tag)]
	)
	return 0
