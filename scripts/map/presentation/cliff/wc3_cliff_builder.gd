class_name Wc3CliffBuilder
extends RefCounted

## 悬崖表现装配：只读 placements + Catalog 资产路径 → MultiMesh 分组。
## 禁止：拓扑判断、改 Heightfield、过滤 TAG（Logic 已保证列表可渲染）。
## 变体随机性在 Catalog/Logic（按格 BL / 空间哈希；同墙可不同变体）。
## 勿对 cliff UV 做实例抖动（易采到贴图白边）。
##
## 变换两套（勿混用）：
##   Cliffs     → instance_transform（经典锚 ix+1，无解旋）
##   CliffTrans → instance_transform_trans（HiveWE modern (y,-x) 解旋 + 锚 ix）


static func build_from_placements(
	placements: Array[Wc3CliffPlacement],
	cliff_catalog: Wc3CliffCatalog,
	center: Vector2,
	tile_size: float
) -> Wc3CliffBuildResult:
	var result := Wc3CliffBuildResult.new()
	if placements.is_empty() or cliff_catalog == null:
		return result

	var buckets: Dictionary = {} # key → Group
	var missing_logged: Dictionary = {}

	for p in placements:
		if p == null:
			continue
		var glb: String = cliff_catalog.resolve_glb(p.model_dir, p.tag, p.variation)
		if glb.is_empty():
			if not missing_logged.has("C:" + p.tag):
				missing_logged["C:" + p.tag] = true
				push_warning("悬崖模型缺失: %s/%s" % [p.model_dir, p.tag])
			result.missing += 1
			continue
		var xf := instance_transform(p.ix, p.iy, p.base_layer, center, tile_size)
		_bucket_add(buckets, glb, p.cliff_tex_index, xf, Vector2i(p.ix, p.iy), p.base_layer)
		result.placed_cliffs += 1

	for k in buckets.keys():
		result.groups.append(buckets[k] as Wc3CliffBuildResult.Group)
	return result


## CliffTrans：必须用解旋变换；勿走 build_from_placements（直崖锚点）。
static func build_from_ramp_placements(
	placements: Array[Wc3RampPlacement],
	cliff_catalog: Wc3CliffCatalog,
	center: Vector2,
	tile_size: float
) -> Wc3CliffBuildResult:
	var result := Wc3CliffBuildResult.new()
	if placements.is_empty() or cliff_catalog == null:
		return result

	var buckets: Dictionary = {}
	var missing_logged: Dictionary = {}

	for p in placements:
		if p == null or not p.has_glb:
			continue
		var glb: String = cliff_catalog.resolve_glb(p.model_dir, p.tag, p.variation)
		if glb.is_empty():
			if not missing_logged.has("R:" + p.tag):
				missing_logged["R:" + p.tag] = true
				push_warning("斜坡模型缺失: %s/%s" % [p.model_dir, p.tag])
			result.missing += 1
			continue
		var xf := instance_transform_trans(p.ix, p.iy, p.base_layer, center, tile_size)
		_bucket_add(buckets, glb, p.cliff_tex_index, xf, Vector2i(p.ix, p.iy), p.base_layer)
		result.placed_cliffs += 1

	for k in buckets.keys():
		result.groups.append(buckets[k] as Wc3CliffBuildResult.Group)
	return result


static func _bucket_add(
	buckets: Dictionary,
	glb: String,
	tex_idx: int,
	xf: Transform3D,
	tile: Vector2i,
	base_layer: int
) -> void:
	var key := "%s|%d" % [glb, tex_idx]
	if not buckets.has(key):
		var g := Wc3CliffBuildResult.Group.new()
		g.glb = glb
		g.cliff_tex_index = tex_idx
		buckets[key] = g
	var group: Wc3CliffBuildResult.Group = buckets[key] as Wc3CliffBuildResult.Group
	group.transforms.append(xf)
	group.tiles.append(tile)
	group.base_layers.append(base_layer)


## 直崖：局部 X∈[-128,0]，锚 (ix+1, iy)；Z=(base-2)*128。无解旋。
static func instance_transform(
	ix: int,
	iy: int,
	base_layer: int,
	center: Vector2,
	tile_size: float
) -> Transform3D:
	var wc3_x := float(ix + 1) * tile_size + center.x
	var wc3_y := float(iy) * tile_size + center.y
	var wc3_z := float(base_layer - 2) * 128.0
	var origin := Wc3Coords.wc3_xy_to_godot(wc3_x, wc3_y, wc3_z)
	return Transform3D(Basis.from_scale(Vector3.ONE * Wc3Coords.WORLD_SCALE), origin)


## CliffTrans：对齐 HiveWE cliff.vert
##   rotated = (mdx.y, -mdx.x, mdx.z)/128 + (ix, iy, min-2)
## GLB 顶点已是 (mdx.x, mdx.z, -mdx.y)；此处用 Basis 完成解旋，锚点为 (ix,iy)（无 +1）。
static func instance_transform_trans(
	ix: int,
	iy: int,
	base_layer: int,
	center: Vector2,
	tile_size: float
) -> Transform3D:
	var s: float = Wc3Coords.WORLD_SCALE
	# columns: gx→(0,0,s), gy→(0,s,0), gz→(-s,0,0)
	var basis := Basis(Vector3(0.0, 0.0, s), Vector3(0.0, s, 0.0), Vector3(-s, 0.0, 0.0))
	var wc3_x := float(ix) * tile_size + center.x
	var wc3_y := float(iy) * tile_size + center.y
	var wc3_z := float(base_layer - 2) * 128.0
	var origin := Wc3Coords.wc3_xy_to_godot(wc3_x, wc3_y, wc3_z)
	return Transform3D(basis, origin)
