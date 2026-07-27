class_name Wc3CliffBuilder
extends RefCounted

## 悬崖表现装配：只读 placements + Catalog 资产路径 → MultiMesh 分组。
## 禁止：拓扑判断、改 Heightfield、过滤 TAG（Logic 已保证列表可渲染）。
## 变体随机性在 Catalog/Logic（TAG 墙段空间哈希）；勿对 cliff UV 做实例抖动（易采到贴图白边）。


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
		_bucket_add(buckets, glb, p.cliff_tex_index, xf)
		result.placed_cliffs += 1

	for k in buckets.keys():
		result.groups.append(buckets[k] as Wc3CliffBuildResult.Group)
	return result


static func _bucket_add(
	buckets: Dictionary, glb: String, tex_idx: int, xf: Transform3D
) -> void:
	var key := "%s|%d" % [glb, tex_idx]
	if not buckets.has(key):
		var g := Wc3CliffBuildResult.Group.new()
		g.glb = glb
		g.cliff_tex_index = tex_idx
		buckets[key] = g
	(buckets[key] as Wc3CliffBuildResult.Group).transforms.append(xf)


## 坐标映射（表现）：Cliffs 局部 X∈[-128,0]，锚 (ix+1, iy)；Z=(base-2)*128。
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
