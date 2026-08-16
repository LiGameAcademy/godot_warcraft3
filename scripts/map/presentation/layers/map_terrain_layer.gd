class_name MapTerrainLayer
extends Node3D

## 地面表现层：只读 Heightfield + Catalog 贴图 + 直崖 gap_mask → 网格。
## 禁止改 Heightfield；禁止读斜坡 Collect。
## 斜坡挖洞由 Ramp Present 调 apply_dig_mask / undig_tiles。

## 官方图集角 bit（非教学口诀 BL=1）。用于过渡块编号。
enum AtlasCornerBit {
	BR = 1,
	BL = 2,
	TR = 4,
	TL = 8,
}

@export var ground_material: ShaderMaterial			## 地面材质（场景可配：默认指向 assets/materials）
@onready var _ground: HeightfieldMesh = $Ground		## 地面网格

var last_gap_count: int = 0							## 上次 gap 计数
## 上次 build 缓存，供斜坡 Present 增量挖洞 / 恢复入口地面
var _last_hf: Wc3Heightfield = null
var _last_extended: PackedByteArray = PackedByteArray()
var _base_gap: PackedByteArray = PackedByteArray()
var _extra_dig: PackedByteArray = PackedByteArray()
var _undig: PackedByteArray = PackedByteArray()
## tilepoint：入口低角半层抬高（Present bake，不写 HF）
var _entrance_h_boost: PackedByteArray = PackedByteArray()
var _last_cliff_to_ground: PackedInt32Array = PackedInt32Array()
## tilepoint：CliffTrans 过渡 mask（corner_texture 读，对齐 HivEWE real_tile_texture）
var _last_romp: PackedByteArray = PackedByteArray()

## 四角 bitmask 结果（避免裸 Dictionary 键）。
class CornerMask extends RefCounted:
	var pedagogical: int = 0
	var atlas: int = 0


## 单格叠层：CUSTOM0=tex 槽，CUSTOM1=variation/atlas。
class LayerSlots extends RefCounted:
	var tex: PackedFloat32Array = PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])
	var variation: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


func build(ctx: MapBuildContext) -> void:
	_ground.clear_mesh()
	last_gap_count = 0
	_last_hf = null
	_last_extended = PackedByteArray()
	_base_gap = PackedByteArray()
	_extra_dig = PackedByteArray()
	_undig = PackedByteArray()
	_entrance_h_boost = PackedByteArray()
	_last_cliff_to_ground = PackedInt32Array()
	_last_romp = PackedByteArray()

	var hf: Wc3Heightfield = ctx.heightfield
	if hf == null or not hf.is_valid():
		AppLog.warn(AppLog.Layer.PRESENT, "Terrain", "heightfield 无效")
		return

	var ground_tilesets: Array = hf.ground_tilesets
	if ground_tilesets.is_empty():
		AppLog.warn(AppLog.Layer.PRESENT, "Terrain", "groundTilesets 为空")
		return

	ctx.ensure_cliff_topology()

	var extended: PackedByteArray = Wc3GroundTileCatalog.build_extended_flags(
		ground_tilesets, ctx.tiles
	)
	_last_hf = hf
	_last_extended = extended
	_base_gap = ctx.cliff_gap_mask
	_last_cliff_to_ground = PackedInt32Array()
	if ctx.cliff_catalog != null:
		_last_cliff_to_ground = ctx.cliff_catalog.build_cliff_to_ground_map(
			hf.cliff_tilesets, ground_tilesets
		)
	# 缓存斜坡 romp（corner_texture 用，对齐 HivEWE real_tile_texture a_romp 检查）
	if ctx.ramp != null and not ctx.ramp.romp.is_empty():
		_last_romp = ctx.ramp.romp.duplicate()
	last_gap_count = _build_ground_mesh(
		hf, extended, _compose_gap_mask(), _last_cliff_to_ground
	)

	var tex_array: Texture2DArray = Wc3GroundTileCatalog.build_texture_array(
		ground_tilesets, ctx.tiles
	)
	if tex_array == null:
		AppLog.error(AppLog.Layer.PRESENT, "Terrain", "Texture2DArray 失败")
		return

	if ground_material == null:
		AppLog.error(AppLog.Layer.PRESENT, "Terrain", "未配置 ground_material")
		return

	_ground.apply_from_template(
		ground_material,
		{
			"tilesets": tex_array,
			"world_scale": Wc3Coords.WORLD_SCALE,
			"dbg_center_offset": hf.center_offset,
			"dbg_tile_size": hf.tile_size,
		}
	)
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.layers = Wc3Coords.RENDER_LAYER_TERRAIN

	AppLog.info(
		AppLog.Layer.PRESENT,
		"Terrain",
		"mesh OK gaps=%d tiles=%d layers=%d mat=%s"
		% [
			last_gap_count,
			hf.map_width * hf.map_height,
			tex_array.get_layers(),
			_ground.active_material != null,
		]
	)


