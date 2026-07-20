class_name HeightfieldMeshBuilder
extends RefCounted
## 从规则高度格点生成 ArrayMesh（非 SurfaceTool）。
## 地形地面与水体共用同一套几何构建；贴图/材质由上层负责。


## 向输出缓冲追加一个格子（两个三角形，独立顶点，便于每面法线）。
static func append_quad(
	out: Dictionary,
	p00: Vector3,
	p10: Vector3,
	p01: Vector3,
	p11: Vector3,
	uv00: Vector2 = Vector2.ZERO,
	uv10: Vector2 = Vector2.RIGHT,
	uv01: Vector2 = Vector2.UP,
	uv11: Vector2 = Vector2.ONE,
	c00: Color = Color.WHITE,
	c10: Color = Color.WHITE,
	c01: Color = Color.WHITE,
	c11: Color = Color.WHITE
) -> void:
	var verts: PackedVector3Array = out["v"]
	var norms: PackedVector3Array = out["n"]
	var uvs: PackedVector2Array = out["uv"]
	var cols: PackedColorArray = out["c"]
	var indices: PackedInt32Array = out["idx"]
	var base: int = verts.size()

	var n0 := (p01 - p00).cross(p11 - p00).normalized()
	var n1 := (p11 - p00).cross(p10 - p00).normalized()
	if n0.is_zero_approx():
		n0 = Vector3.UP
	if n1.is_zero_approx():
		n1 = Vector3.UP

	verts.append(p00)
	verts.append(p01)
	verts.append(p11)
	verts.append(p00)
	verts.append(p11)
	verts.append(p10)
	norms.append(n0)
	norms.append(n0)
	norms.append(n0)
	norms.append(n1)
	norms.append(n1)
	norms.append(n1)
	uvs.append(uv00)
	uvs.append(uv01)
	uvs.append(uv11)
	uvs.append(uv00)
	uvs.append(uv11)
	uvs.append(uv10)
	cols.append(c00)
	cols.append(c01)
	cols.append(c11)
	cols.append(c00)
	cols.append(c11)
	cols.append(c10)
	for k in range(6):
		indices.append(base + k)
	out["v"] = verts
	out["n"] = norms
	out["uv"] = uvs
	out["c"] = cols
	out["idx"] = indices


static func empty_bucket() -> Dictionary:
	return {
		"v": PackedVector3Array(),
		"n": PackedVector3Array(),
		"uv": PackedVector2Array(),
		"c": PackedColorArray(),
		"idx": PackedInt32Array(),
	}


static func bucket_to_arrays(bucket: Dictionary) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = bucket["v"]
	arrays[Mesh.ARRAY_NORMAL] = bucket["n"]
	arrays[Mesh.ARRAY_TEX_UV] = bucket["uv"]
	arrays[Mesh.ARRAY_COLOR] = bucket["c"]
	arrays[Mesh.ARRAY_INDEX] = bucket["idx"]
	return arrays


static func mesh_from_buckets(buckets: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for b in buckets:
		var bucket: Dictionary = b
		if (bucket["v"] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bucket_to_arrays(bucket))
	return mesh


## 单 surface 高度网格：heights 为 width*height 行主序。
## include_cell(ix, iy) 可选；返回空则跳过该格。
static func build_uniform_mesh(
	width: int,
	height: int,
	heights: Array,
	center: Vector2,
	tile_size: float,
	include_cell: Callable = Callable()
) -> ArrayMesh:
	var bucket := empty_bucket()
	for iy in range(height - 1):
		for ix in range(width - 1):
			if include_cell.is_valid() and not include_cell.call(ix, iy):
				continue
			var i00 := iy * width + ix
			var i10 := i00 + 1
			var i01 := i00 + width
			var i11 := i01 + 1
			if i11 >= heights.size():
				continue
			var p00 := sample_vert(ix, iy, float(heights[i00]), center, tile_size)
			var p10 := sample_vert(ix + 1, iy, float(heights[i10]), center, tile_size)
			var p01 := sample_vert(ix, iy + 1, float(heights[i01]), center, tile_size)
			var p11 := sample_vert(ix + 1, iy + 1, float(heights[i11]), center, tile_size)
			var uv00 := Vector2(float(ix), float(iy))
			var uv10 := Vector2(float(ix + 1), float(iy))
			var uv01 := Vector2(float(ix), float(iy + 1))
			var uv11 := Vector2(float(ix + 1), float(iy + 1))
			append_quad(bucket, p00, p10, p01, p11, uv00, uv10, uv01, uv11)
	return mesh_from_buckets([bucket])


static func sample_vert(ix: int, iy: int, h: float, center: Vector2, tile_size: float) -> Vector3:
	var xy := Wc3Coords.tilepoint_wc3(ix, iy, center, tile_size)
	return Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, h)


static func read_heightfield_meta(hf: Dictionary) -> Dictionary:
	var co: Dictionary = hf.get("centerOffset", {})
	return {
		"width": int(hf.get("tilepointWidth", 0)),
		"height": int(hf.get("tilepointHeight", 0)),
		"tile_size": float(hf.get("tileSize", Wc3Coords.TILE_SIZE)),
		"center": Vector2(float(co.get("x", 0.0)), float(co.get("y", 0.0))),
		"heights": hf.get("heights", []) as Array,
		"water_heights": hf.get("waterHeights", []) as Array,
		"ground_textures": hf.get("groundTextures", []) as Array,
		"ground_variations": hf.get("groundVariations", []) as Array,
		"cliff_textures": hf.get("cliffTextures", []) as Array,
		"cliff_variations": hf.get("cliffVariations", []) as Array,
		"layer_heights": hf.get("layerHeights", []) as Array,
		"flags": hf.get("flagsPacked", []) as Array,
		"ground_tilesets": hf.get("groundTilesets", []) as Array,
		"cliff_tilesets": hf.get("cliffTilesets", []) as Array,
	}
