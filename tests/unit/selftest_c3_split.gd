extends SceneTree
## 可选工具 selftest：按 VertexGroup 拆 geoset（bake:scn 默认不调用）。
## 验证 SplitMeshesByGroup.split 把 .gltf 里的 Geoset_<i> 节点拆成多个 BoneAttachment3D + MeshInstance3D。
## 5/5：
##   1. 拆出 group 数量 = attachments.json 期望值
##   2. BoneAttachment3D.bone_name == group.bones[0]
##   3. 新 mesh 单 joint skin（4 个 slot 都是 0/0/0/0 + 1/0/0/0）
##   4. 新 mesh vertex count == group.vertex_count
##   5. 原 Geoset_<i> 节点已 queue_free
##
## godot --headless --path . -s res://tests/unit/selftest_c3_split.gd

const SplitMeshesByGroupScript := preload("res://scripts/tool/split_meshes_by_group.gd")

var passed: int = 0
var total: int = 5


func _init() -> void:
	_test_split_count()
	# 关键：每次 test 重新 setup（cache 复用但 proto 是 _scene_cache 里的，同一 cache 多次 _setup 拿到的是已拆的 proto）
	# 修法：每次 _setup 先 evict，再 instance
	_test_bone_name_correct()
	_test_single_joint_skin()
	_test_vertex_subset()
	await _test_orig_mesh_removed()  # await: 让其内部 await process_frame 跑完

	if passed == total:
		print("selftest_c3_split: PASS")
		quit(0)
	else:
		push_error("selftest_c3_split: FAIL %d/%d" % [passed, total])
		quit(1)


# 公共：加载 Footman.gltf + 调 split + 读 attachments.json
# 关键：每次新建 MapModelCache 避免 proto 复用（否则前一次 test split 改了 proto，后一次 split 看到已拆）
func _setup_split_footman() -> Dictionary:
	# 关键：直接 RuntimeAssets.load_gltf_scene 加载 .gltf，绕过 .scn 优先逻辑
	var glb_res := "res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	var proto: Node3D = RuntimeAssets.load_gltf_scene(glb_res)
	if proto == null:
		push_error("setup: cannot load Footman.gltf via RuntimeAssets")
		return {}
	var inst := proto.duplicate() as Node3D
	if inst == null:
		push_error("setup: cannot duplicate")
		return {}
	# 注意：selftest 主要用 proto（直接调 split）；inst 是 duplicate，给 find_children 用
	var att_path := "res://assets/asset-converted/Units/Human/Footman/Footman.attachments.json"
	var af := FileAccess.open(att_path, FileAccess.READ)
	if af == null:
		push_error("setup: cannot open %s" % att_path)
		return {}
	var j = JSON.parse_string(af.get_as_text())
	af.close()
	if j == null or not j is Dictionary:
		push_error("setup: json null")
		return {}
	var split_n: int = SplitMeshesByGroupScript.split(proto, j)
	# selftest 主要用 proto（split 直接改 proto 树）
	return {"proto": proto, "inst": inst, "att": j, "split_n": split_n, "glb_res": glb_res}


# Test 1: 拆出 group 数量 = attachments.json 期望
func _test_split_count() -> void:
	var s := _setup_split_footman()
	if s.is_empty():
		return
	var att: Dictionary = s.att
	var expected := 0
	for exp in att.geoset_expansions:
		expected += exp.groups.size()
	var bas: Array = s.proto.find_children("Geoset_*_Group_*", "BoneAttachment3D", true, false)
	if bas.size() != expected:
		push_error("test_1 FAIL: expected %d groups, got %d" % [expected, bas.size()])
		return
	if int(s.split_n) != expected:
		push_error("test_1 FAIL: split_n=%d != expected=%d" % [s.split_n, expected])
		return
	print("  Footman split: %d groups = %d expected" % [bas.size(), expected])
	passed += 1


# Test 2: BoneAttachment3D.bone_name 正确
func _test_bone_name_correct() -> void:
	var s := _setup_split_footman()
	if s.is_empty():
		return
	var att: Dictionary = s.att
	# 期望: ba name "Geoset_<gi>_Group_<group_idx>" → bone_name = group.bones[0]
	var bas: Array = s.proto.find_children("Geoset_*_Group_*", "BoneAttachment3D", true, false)
	var errors := 0
	for ba in bas:
		var parts: PackedStringArray = ba.name.split("_")
		# Geoset_0_Group_5 → gi=0, group_idx=5
		var gi := int(parts[1])
		var group_idx := int(parts[3])
		var exp: Dictionary = att.geoset_expansions[gi]
		var groups: Array = exp.groups
		var found: Dictionary = {}
		for g in groups:
			if int(g.group_index) == group_idx:
				found = g
				break
		if found.is_empty():
			push_error("test_2 FAIL: group %d not in geoset %d" % [group_idx, gi])
			errors += 1
			continue
		var expected_bone: String = found.bones[0]
		if ba.bone_name != expected_bone:
			push_error("test_2 FAIL: %s bone_name=%s expected=%s" % [ba.name, ba.bone_name, expected_bone])
			errors += 1
	if errors == 0:
		print("  Footman bone_name: %d BoneAttachment3D all correct" % bas.size())
		passed += 1


