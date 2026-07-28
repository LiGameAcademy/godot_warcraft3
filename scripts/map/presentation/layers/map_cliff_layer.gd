class_name MapCliffLayer
extends Node3D

## 悬崖表现层：只读 Context.placements + Catalog 资产 → MultiMesh。
## 禁止改 Heightfield；禁止做 TAG / 挖洞 / 变体选型（一律 Logic）。
## 禁止读斜坡 Collect；入口 / CliffTrans 覆盖由 Ramp Present 调 hide_at_tiles。

var _shader: Shader
var _height_tex: Texture2D
var last_placed: int = 0
var _cliff_mats: Array[ShaderMaterial] = []
var _dbg_tile: bool = false
var _dbg_path: bool = false
var _dbg_fine: bool = false
var _dbg_center: Vector2 = Vector2.ZERO
var _dbg_tile_size: float = 128.0
## Vector2i(ix,iy) → Array[{ "mm": MultiMesh, "index": int }]
var _instances_by_tile: Dictionary = {}


func build(ctx: MapBuildContext) -> void:
	_clear_children()
	_cliff_mats.clear()
	_instances_by_tile.clear()
	last_placed = 0
	ctx.ensure_cliff_topology()

	var hf: Wc3Heightfield = ctx.heightfield
	if hf == null or not hf.is_valid():
		return

	_height_tex = Wc3CliffHeightMap.build_texture(ctx.hf, ctx.meta)
	_shader = load("res://assets/shaders/wc3_cliff.gdshader") as Shader
	_dbg_center = hf.center_offset
	_dbg_tile_size = hf.tile_size

	var collected: Wc3CliffBuildResult = Wc3CliffBuilder.build_from_placements(
		ctx.cliff_placements,
		ctx.cliff_catalog,
		hf.center_offset,
		hf.tile_size
	)
	if collected.groups.is_empty() and collected.placed_cliffs == 0:
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
			print(
				"Cliff tex[%d] %s → %s (%s)"
				% [
					tex_idx,
					str(cliff_tilesets[tex_idx]) if tex_idx < cliff_tilesets.size() else "?",
					png,
					"ok" if tex_cache[tex_idx] else "FAIL",
				]
			)

		var key := "%s|%d" % [glb, tex_idx]
		var mesh: Mesh = mesh_by_key.get(key)
		if mesh == null:
			var mat := _cliff_material(tex_cache[tex_idx], hf)
			_cliff_mats.append(mat)
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
			if i < g.tiles.size():
				_register_instance(g.tiles[i], mm, i)

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Cliff_%s_%d" % [glb.get_file().get_basename(), tex_idx]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		last_placed += transforms.size()

	_apply_debug_grid_to_mats()

	print(
		"Cliffs: placed=%d missing=%d groups=%d"
		% [
			last_placed,
			collected.missing,
			collected.groups.size(),
		]
	)


func _register_instance(tile: Vector2i, mm: MultiMesh, index: int) -> void:
	if not _instances_by_tile.has(tile):
		_instances_by_tile[tile] = []
	(_instances_by_tile[tile] as Array).append({"mm": mm, "index": index})


## 斜坡 Present API：隐藏指定地表格上的直崖（入口 / 已被 CliffTrans 覆盖）。
func hide_at_tiles(tiles: Array[Vector2i]) -> void:
	if tiles.is_empty() or _instances_by_tile.is_empty():
		return
	# 零缩放藏模（Transform3D 无 ZERO 常量）
	var hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	for t in tiles:
		if not _instances_by_tile.has(t):
			continue
		for entry in _instances_by_tile[t]:
			var mm: MultiMesh = entry.get("mm") as MultiMesh
			var idx: int = int(entry.get("index", -1))
			if mm == null or idx < 0 or idx >= mm.instance_count:
				continue
			mm.set_instance_transform(idx, hidden)


func get_debug_materials() -> Array[ShaderMaterial]:
	return _cliff_mats.duplicate()


func set_debug_grid(show_tile: bool, show_path: bool, show_fine: bool) -> void:
	_dbg_tile = show_tile
	_dbg_path = show_path
	_dbg_fine = show_fine
	_apply_debug_grid_to_mats()


func _apply_debug_grid_to_mats() -> void:
	for mat in _cliff_mats:
		if mat == null:
			continue
		mat.set_shader_parameter("dbg_grid_tile", _dbg_tile)
		mat.set_shader_parameter("dbg_grid_path", _dbg_path)
		mat.set_shader_parameter("dbg_grid_fine", _dbg_fine)
		mat.set_shader_parameter("dbg_center_offset", _dbg_center)
		mat.set_shader_parameter("dbg_tile_size", _dbg_tile_size)


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
	mat.set_shader_parameter("dbg_grid_tile", _dbg_tile)
	mat.set_shader_parameter("dbg_grid_path", _dbg_path)
	mat.set_shader_parameter("dbg_grid_fine", _dbg_fine)
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