## 斜坡 Present API：追加挖洞（与直崖 gap OR）。不读 ramp 数据。
func apply_dig_mask(extra: PackedByteArray) -> void:
	_extra_dig = extra.duplicate() if not extra.is_empty() else PackedByteArray()
	_rebuild_ground_mesh_only()


## 斜坡 Present API：强制保留地面（入口格）。优先级高于 dig。
func undig_tiles(tiles: Array[Vector2i]) -> void:
	_set_undig_tiles(tiles)
	_rebuild_ground_mesh_only()


## 一次重建：斜坡 dig + 入口 undig + 入口低角半层抬高（不写 HF）。
## romp 来自 ctx.ramp.romp（CliffTrans 过渡 mask）—— corner_texture 用，对齐 HivEWE a_romp。
func apply_ramp_dig(
	extra: PackedByteArray,
	entrance_tiles: Array[Vector2i],
	entrance_height_boost: PackedByteArray = PackedByteArray(),
	romp: PackedByteArray = PackedByteArray()
) -> void:
	_extra_dig = extra.duplicate() if not extra.is_empty() else PackedByteArray()
	_set_undig_tiles(entrance_tiles)
	_entrance_h_boost = (
		entrance_height_boost.duplicate() if not entrance_height_boost.is_empty() else PackedByteArray()
	)
	if not romp.is_empty():
		_last_romp = romp.duplicate()
	_rebuild_ground_mesh_only()


func _set_undig_tiles(tiles: Array[Vector2i]) -> void:
	if _last_hf == null or not _last_hf.is_valid():
		_undig = PackedByteArray()
		return
	var map_w: int = _last_hf.width - 1
	var map_h: int = _last_hf.height - 1
	_undig.resize(maxi(map_w * map_h, 0))
	_undig.fill(0)
	for t in tiles:
		if t.x < 0 or t.y < 0 or t.x >= map_w or t.y >= map_h:
			continue
		_undig[t.y * map_w + t.x] = 1


func _rebuild_ground_mesh_only() -> void:
	if _last_hf == null or not _last_hf.is_valid():
		return
	last_gap_count = _build_ground_mesh(
		_last_hf, _last_extended, _compose_gap_mask(), _last_cliff_to_ground
	)


func _compose_gap_mask() -> PackedByteArray:
	var n: int = _base_gap.size()
	var out := _base_gap.duplicate()
	if out.is_empty():
		return out
	for i in range(mini(n, _extra_dig.size())):
		if _extra_dig[i] != 0:
			out[i] = 1
	for i in range(mini(n, _undig.size())):
		if _undig[i] != 0:
			out[i] = 0
	return out


## 供 DebugGrid 层收集可调 shader 材质。
func get_debug_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	if _ground != null and _ground.active_material != null:
		out.append(_ground.active_material)
	return out


## 对某一地表类型累加 bitmask。
func corner_mask_for_type(t_bl: int, t_br: int, t_tl: int, t_tr: int, terrain_type: int) -> CornerMask:
	var mask := CornerMask.new()
	if t_bl == terrain_type:
		mask.pedagogical |= 1
		mask.atlas |= AtlasCornerBit.BL
	if t_br == terrain_type:
		mask.pedagogical |= 2
		mask.atlas |= AtlasCornerBit.BR
	if t_tl == terrain_type:
		mask.pedagogical |= 4
		mask.atlas |= AtlasCornerBit.TL
	if t_tr == terrain_type:
		mask.pedagogical |= 8
		mask.atlas |= AtlasCornerBit.TR
	return mask


## 邻近直崖/斜坡格时改用 cliff.groundTile（对齐 HivEWE `real_tile_texture`）。
## 实现已上提至 Wc3TerrainLogic.real_tile_texture；此处保留同名供 Present 调用。
func corner_texture(
	ground_tex: Array,
	layer_heights: Array,
	cliff_tex: Array,
	cliff_to_ground: PackedInt32Array,
	tp_w: int,
	tp_h: int,
	col: int,
	row: int
) -> int:
	var flags: Array = _last_hf.flags_packed if _last_hf != null else []
	return Wc3TerrainLogic.real_tile_texture(
		ground_tex,
		layer_heights,
		cliff_tex,
		cliff_to_ground,
		flags,
		_last_romp,
		tp_w,
		tp_h,
		col,
		row
	)


