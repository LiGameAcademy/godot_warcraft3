class_name MapRampLayer
extends Node3D

## HiveWE-compatible ramp presentation: collect models, preserve entrance ground, boost low corners.

const Wc3RampCollectScript = preload("res://scripts/map/logic/ramp/wc3_ramp_collect.gd")

@export var terrain: MapTerrainLayer
@export var cliffs: MapCliffLayer

var last_placement_count: int = 0
var last_dig_count: int = 0
var last_entrance_count: int = 0
var last_boost_count: int = 0
var _shader: Shader
var _height_tex: Texture2D
var _ramp_mats: Array[ShaderMaterial] = []


func build(ctx: MapBuildContext) -> void:
	_clear_children()
	_ramp_mats.clear()
	last_placement_count = 0
	last_dig_count = 0
	last_entrance_count = 0
	last_boost_count = 0
	if ctx == null:
		return

	ctx.ensure_ramp_topology()
	var hf: Wc3Heightfield = ctx.heightfield
	if hf == null or not hf.is_valid():
		return

	var ramp_data: Wc3RampCollectResult = ctx.ramp
	if ramp_data == null:
		return
	var terrain_layer: MapTerrainLayer = terrain
	if terrain_layer == null:
		terrain_layer = get_node_or_null("../Terrain") as MapTerrainLayer
	var has_ramp_flag := false
	for flag in hf.flags_packed:
		if (int(flag) & Wc3Coords.FLAG_RAMP) != 0:
			has_ramp_flag = true
			break
	if not has_ramp_flag and ramp_data.placements.is_empty() and ramp_data.romp.count(0) == ramp_data.romp.size():
		# No ramp can produce a dig/entrance without a ramp flag. Still clear the
		# previous masks so erasing the last ramp restores the ground correctly.
		if terrain_layer != null:
			terrain_layer.apply_ramp_dig(PackedByteArray(), [], PackedByteArray(), ramp_data.romp)
		return

	# 挖洞 + 入口 undig + 入口低角半层（贴 CliffTrans 坡脚）
	# Only model footprints are removed; entrance ground takes precedence.
	ctx.ensure_ramp_surface_plan()
	var dig: PackedByteArray = ctx.ramp_surface_plan.dig
	var entrances: Array[Vector2i] = ctx.ramp_surface_plan.ground_tiles
	var seam_plan: Dictionary = ctx.ramp_surface_plan
	var boost: PackedByteArray = seam_plan.boost
	last_dig_count = _count_ones(dig)
	last_entrance_count = entrances.size()
	last_boost_count = _count_ones(boost)
	if terrain_layer != null:
		# 传 romp 让 corner_texture 能看 a_romp（对齐 HivEWE real_tile_texture）
		terrain_layer.apply_ramp_dig(dig, entrances, boost, ramp_data.romp)
		AppLog.info(
			AppLog.Layer.PRESENT,
			"Ramp",
			"terrain gaps after dig=%d (plan_dig=%d footprint应各2格)"
			% [terrain_layer.last_gap_count, last_dig_count]
		)
	else:
		AppLog.warn(AppLog.Layer.PRESENT, "Ramp", "terrain 未接线，romp 探出格不会挖洞")

	var ramp_placements: Array[Wc3RampPlacement] = []
	for p in ctx.ramp_surface_plan.original_placements:
		if p != null and p.has_glb:
			ramp_placements.append(p)

	if ramp_placements.is_empty() or ctx.cliff_catalog == null:
		last_placement_count = 0
		AppLog.info(
			AppLog.Layer.PRESENT,
			"Ramp",
			"dig=%d entrances=%d boost=%d no CliffTrans"
			% [last_dig_count, last_entrance_count, last_boost_count]
		)
		return

	_height_tex = Wc3CliffHeightMap.build_texture(ctx.hf, ctx.meta)
	_shader = load("res://assets/shaders/wc3_cliff.gdshader") as Shader

	# 必须用 CliffTrans 解旋变换；勿复用直崖 build_from_placements
	var collected: Wc3CliffBuildResult = Wc3CliffBuilder.build_from_ramp_placements(
		ramp_placements,
		ctx.cliff_catalog,
		hf.center_offset,
		hf.tile_size
	)
	_mount_groups(collected, ctx, hf)
	last_placement_count = collected.placed_cliffs

	AppLog.info(
		AppLog.Layer.PRESENT,
		"Ramp",
		"placed=%d missing=%d dig=%d entrances=%d boost=%d"
		% [
			last_placement_count,
			collected.missing,
			last_dig_count,
			last_entrance_count,
			last_boost_count,
		]
	)


