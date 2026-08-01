class_name MapDoodadLayer
extends Node3D
## 静物 / 装饰物层：GLB 实例或按 Geoset 分片 MultiMesh。

const _Pe2 := preload("res://scripts/map/presentation/effects/wc3_pe2_particles.gd")


@export var try_load_glb: bool = true
@export var multimesh_threshold: int = 8

var _catalog: Wc3IdCatalog
var _cache: MapModelCache
var last_placed: int = 0
var last_placeholder: int = 0


func setup(catalog: Wc3IdCatalog, cache: MapModelCache) -> void:
	_catalog = catalog
	_cache = cache


## 用 Document 的 doodads[] 全量重建（编辑器撤销/进入装饰物模式）。
func rebuild_from_list(hf: Wc3Heightfield, doodads: Array) -> void:
	var ctx := MapBuildContext.new()
	ctx.heightfield = hf
	ctx.doodads = {"doodads": doodads}
	# catalog/cache 已在 setup
	build(ctx)


## 增量追加一条（笔刷放置）；返回是否成功实例化。
func add_one(d: Dictionary, hf: Wc3Heightfield) -> bool:
	if d.is_empty() or _catalog == null:
		return false
	var type_id := str(d.get("id", ""))
	var variation := int(d.get("variation", 0))
	var glb := _catalog.converted_glb_path(type_id, variation) if try_load_glb else ""
	var has_anim := (not glb.is_empty()) and _cache != null and _cache.glb_has_animation(glb)
	if not glb.is_empty() and _cache != null:
		_place_doodad_instance(type_id, glb, d, has_anim)
		last_placed += 1
	else:
		_place_doodad_placeholder(type_id, d)
		last_placeholder += 1
	if hf != null:
		_refresh_one_height(get_child(get_child_count() - 1), hf)
	return true


## 按 creationNumber 移除 Present 节点（MultiMesh 组内无法精确删 → 返回 false，调用方应全量 rebuild）。
func remove_by_creation_number(creation_number: int) -> bool:
	var node := find_by_creation_number(creation_number)
	if node == null:
		return false
	remove_child(node)
	node.free()
	return true


## 单实例 Present（非 MultiMesh 组内条目）。找不到返回 null。
func find_by_creation_number(creation_number: int) -> Node3D:
	if creation_number < 0:
		return null
	for c in get_children():
		if not (c is Node3D):
			continue
		var d: Dictionary = c.get_meta("doodad_data", {})
		if d.is_empty():
			continue
		if int(d.get("creationNumber", -1)) != creation_number:
			continue
		return c as Node3D
	return null


func _refresh_one_height(node: Node, hf: Wc3Heightfield) -> void:
	if node == null or not (node is Node3D) or hf == null or not hf.is_valid():
		return
	var d: Dictionary = node.get_meta("doodad_data", {})
	if d.is_empty():
		return
	var pos: Dictionary = d.get("position", {})
	var wx: float = float(pos.get("x", 0.0))
	var wy: float = float(pos.get("y", 0.0))
	var new_z_wc3: float = hf.interpolated_height(wx, wy)
	# WC3 Z→Godot Y；勿写 position.z（那是水平 -WC3.Y）
	(node as Node3D).position = Wc3Coords.wc3_xy_to_godot(wx, wy, new_z_wc3)
	pos["z"] = new_z_wc3
	d["position"] = pos
	node.set_meta("doodad_data", d)


