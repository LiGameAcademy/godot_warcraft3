class_name Wc3WaterMesh
extends RefCounted
## 构建 HiveWE 式水面网格：含水格 + (waterH+offset) 高度 + 深度顶点色。
## 对齐 HiveWE water.vert：四角任一有 water 即画（含斜坡格，水面在坡 mesh 下方）。


const FLAG_WATER := Wc3Coords.FLAG_WATER


static func build(
	hf: Dictionary,
	params: Wc3WaterParams,
	height_bias_wc3: float = 0.0,
	meta: Dictionary = {}
) -> Dictionary:
	if meta.is_empty():
		meta = Wc3Heightfield.build_meta_from_dict(hf)
	var tp_w: int = meta["width"]
	var tp_h: int = meta["height"]
	var ground: Array = meta["heights"]
	var water_h: Array = meta["water_heights"]
	var flags: Array = meta["flags"]
	var center: Vector2 = meta["center"]
	var tile_size: float = meta["tile_size"]

	if tp_w < 2 or tp_h < 2 or ground.is_empty() or flags.is_empty():
		return {}
	if water_h.is_empty():
		water_h = ground

	var offset := params.height_offset_wc3() + height_bias_wc3
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	var cell_count := 0
	var under_ramp := 0

	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			# HiveWE：不因 ramp 跳过；斜坡/崖下也要有水面，避免岸边直角硬切
			if not has_water_flag(flags, tp_w, ix, iy):
				continue
			cell_count += 1
			var i00 := iy * tp_w + ix
			var i10 := i00 + 1
			var i01 := i00 + tp_w
			var i11 := i01 + 1

			var wh00 := float(water_h[i00]) + offset
			var wh10 := float(water_h[i10]) + offset
			var wh01 := float(water_h[i01]) + offset
			var wh11 := float(water_h[i11]) + offset

			var p00 := HeightfieldMesh.sample_vert(ix, iy, wh00, center, tile_size)
			var p10 := HeightfieldMesh.sample_vert(ix + 1, iy, wh10, center, tile_size)
			var p01 := HeightfieldMesh.sample_vert(ix, iy + 1, wh01, center, tile_size)
			var p11 := HeightfieldMesh.sample_vert(ix + 1, iy + 1, wh11, center, tile_size)

			var c00 := _vert_color(wh00, float(ground[i00]), params)
			var c10 := _vert_color(wh10, float(ground[i10]), params)
			var c01 := _vert_color(wh01, float(ground[i01]), params)
			var c11 := _vert_color(wh11, float(ground[i11]), params)

			# Water.slk cells：贴图跨 cells×cells 格（官方）；HiveWE/viewer 常误用每格 0..1
			var inv := 1.0 / maxf(params.cells, 1.0)
			var uv00 := Vector2(float(ix), float(iy)) * inv
			var uv10 := Vector2(float(ix + 1), float(iy)) * inv
			var uv01 := Vector2(float(ix), float(iy + 1)) * inv
			var uv11 := Vector2(float(ix + 1), float(iy + 1)) * inv
			_emit_tri(
				verts, norms, uvs, cols, indices,
				p00, p01, p11,
				uv00, uv01, uv11,
				c00, c01, c11
			)
			_emit_tri(
				verts, norms, uvs, cols, indices,
				p00, p11, p10,
				uv00, uv11, uv10,
				c00, c11, c10
			)

	if verts.is_empty():
		return {}

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "cell_count": cell_count, "under_ramp": under_ramp, "skipped_ramp": 0}


## 四角任一有 water 标志（原始 W3E / HiveWE water_exists）。
static func has_water_flag(flags: Array, tp_w: int, ix: int, iy: int) -> bool:
	var i00 := iy * tp_w + ix
	var i10 := i00 + 1
	var i01 := i00 + tp_w
	var i11 := i01 + 1
	if i11 >= flags.size():
		return false
	return (
		(int(flags[i00]) & FLAG_WATER) != 0
		or (int(flags[i10]) & FLAG_WATER) != 0
		or (int(flags[i01]) & FLAG_WATER) != 0
		or (int(flags[i11]) & FLAG_WATER) != 0
	)


## 开阔水面（岸浪用）：有 water 旗即算（斜坡重建前忽略 FLAG_RAMP）。
static func is_surface_water_tile(flags: Array, tp_w: int, ix: int, iy: int) -> bool:
	return has_water_flag(flags, tp_w, ix, iy)


static func _vert_color(water_wc3: float, ground_wc3: float, params: Wc3WaterParams) -> Color:
	var depth_tiles := (water_wc3 - ground_wc3) / 128.0
	return Wc3WaterParams.depth_color(
		depth_tiles,
		params.shallow_min,
		params.shallow_max,
		params.deep_min,
		params.deep_max
	)


static func _emit_tri(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	uvs: PackedVector2Array,
	cols: PackedColorArray,
	indices: PackedInt32Array,
	pa: Vector3, pb: Vector3, pc: Vector3,
	uva: Vector2, uvb: Vector2, uvc: Vector2,
	ca: Color, cb: Color, cc: Color
) -> void:
	var n := (pb - pa).cross(pc - pa).normalized()
	if n.is_zero_approx():
		n = Vector3.UP
	var base := verts.size()
	verts.append(pa)
	verts.append(pb)
	verts.append(pc)
	norms.append(n)
	norms.append(n)
	norms.append(n)
	uvs.append(uva)
	uvs.append(uvb)
	uvs.append(uvc)
	cols.append(ca)
	cols.append(cb)
	cols.append(cc)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