## 返回 gap_count；网格写在 _ground 上。挖洞只消费传入 mask（直崖 ± 斜坡 API 合成）。
func _build_ground_mesh(
	hf: Wc3Heightfield,
	extended_flags: PackedByteArray,
	gap_mask: PackedByteArray,
	cliff_to_ground: PackedInt32Array = PackedInt32Array()
) -> int:
	var width: int = hf.width
	var height: int = hf.height
	if width < 2 or height < 2:
		push_error("MapTerrainLayer: heightfield 无效")
		return 0

	_ground.begin_build(true)
	var gap_count := 0
	var center: Vector2 = hf.center_offset
	var tile_size: float = hf.tile_size
	var map_w: int = width - 1
	var ground_tex: Array = hf.ground_textures
	var layer_heights: Array = hf.layer_heights
	var cliff_tex: Array = hf.cliff_textures

	for iy in range(height - 1):
		for ix in range(width - 1):
			var i00 := iy * width + ix
			var gi: int = iy * map_w + ix
			if gi >= 0 and gi < gap_mask.size() and gap_mask[gi] != 0:
				gap_count += 1
				continue

			var t_bl: int = corner_texture(
				ground_tex, layer_heights, cliff_tex, cliff_to_ground, width, height, ix, iy
			)
			var t_br: int = corner_texture(
				ground_tex, layer_heights, cliff_tex, cliff_to_ground, width, height, ix + 1, iy
			)
			var t_tl: int = corner_texture(
				ground_tex, layer_heights, cliff_tex, cliff_to_ground, width, height, ix, iy + 1
			)
			var t_tr: int = corner_texture(
				ground_tex, layer_heights, cliff_tex, cliff_to_ground, width, height, ix + 1, iy + 1
			)

			var slots: LayerSlots = _build_layers(
				t_bl, t_br, t_tl, t_tr,
				_var_at(hf.ground_variations, i00),
				extended_flags
			)

			var positions := PackedVector3Array([
				HeightfieldMesh.sample_vert(
					ix, iy, _corner_h(hf, i00), center, tile_size
				),
				HeightfieldMesh.sample_vert(
					ix + 1, iy, _corner_h(hf, i00 + 1), center, tile_size
				),
				HeightfieldMesh.sample_vert(
					ix, iy + 1, _corner_h(hf, i00 + width), center, tile_size
				),
				HeightfieldMesh.sample_vert(
					ix + 1, iy + 1, _corner_h(hf, i00 + width + 1), center, tile_size
				),
			])
			_ground.add_quad(positions, slots.tex, slots.variation)

	_ground.commit_build()
	return gap_count


## Present bake：入口低角 +0.5 层（64 WC3）；不改权威 heights。
func _corner_h(hf: Wc3Heightfield, corner_i: int) -> float:
	var h: float = float(hf.heights[corner_i])
	if corner_i >= 0 and corner_i < _entrance_h_boost.size() and _entrance_h_boost[corner_i] != 0:
		h += 0.5 * Wc3CliffLogic.LAYER_HEIGHT_STEP
	return h


## 构建层
func _build_layers(
	t_bl: int, t_br: int, t_tl: int, t_tr: int,
	ground_variation: int, extended_flags: PackedByteArray) -> LayerSlots:
	var unique: Array[int] = []
	for t in [t_bl, t_br, t_tl, t_tr]:
		if not unique.has(t):
			unique.append(t)
	unique.sort()

	var slots := LayerSlots.new()
	var base: int = unique[0]
	slots.tex[0] = float(base)
	slots.variation[0] = float(_fill_variation(base, ground_variation, extended_flags))

	var slot := 1
	for i in range(1, unique.size()):
		if slot >= 4:
			break
		var t: int = unique[i]
		var mask: CornerMask = corner_mask_for_type(t_bl, t_br, t_tl, t_tr, t)
		if mask.atlas == 0:
			continue
		slots.tex[slot] = float(t)
		slots.variation[slot] = float(mask.atlas)
		slot += 1
	return slots

## 填充变体
func _fill_variation(ground_texture: int, variation: int, extended_flags: PackedByteArray) -> int:
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


func _tex_at(ground_tex: Array, i: int) -> int:
	if i < 0 or i >= ground_tex.size():
		return 0
	return int(ground_tex[i])

func _var_at(ground_var: Array, i: int) -> int:
	if ground_var.is_empty() or i < 0 or i >= ground_var.size():
		return 0
	return int(ground_var[i])