func build(ctx: MapBuildContext) -> void:
	_clear_children()
	last_placed = 0
	last_placeholder = 0
	if ctx == null:
		return
	var doodads: Array = ctx.doodads.get("doodads", [])
	if doodads.is_empty():
		return

	var groups: Dictionary = {}
	for d in doodads:
		var type_id := str(d.get("id", ""))
		var variation := int(d.get("variation", 0))
		var key := "%s#%d" % [type_id, variation]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(d)

	var glb_groups := 0
	var ph_groups := 0
	var mm_groups := 0
	var anim_instances := 0
	var helper_count := 0
	for key_variant in groups.keys():
		var key := str(key_variant)
		var list: Array = groups[key]
		var parts: PackedStringArray = key.split("#")
		var type_id: String = parts[0] if parts.size() > 0 else ""
		var variation: int = int(parts[1]) if parts.size() > 1 else 0
		var info: Dictionary = _catalog.lookup(type_id) if _catalog != null else {}
		var glb := _catalog.converted_glb_path(type_id, variation) if try_load_glb else ""
		var has_anim := (not glb.is_empty()) and _cache.glb_has_animation(glb)
		var use_helper := bool(info.get("use_click_helper", false))
		var has_pe2: bool = (not glb.is_empty()) and _Pe2.has_emitters(glb)
		# 空壳 / Click Helper / 动画 / PE2：不走 MultiMesh（需逐实例挂 helper/粒子或播 Stand）
		var allow_mm: bool = (
			not glb.is_empty()
			and (not has_anim)
			and (not use_helper)
			and (not has_pe2)
			and list.size() >= multimesh_threshold
			and _cache.glb_has_mesh(glb)
		)

		if allow_mm:
			if _place_multimesh_group(type_id, variation, glb, list):
				glb_groups += 1
				mm_groups += 1
				last_placed += list.size()
				continue

		if not glb.is_empty():
			for d in list:
				var placed_helpers := _place_doodad_instance(type_id, glb, d, has_anim)
				last_placed += 1
				if has_anim:
					anim_instances += 1
				if placed_helpers:
					helper_count += 1
			glb_groups += 1
		else:
			for d in list:
				_place_doodad_placeholder(type_id, d)
				last_placeholder += 1
				helper_count += 1
			ph_groups += 1

	print(
		"Doodads: placed=%d placeholder=%d animated=%d helpers=%d groups(glb=%d mm=%d ph=%d)"
		% [last_placed, last_placeholder, anim_instances, helper_count, glb_groups, mm_groups, ph_groups]
	)

	# 按 heightfield 重算所有 doodad Y（HivEWE change_doodad_heights 等价）。
	# JSON 原始 pos.z 被覆盖；后续改地形时 MapLoader.rebuild_* 会再刷一次。
	_apply_height_update(ctx.heightfield)


func _place_multimesh_group(type_id: String, variation: int, glb: String, list: Array) -> bool:
	var parts: Array = _cache.mesh_parts_from_glb(glb)
	if parts.is_empty():
		return false
	var xforms: Array[Transform3D] = []
	xforms.resize(list.size())
	for i in range(list.size()):
		xforms[i] = _doodad_transform(list[i])

	var root := Node3D.new()
	root.name = "MM_%s_%d" % [type_id, variation]
	for pi in range(parts.size()):
		var part: Dictionary = parts[pi]
		var mesh: Mesh = part.get("mesh") as Mesh
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Part%d" % pi
		mmi.multimesh = mm
		var mat: Material = part.get("material") as Material
		if mat:
			mmi.material_override = mat
		root.add_child(mmi)
	if root.get_child_count() == 0:
		root.free()
		return false
	add_child(root)
	return true


func _place_doodad_instance(type_id: String, glb: String, d: Dictionary, play_anim: bool = false) -> bool:
	var node := _cache.instance_glb(glb)
	if node == null:
		_place_doodad_placeholder(type_id, d)
		last_placeholder += 1
		last_placed -= 1
		return true
	node.name = "%s_%s" % [type_id, str(d.get("creationNumber", 0))]
	_apply_doodad_xform(node, d, true)
	node.set_meta("doodad_data", d)  # 供 refresh_heights 重算 Y 用
	var info: Dictionary = _catalog.lookup(type_id) if _catalog != null else {}
	var has_mesh: bool = MapPlaceholders.node_has_mesh(node)
	_Pe2.attach_to(node, glb)
	var helpers := MapPlaceholders.attach_editor_helpers(node, info, has_mesh)
	add_child(node)
	if play_anim:
		_cache.autoplay_stand(node, true)
	elif not has_mesh:
		# 空壳也可能带空 Stand；仍尝试播，失败则依赖 EffectParticles
		_cache.autoplay_stand(node, true)
	return helpers