func _mount_groups(
	collected: Wc3CliffBuildResult, ctx: MapBuildContext, hf: Wc3Heightfield
) -> void:
	if collected.groups.is_empty():
		return
	var cliff_tilesets: Array = hf.cliff_tilesets
	var tex_cache: Dictionary = {}
	var mesh_by_key: Dictionary = {}
	var mounted := 0
	ctx.ensure_ramp_surface_plan()
	var seam_plan: Dictionary = ctx.ramp_surface_plan

	for g in collected.groups:
		var glb: String = g.glb
		var tex_idx: int = g.cliff_tex_index
		var transforms: Array[Transform3D] = g.transforms
		if transforms.is_empty():
			continue

		if not tex_cache.has(tex_idx):
			var png: String = ""
			if ctx.cliff_catalog != null:
				png = ctx.cliff_catalog.png_for_cliff_index(cliff_tilesets, tex_idx)
			tex_cache[tex_idx] = RuntimeAssets.load_texture(png) if not png.is_empty() else null

		var key := "%s|%d" % [glb, tex_idx]
		var mesh: Mesh = mesh_by_key.get(key)
		if mesh == null:
			var mat := _cliff_material(tex_cache[tex_idx], hf)
			_ramp_mats.append(mat)
			mesh = _mesh_with_material(ctx.cache, glb, mat)
			if mesh == null:
				AppLog.warn(
					AppLog.Layer.PRESENT,
					"Ramp",
					"mesh null %s" % glb.get_file()
				)
				continue
			mesh_by_key[key] = mesh

		# 每块独立 MeshInstance：解旋 Basis 下 MultiMesh AABB 易被裁掉导致「挖了洞却看不见 CliffTrans」
		var mat_override: Material = null
		if mesh.get_surface_count() > 0:
			mat_override = mesh.surface_get_material(0)
		for i in range(transforms.size()):
			var xf: Transform3D = transforms[i]
			var mi := MeshInstance3D.new()
			mi.name = "Ramp_%s_%d_%d" % [glb.get_file().get_basename(), tex_idx, i]
			mi.mesh = preload("res://scripts/map/presentation/cliff/wc3_cliff_stitcher.gd").build_mesh(mesh, xf, hf, seam_plan.tiles, seam_plan.boost)
			mi.transform = xf
			if mat_override != null:
				mi.material_override = mat_override
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# 本地 AABB；节点 transform 已含解旋，避免错误裁剪
			mi.custom_aabb = mi.mesh.get_aabb()
			mi.extra_cull_margin = 4.0
			mi.layers = Wc3Coords.RENDER_LAYER_TERRAIN
			add_child(mi)
			mounted += 1

	if mounted != collected.placed_cliffs:
		AppLog.warn(
			AppLog.Layer.PRESENT,
			"Ramp",
			"mounted=%d placed=%d (mesh skip?)" % [mounted, collected.placed_cliffs]
		)


func _cliff_material(tex: Texture2D, hf: Wc3Heightfield) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("height_map", _height_tex)
	mat.set_shader_parameter("center_offset", hf.center_offset)
	mat.set_shader_parameter("map_size", Vector2(float(hf.width), float(hf.height)))
	mat.set_shader_parameter("world_scale", Wc3Coords.WORLD_SCALE)
	mat.set_shader_parameter("albedo_scale", 1.0)
	mat.set_shader_parameter("dbg_center_offset", hf.center_offset)
	mat.set_shader_parameter("dbg_tile_size", hf.tile_size)
	if tex:
		mat.set_shader_parameter("cliff_albedo", tex)
	return mat


func _mesh_with_material(cache: MapModelCache, glb: String, mat: Material) -> Mesh:
	var src := cache.mesh_from_glb(glb)
	if src == null:
		return null
	var dup: ArrayMesh = src.duplicate(true) as ArrayMesh
	if dup == null:
		return null
	for s in range(dup.get_surface_count()):
		dup.surface_set_material(s, mat)
	return dup


func _count_ones(mask: PackedByteArray) -> int:
	var n := 0
	for i in range(mask.size()):
		if mask[i] != 0:
			n += 1
	return n


func get_debug_materials() -> Array[ShaderMaterial]:
	return _ramp_mats.duplicate()


func _clear_children() -> void:
	while get_child_count() > 0:
		var c: Node = get_child(0)
		remove_child(c)
		c.free()