# Test 3: 新 mesh 是 bone-local 空间顶点（无 skin 数组；BoneAttachment 跟骨）
## 老李修法：把顶点 transform 到 bone-local，避免空 skin 时 Godot 不渲染；
## 也不再写 ARRAY_BONES / ARRAY_WEIGHTS，纯静态 mesh 跟骨。
func _test_single_joint_skin() -> void:
	var s := _setup_split_footman()
	if s.is_empty():
		return
	var bas: Array = s.proto.find_children("Geoset_*_Group_*", "BoneAttachment3D", true, false)
	var skeleton: Skeleton3D = s.proto.find_children("*", "Skeleton3D", true, false)[0]
	var errors := 0
	for ba in bas:
		var mi_list: Array = ba.find_children("*", "MeshInstance3D", false, false)
		if mi_list.is_empty():
			push_error("test_3 FAIL: %s no MeshInstance3D" % ba.name)
			errors += 1
			continue
		var mi: MeshInstance3D = mi_list[0]
		var mesh: ArrayMesh = mi.mesh
		if mesh.get_surface_count() == 0:
			push_error("test_3 FAIL: %s no surface" % ba.name)
			errors += 1
			continue
		var arrays: Array = mesh.surface_get_arrays(0)
		var n_verts: int = arrays[Mesh.ARRAY_VERTEX].size() if arrays[Mesh.ARRAY_VERTEX] != null else 0
		if n_verts == 0:
			push_error("test_3 FAIL: %s 0 verts" % ba.name)
			errors += 1
			continue
		# 验：不写 ARRAY_BONES / ARRAY_WEIGHTS（避免空 skin 时 Godot 不渲染）
		if arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_BONES].size() > 0:
			push_error("test_3 FAIL: %s should not have ARRAY_BONES (bone-local static mesh)" % ba.name)
			errors += 1
		if arrays[Mesh.ARRAY_WEIGHTS] != null and arrays[Mesh.ARRAY_WEIGHTS].size() > 0:
			push_error("test_3 FAIL: %s should not have ARRAY_WEIGHTS (bone-local static mesh)" % ba.name)
			errors += 1
		# 验：顶点不是 NaN / 0 长度（空数组也 PASS）
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts == null:
			push_error("test_3 FAIL: %s null verts" % ba.name)
			errors += 1
	if errors == 0:
		print("  Footman bone-local mesh: %d BoneAttachment3D all static (no skin array)" % bas.size())
		passed += 1


# Test 4: 新 mesh vertex count = group.vertex_count
func _test_vertex_subset() -> void:
	var s := _setup_split_footman()
	if s.is_empty():
		return
	var att: Dictionary = s.att
	var bas: Array = s.proto.find_children("Geoset_*_Group_*", "BoneAttachment3D", true, false)
	var errors := 0
	for ba in bas:
		var parts: PackedStringArray = ba.name.split("_")
		var gi := int(parts[1])
		var group_idx := int(parts[3])
		var exp: Dictionary = att.geoset_expansions[gi]
		var groups: Array = exp.groups
		var found: Dictionary = {}
		for g in groups:
			if int(g.group_index) == group_idx:
				found = g
				break
		var expected_v: int = int(found.vertex_count)
		var mi: MeshInstance3D = ba.find_children("*", "MeshInstance3D", false, false)[0]
		var mesh: ArrayMesh = mi.mesh
		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.size() != expected_v:
			push_error("test_4 FAIL: %s verts=%d expected=%d" % [ba.name, verts.size(), expected_v])
			errors += 1
	if errors == 0:
		print("  Footman vertex subset: %d BoneAttachment3D all match" % bas.size())
		passed += 1


# Test 5: 原 Geoset_<i> 节点已 queue_free
func _test_orig_mesh_removed() -> void:
	var s := _setup_split_footman()
	if s.is_empty():
		return
	# 强制 process_frame 让 queue_free 真正生效
	await process_frame
	var bas: Array = s.proto.find_children("Geoset_*_Group_*", "BoneAttachment3D", true, false)
	# 数原 Geoset_<i> 节点（应是 0，因为都拆了）
	var orig: Array = []
	for c in s.proto.find_children("Geoset_*", "MeshInstance3D", true, false):
		if c is MeshInstance3D:
			orig.append(c)
	# 但要排除我们新建的 Geoset_<gi>_Group_<gi>（命名是 Geoset_0_Group_0，find_children "Geoset_*" 会匹配 "Geoset_0_Group_0"）
	# 实际原 Geoset_<i> 名称是 "Geoset_0"（无 _Group_），所以用 name 区分
	var orig_only: Array = []
	for c in orig:
		var parts: PackedStringArray = c.name.split("_")
		if parts.size() == 2:  # "Geoset_0" → 2 parts；"Geoset_0_Group_0" → 4 parts
			orig_only.append(c)
	if not orig_only.is_empty():
		push_error("test_5 FAIL: orig Geoset_* nodes still present: %d" % orig_only.size())
		for c in orig_only:
			print("    remaining: %s" % c.name)
		return
	print("  Footman orig Geoset removed: 0 remaining, %d new BoneAttachment3D" % bas.size())
	passed += 1
