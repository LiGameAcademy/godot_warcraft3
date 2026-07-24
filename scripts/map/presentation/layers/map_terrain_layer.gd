class_name MapTerrainLayer
extends Node3D

## 地面表现层：根据 Heightfield 画网格 + 挂 Catalog 贴图。
## 底层三角/四边形由 HeightfieldMesh 提供；本层只做 WC3 地表规则与组网。


const GROUND_MATERIAL: ShaderMaterial = preload(
	"res://scripts/map/presentation/materials/wc3_ground_material.tres"
)

## 官方图集角权重（非教学口诀 BL=1）：BR=1 BL=2 TR=4 TL=8
const ATLAS_BR := 1
const ATLAS_BL := 2
const ATLAS_TR := 4
const ATLAS_TL := 8

@onready var _ground: HeightfieldMesh = $Ground

var last_gap_count: int = 0
var _ground_mat: ShaderMaterial


func build(ctx) -> void:
	_ground.clear_mesh()
	_ground_mat = null
	last_gap_count = 0
	ctx.ensure_cliff_topology()

	var ground_tilesets: Array = ctx.hf.get("groundTilesets", [])
	if ground_tilesets.is_empty() and ctx.heightfield != null:
		ground_tilesets = ctx.heightfield.ground_tilesets
	if ground_tilesets.is_empty():
		push_warning("MapTerrainLayer: groundTilesets 为空")
		return

	var extended := Wc3GroundTileCatalog.build_extended_flags(ground_tilesets, ctx.tiles)
	var built := _build_ground_mesh(
		ctx.hf, extended, ctx.tiles, ctx.meta, ctx.cliff_romp
	)
	if built.is_empty():
		push_warning("MapTerrainLayer: 地面网格为空")
		return

	var tex_array := Wc3GroundTileCatalog.build_texture_array(ground_tilesets, ctx.tiles)
	if tex_array == null:
		push_warning("MapTerrainLayer: Texture2DArray 失败")
		return

	last_gap_count = int(built.get("gap_count", 0))
	# commit 已写入 _ground.mesh

	var mat: ShaderMaterial = GROUND_MATERIAL.duplicate() as ShaderMaterial
	mat.set_shader_parameter("tilesets", tex_array)
	mat.set_shader_parameter("world_scale", Wc3Coords.WORLD_SCALE)
	mat.set_shader_parameter("dbg_center_offset", ctx.meta.get("center", Vector2.ZERO))
	mat.set_shader_parameter("dbg_tile_size", float(ctx.meta.get("tile_size", Wc3Coords.TILE_SIZE)))
	_ground_mat = mat
	_ground.apply_material(mat)
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var stats: Dictionary = ctx.cliff_gap_stats
	print(
		"Terrain gaps: %d rampDecks=%d (cliff=%d ramp_tiles=%d ramp_models=%d / tiles=%d)"
		% [
			last_gap_count,
			int(built.get("ramp_deck_count", 0)),
			int(stats.get("cliffs", 0)),
			int(stats.get("ramps", 0)),
			int(stats.get("ramp_models", 0)),
			int(stats.get("tiles", 0)),
		]
	)


func set_debug_grid(show_tile: bool, show_path: bool, show_fine: bool) -> void:
	if _ground_mat == null:
		return
	_ground_mat.set_shader_parameter("dbg_grid_tile", show_tile)
	_ground_mat.set_shader_parameter("dbg_grid_path", show_path)
	_ground_mat.set_shader_parameter("dbg_grid_fine", show_fine)


## 返回 { mesh, gap_count, ramp_deck_count }
func _build_ground_mesh(
	hf: Dictionary,
	extended_flags: PackedByteArray,
	tiles: Wc3TerrainTiles,
	meta: Dictionary,
	romp: PackedByteArray
) -> Dictionary:
	if meta.is_empty():
		meta = Wc3Heightfield.build_meta_from_dict(hf)
	var width: int = int(meta["width"])
	var height: int = int(meta["height"])
	var heights: Array = meta["heights"]
	var ground_tex: Array = meta["ground_textures"]
	var ground_var: Array = meta["ground_variations"]
	var layer_heights: Array = meta["layer_heights"]
	var flags: Array = meta["flags"]
	var cliff_tex: Array = meta["cliff_textures"]
	var ground_tilesets: Array = meta["ground_tilesets"]
	var cliff_tilesets: Array = meta["cliff_tilesets"]
	var center: Vector2 = meta["center"]
	var tile_size: float = float(meta["tile_size"])
	if romp.is_empty():
		romp = Wc3CliffTiles.collect_ramp_placements(hf, meta, tiles)["romp"]

	var cliff_to_ground: PackedInt32Array = _build_cliff_to_ground(
		cliff_tilesets, ground_tilesets, tiles
	)

	if width < 2 or height < 2 or heights.size() < width * height:
		push_error("MapTerrainLayer: heightfield 尺寸无效")
		return {}

	_ground.begin_build(true)
	var gap_count := 0

	for iy in range(height - 1):
		for ix in range(width - 1):
			var i00 := iy * width + ix
			if Wc3CliffTiles.should_leave_gap(layer_heights, flags, width, height, ix, iy, romp):
				gap_count += 1
				continue

			var t_bl := corner_texture(
				ground_tex, layer_heights, cliff_tex, cliff_to_ground, width, height, ix, iy
			)
			var t_br := corner_texture(
				ground_tex, layer_heights, cliff_tex, cliff_to_ground, width, height, ix + 1, iy
			)
			var t_tl := corner_texture(
				ground_tex, layer_heights, cliff_tex, cliff_to_ground, width, height, ix, iy + 1
			)
			var t_tr := corner_texture(
				ground_tex, layer_heights, cliff_tex, cliff_to_ground, width, height, ix + 1, iy + 1
			)

			var layers := _build_layers(
				t_bl, t_br, t_tl, t_tr,
				_var_at(ground_var, i00),
				extended_flags
			)

			var p_bl := HeightfieldMesh.sample_vert(
				ix, iy, _raw_height(heights, width, ix, iy), center, tile_size
			)
			var p_br := HeightfieldMesh.sample_vert(
				ix + 1, iy, _raw_height(heights, width, ix + 1, iy), center, tile_size
			)
			var p_tl := HeightfieldMesh.sample_vert(
				ix, iy + 1, _raw_height(heights, width, ix, iy + 1), center, tile_size
			)
			var p_tr := HeightfieldMesh.sample_vert(
				ix + 1, iy + 1, _raw_height(heights, width, ix + 1, iy + 1), center, tile_size
			)

			_ground.add_quad(p_bl, p_br, p_tl, p_tr, layers["tex"], layers["var"])

	var mesh := _ground.commit_build()
	return {
		"mesh": mesh,
		"gap_count": gap_count,
		"ramp_deck_count": 0,
	}


