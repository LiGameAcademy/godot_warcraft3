class_name Wc3CliffBuilder
extends RefCounted
## WC3 悬崖：独立于地面高度网格的竖直面 / 悬崖块 Mesh。
## 当前实现：在相邻 tilepoint 的 layerHeight 不连续处挤出垂直墙（占位几何）。
## 后续应替换为 CliffTypes 对应的悬崖模型瓦片（与官方 cliff tile 一致）。


## 返回 { mesh: ArrayMesh, surface_cliff: PackedInt32Array }
## surface_cliff[i] = cliffTilesets 索引。
static func build_cliff_mesh(hf: Dictionary) -> Dictionary:
	var meta := HeightfieldMeshBuilder.read_heightfield_meta(hf)
	var width: int = meta["width"]
	var height: int = meta["height"]
	var heights: Array = meta["heights"]
	var layers: Array = meta["layer_heights"]
	var cliff_tex: Array = meta["cliff_textures"]
	var center: Vector2 = meta["center"]
	var tile_size: float = meta["tile_size"]

	if layers.is_empty() or width < 2 or height < 2:
		return {}

	var buckets: Dictionary = {}

	# 水平边（ix ↔ ix+1）与竖直边（iy ↔ iy+1）
	for iy in range(height):
		for ix in range(width - 1):
			_try_edge(
				buckets, heights, layers, cliff_tex, width,
				ix, iy, ix + 1, iy, center, tile_size
			)
	for iy in range(height - 1):
		for ix in range(width):
			_try_edge(
				buckets, heights, layers, cliff_tex, width,
				ix, iy, ix, iy + 1, center, tile_size
			)

	if buckets.is_empty():
		return {}

	var keys: Array = buckets.keys()
	keys.sort()
	var ordered: Array = []
	var surface_cliff := PackedInt32Array()
	for key in keys:
		ordered.append(buckets[key])
		surface_cliff.append(int(key))

	return {
		"mesh": HeightfieldMeshBuilder.mesh_from_buckets(ordered),
		"surface_cliff": surface_cliff,
		"cliff_tilesets": meta["cliff_tilesets"],
	}


static func _try_edge(
	buckets: Dictionary,
	heights: Array,
	layers: Array,
	cliff_tex: Array,
	width: int,
	ax: int,
	ay: int,
	bx: int,
	by: int,
	center: Vector2,
	tile_size: float
) -> void:
	var ia := ay * width + ax
	var ib := by * width + bx
	if ia >= layers.size() or ib >= layers.size():
		return
	var la := int(layers[ia])
	var lb := int(layers[ib])
	if la == lb:
		return

	# 较高一侧决定悬崖贴图索引
	var hi := ia if la > lb else ib
	var cliff_key := int(cliff_tex[hi]) if hi < cliff_tex.size() else 0
	if not buckets.has(cliff_key):
		buckets[cliff_key] = HeightfieldMeshBuilder.empty_bucket()

	var ha := float(heights[ia])
	var hb := float(heights[ib])
	var pa := HeightfieldMeshBuilder.sample_vert(ax, ay, ha, center, tile_size)
	var pb := HeightfieldMeshBuilder.sample_vert(bx, by, hb, center, tile_size)
	# sample_vert 已含 WORLD_SCALE；垂直墙取两端 Y 的 min/max
	var y_lo := minf(pa.y, pb.y)
	var y_hi := maxf(pa.y, pb.y)
	if is_equal_approx(y_lo, y_hi):
		y_hi = y_lo + float(Wc3Coords.TILE_SIZE) * Wc3Coords.WORLD_SCALE * 0.25

	var a_lo := Vector3(pa.x, y_lo, pa.z)
	var b_lo := Vector3(pb.x, y_lo, pb.z)
	var a_hi := Vector3(pa.x, y_hi, pa.z)
	var b_hi := Vector3(pb.x, y_hi, pb.z)

	# 保证绕序朝外（粗略：从低层看向高层）
	if la < lb:
		HeightfieldMeshBuilder.append_quad(
			buckets[cliff_key], a_lo, b_lo, a_hi, b_hi,
			Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0)
		)
	else:
		HeightfieldMeshBuilder.append_quad(
			buckets[cliff_key], b_lo, a_lo, b_hi, a_hi,
			Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0)
		)
