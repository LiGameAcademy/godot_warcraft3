class_name MapCliffLayer
extends Node3D

## 悬崖表现层：只读 Context.placements + Catalog 资产 → MultiMesh。
## 禁止改 Heightfield；禁止做 TAG / 挖洞 / 变体选型（一律 Logic）。
## 禁止读斜坡 Collect；斜坡跳过由 Loader 在 build 前 filter_cliff_placements。
## hide_* 仅调试/兼容；主路径不依赖事后零缩放。

var _shader: Shader
var _height_tex: Texture2D
var last_placed: int = 0
var _cliff_mats: Array[ShaderMaterial] = []
var _dbg_tile: bool = false
var _dbg_path: bool = false
var _dbg_fine: bool = false
var _dbg_center: Vector2 = Vector2.ZERO
var _dbg_tile_size: float = 128.0
## 每块直崖模型一条：{ mm, index, ix, iy, base_layer, xf }
var _instances: Array[Dictionary] = []


func build(ctx: MapBuildContext) -> void:
	_clear_children()
	_cliff_mats.clear()
	_instances.clear()
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
			AppLog.debug(
				AppLog.Layer.PRESENT,
				"Cliff",
				"tex[%d] %s → %s (%s)"
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
			var tile := Vector2i(g.tiles[i].x, g.tiles[i].y) if i < g.tiles.size() else Vector2i(-1, -1)
			var base_l: int = int(g.base_layers[i]) if i < g.base_layers.size() else 2
			_instances.append({
				"mm": mm,
				"index": i,
				"ix": tile.x,
				"iy": tile.y,
				"base_layer": base_l,
				"xf": transforms[i],
			})

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Cliff_%s_%d" % [glb.get_file().get_basename(), tex_idx]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.layers = Wc3Coords.RENDER_LAYER_TERRAIN
		add_child(mmi)
		last_placed += transforms.size()

	_apply_debug_grid_to_mats()

	AppLog.info(
		AppLog.Layer.PRESENT,
		"Cliff",
		"placed=%d missing=%d groups=%d"
		% [
			last_placed,
			collected.missing,
			collected.groups.size(),
		]
	)


## 斜坡 Present：按「单块直崖模型」隐藏（叠段粒度），不整格一刀切。
func hide_pieces_for_ramp(hf: Wc3Heightfield, ramp_data: Wc3RampCollectResult) -> int:
	if _instances.is_empty() or hf == null or ramp_data == null:
		return 0
	var hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	var n := 0
	for entry in _instances:
		var ix: int = int(entry.get("ix", -1))
		var iy: int = int(entry.get("iy", -1))
		var base_l: int = int(entry.get("base_layer", 2))
		if not Wc3RampLogic.should_hide_cliff_piece(ix, iy, base_l, hf, ramp_data):
			continue
		var mm: MultiMesh = entry.get("mm") as MultiMesh
		var idx: int = int(entry.get("index", -1))
		if mm == null or idx < 0 or idx >= mm.instance_count:
			continue
		mm.set_instance_transform(idx, hidden)
		n += 1
	return n


## 兼容旧 API：按地表格隐藏该格全部叠段模型。
func hide_at_tiles(tiles: Array[Vector2i]) -> void:
	if tiles.is_empty() or _instances.is_empty():
		return
	var want: Dictionary = {}
	for t in tiles:
		want[t] = true
	var hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	for entry in _instances:
		var tile := Vector2i(int(entry.get("ix", -1)), int(entry.get("iy", -1)))
		if not want.has(tile):
			continue
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