## 对某一地表类型累加 bitmask；返回 pedagogical + atlas。
static func corner_mask_for_type(
	t_bl: int, t_br: int, t_tl: int, t_tr: int, terrain_type: int
) -> Dictionary:
	var pedagogical := 0
	var atlas := 0
	if t_bl == terrain_type:
		pedagogical |= 1
		atlas |= ATLAS_BL
	if t_br == terrain_type:
		pedagogical |= 2
		atlas |= ATLAS_BR
	if t_tl == terrain_type:
		pedagogical |= 4
		atlas |= ATLAS_TL
	if t_tr == terrain_type:
		pedagogical |= 8
		atlas |= ATLAS_TR
	return {"pedagogical": pedagogical, "atlas": atlas}


## 邻近悬崖格时改用 cliff.groundTile（对齐 mdx-m3-viewer cornerTexture）。
static func corner_texture(
	ground_tex: Array,
	layer_heights: Array,
	cliff_tex: Array,
	cliff_to_ground: PackedInt32Array,
	tp_w: int,
	tp_h: int,
	col: int,
	row: int
) -> int:
	if not cliff_to_ground.is_empty():
		for dy in range(-1, 1):
			for dx in range(-1, 1):
				var tx := col + dx
				var ty := row + dy
				if tx < 0 or ty < 0 or tx >= tp_w - 1 or ty >= tp_h - 1:
					continue
				if not Wc3CliffTiles.is_cliff_tile(layer_heights, tp_w, tx, ty):
					continue
				var i00 := ty * tp_w + tx
				var ci := int(cliff_tex[i00]) if i00 < cliff_tex.size() else 0
				if ci == 15:
					ci = 1
				if ci >= 0 and ci < cliff_to_ground.size() and cliff_to_ground[ci] >= 0:
					return cliff_to_ground[ci]
	return _tex_at(ground_tex, row * tp_w + col)


static func _raw_height(heights: Array, tp_w: int, ix: int, iy: int) -> float:
	var i := iy * tp_w + ix
	if i < 0 or i >= heights.size():
		return 0.0
	return float(heights[i])


static func _build_layers(
	t_bl: int, t_br: int, t_tl: int, t_tr: int,
	ground_variation: int,
	extended_flags: PackedByteArray
) -> Dictionary:
	var unique: Array[int] = []
	for t in [t_bl, t_br, t_tl, t_tr]:
		if not unique.has(t):
			unique.append(t)
	unique.sort()

	var tex := PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])
	var vars := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var base: int = unique[0]
	tex[0] = float(base)
	vars[0] = float(_fill_variation(base, ground_variation, extended_flags))

	var slot := 1
	for i in range(1, unique.size()):
		if slot >= 4:
			break
		var t: int = unique[i]
		var mask: Dictionary = corner_mask_for_type(t_bl, t_br, t_tl, t_tr, t)
		var atlas_id: int = int(mask["atlas"])
		if atlas_id == 0:
			continue
		tex[slot] = float(t)
		vars[slot] = float(atlas_id)
		slot += 1

	return {"tex": tex, "var": vars}


static func _fill_variation(
	ground_texture: int, variation: int, extended_flags: PackedByteArray
) -> int:
	var extended := false
	if ground_texture >= 0 and ground_texture < extended_flags.size():
		extended = extended_flags[ground_texture] != 0
	if extended:
		if variation < 16:
			return 16 + variation
		if variation == 16:
			return 15
		return 0
	if variation == 0:
		return 0
	return 15


static func _build_cliff_to_ground(
	cliff_tilesets: Array,
	ground_tilesets: Array,
	tiles: Wc3TerrainTiles
) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(cliff_tilesets.size())
	out.fill(-1)
	if tiles == null:
		return out
	for i in range(cliff_tilesets.size()):
		var ground_id := tiles.ground_tile_for_cliff_id(str(cliff_tilesets[i]))
		if ground_id.is_empty():
			continue
		for gi in range(ground_tilesets.size()):
			if str(ground_tilesets[gi]) == ground_id:
				out[i] = gi
				break
	return out


static func _tex_at(ground_tex: Array, i: int) -> int:
	if i < 0 or i >= ground_tex.size():
		return 0
	return int(ground_tex[i])


static func _var_at(ground_var: Array, i: int) -> int:
	if ground_var.is_empty() or i < 0 or i >= ground_var.size():
		return 0
	return int(ground_var[i])
