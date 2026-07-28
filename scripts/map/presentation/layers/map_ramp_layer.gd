class_name MapRampLayer
extends Node3D

## 斜坡表现层：消费 Collect placements，挂 CliffTrans。
## 直崖跳过由 MapLoader 在挂崖前 filter_cliff_placements（对齐 WE continue）。
## 本阶段不改地形 mesh（dig/undig 后置）；入口低角 +0.5 后置。

@export var terrain: MapTerrainLayer
@export var cliffs: MapCliffLayer

var last_placement_count: int = 0
var _shader: Shader
var _height_tex: Texture2D
var _ramp_mats: Array[ShaderMaterial] = []


func build(ctx: MapBuildContext) -> void:
	_clear_children()
	_ramp_mats.clear()
	last_placement_count = 0
	if ctx == null:
		return

	ctx.ensure_ramp_topology()
	var hf: Wc3Heightfield = ctx.heightfield
	if hf == null or not hf.is_valid():
		return

	var ramp_data: Wc3RampCollectResult = ctx.ramp
	if ramp_data == null:
		return

	var ramp_placements: Array[Wc3RampPlacement] = []
	for p in ramp_data.placements:
		if p != null and p.has_glb:
			ramp_placements.append(p)

	if ramp_placements.is_empty() or ctx.cliff_catalog == null:
		last_placement_count = 0
		MapLog.info(MapLog.Layer.PRESENT, "Ramp", "no CliffTrans")
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

	MapLog.info(
		MapLog.Layer.PRESENT,
		"Ramp",
		"placed=%d missing=%d" % [last_placement_count, collected.missing]
	)


func _mount_groups(
	collected: Wc3CliffBuildResult, ctx: MapBuildContext, hf: Wc3Heightfield
) -> void:
	if collected.groups.is_empty():
		return
	var cliff_tilesets: Array = hf.cliff_tilesets
	var tex_cache: Dictionary = {}
	var mesh_by_key: Dictionary = {}

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
				continue
			mesh_by_key[key] = mesh

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i])

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Ramp_%s_%d" % [glb.get_file().get_basename(), tex_idx]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


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


func _clear_children() -> void:
	for c in get_children():
		c.queue_free()