func _place_doodad_placeholder(type_id: String, d: Dictionary) -> void:
	var info: Dictionary = _catalog.lookup(type_id) if _catalog != null else {}
	# 有 useClickHelper / 缺模：用 WE 粉黑棋盘盒，而不是绿圆柱
	var node: Node3D
	if bool(info.get("use_click_helper", false)):
		node = Node3D.new()
		node.name = "%s_%s" % [type_id, str(d.get("creationNumber", 0))]
		node.add_child(MapPlaceholders.make_click_helper(float(info.get("sel_size", 0.0))))
		node.add_child(MapPlaceholders.make_effect_particles())
		_apply_doodad_xform(node, d, true)
	else:
		node = MapPlaceholders.make_entity(type_id, -1, false)
		node.scale *= 0.8
		_apply_doodad_xform(node, d, false)
	node.set_meta("doodad_data", d)
	add_child(node)


## 公开 API：按 heightfield 重算所有 doodad 的 Y（change_doodad_heights 等价）。
## 改地形笔刷时由 MapLoader.rebuild_* 调。doodad Y 重新贴合新地形。
## 撤销时：MapDocument.heightfield 回到 before 状态 → 再次 refresh → Y 自动回到原值。
## 无需独立 doodad undo 通道（[docs/hivewe/OPERATORS.md §6.4]）。
## [param hf: Wc3Heightfield] 高度场
func refresh_heights(hf: Wc3Heightfield) -> void:
	_apply_height_update(hf)


## 内部：遍历 children，按 doodad_data meta 里的 (x,y) 重算 Z。
## hf 越界或 null 时跳过（不抛错）。children 为空时 no-op。
func _apply_height_update(hf: Wc3Heightfield) -> void:
	if hf == null or not hf.is_valid():
		return
	for c in get_children():
		if not (c is Node3D):
			continue
		var d: Dictionary = c.get_meta("doodad_data", {})
		if d.is_empty():
			continue
		var pos: Dictionary = d.get("position", {})
		var wx: float = float(pos.get("x", 0.0))
		var wy: float = float(pos.get("y", 0.0))
		var new_z_wc3: float = hf.interpolated_height(wx, wy)
		c.position = Wc3Coords.wc3_xy_to_godot(wx, wy, new_z_wc3)
		pos["z"] = new_z_wc3
		d["position"] = pos
		c.set_meta("doodad_data", d)


func _apply_doodad_xform(node: Node3D, d: Dictionary, multiply_imported_scale: bool) -> void:
	var pos: Dictionary = d.get("position", {})
	var scale_data: Dictionary = d.get("scale", {})
	var angle := float(d.get("angle", 0.0))
	node.position = Wc3Coords.wc3_xy_to_godot(
		float(pos.get("x", 0.0)),
		float(pos.get("y", 0.0)),
		float(pos.get("z", 0.0))
	)
	node.rotation.y = Wc3Coords.yaw_wc3_to_godot(angle)
	var sx := float(scale_data.get("x", 1.0))
	var sy := float(scale_data.get("y", 1.0))
	var sz := float(scale_data.get("z", 1.0))
	if multiply_imported_scale:
		# GLB 根节点已含 MODEL_SCALE=0.01，只乘地图缩放
		var b := node.scale
		node.scale = Vector3(b.x * sx, b.y * sz, b.z * sy)
	else:
		node.scale = Vector3(sx, sz, sy) * Wc3Coords.WORLD_SCALE


func _doodad_transform(d: Dictionary) -> Transform3D:
	var pos: Dictionary = d.get("position", {})
	var scale_data: Dictionary = d.get("scale", {})
	var angle := float(d.get("angle", 0.0))
	var gpos := Wc3Coords.wc3_xy_to_godot(
		float(pos.get("x", 0.0)),
		float(pos.get("y", 0.0)),
		float(pos.get("z", 0.0))
	)
	var sx := float(scale_data.get("x", 1.0))
	var sy := float(scale_data.get("y", 1.0))
	var sz := float(scale_data.get("z", 1.0))
	# 网格顶点仍是 WC3 单位，需 WORLD_SCALE（与 GLB 根 scale 等价）
	var xf := Transform3D.IDENTITY
	xf = xf.scaled(Vector3(sx, sz, sy) * Wc3Coords.WORLD_SCALE)
	xf = xf.rotated(Vector3.UP, Wc3Coords.yaw_wc3_to_godot(angle))
	xf.origin = gpos
	return xf


func _clear_children() -> void:
	for c in get_children():
		c.queue_free()
