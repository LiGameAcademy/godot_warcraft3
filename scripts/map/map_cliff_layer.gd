class_name MapCliffLayer
extends Node3D
## 悬崖 / 斜坡层：消费 MapBuildContext；GLB 经 MapModelCache（与单位/装饰共用）。


var _shader: Shader
var _height_tex: Texture2D
var last_placed: int = 0
var _cliff_mats: Array = [] ## ShaderMaterial，供调试栅格开关
var _dbg_tile := false
var _dbg_path := false
var _dbg_fine := false
var _dbg_center: Vector2 = Vector2.ZERO
var _dbg_tile_size: float = 128.0


func build(ctx) -> void:
	_clear_children()
	_cliff_mats.clear()
	last_placed = 0
	ctx.ensure_cliff_topology()

	_height_tex = Wc3CliffHeightMap.build_texture(ctx.hf, ctx.meta)
	_shader = load("res://shaders/wc3_cliff.gdshader") as Shader
	_dbg_center = ctx.meta.get("center", Vector2.ZERO)
	_dbg_tile_size = float(ctx.meta.get("tile_size", Wc3Coords.TILE_SIZE))

	var ramp_data := {
		"romp": ctx.cliff_romp,
		"placements": ctx.cliff_ramp_placements,
	}
	var collected := Wc3CliffBuilder.collect_instances(ctx.hf, ctx.tiles, ctx.meta, ramp_data)
	if collected.is_empty():
		return

	var groups: Array = collected.get("groups", [])
	var cliff_tilesets: Array = collected.get("cliff_tilesets", [])
	var tex_cache: Dictionary = {}
	var mesh_by_key: Dictionary = {} # "glb|tex_idx" → Mesh（带材质）

	for g in groups:
		var glb: String = str(g["glb"])
		var tex_idx: int = int(g["cliff_tex_index"])
		var transforms: Array = g["transforms"]
		if transforms.is_empty():
			continue

		if not tex_cache.has(tex_idx):
			var png: String = ctx.tiles.png_for_cliff_index(cliff_tilesets, tex_idx)
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
			var mat := _cliff_material(tex_cache[tex_idx], ctx.meta)
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

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Cliff_%s_%d" % [glb.get_file().get_basename(), tex_idx]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		last_placed += transforms.size()

	_apply_debug_grid_to_mats()

	print(
		"Cliffs: placed=%d (cliff=%d ramp=%d) missing=%d groups=%d"
		% [
			last_placed,
			int(collected.get("placed_cliffs", 0)),
			int(collected.get("placed_ramps", 0)),
			int(collected.get("missing", 0)),
			groups.size(),
		]
	)


## 查看→栅格：悬崖立面/顶缘也画调试线（与地面同级开关）。
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


func _cliff_material(tex: Texture2D, meta: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("height_map", _height_tex)
	mat.set_shader_parameter("center_offset", meta.get("center", Vector2.ZERO))
	mat.set_shader_parameter(
		"map_size",
		Vector2(float(meta.get("width", 1)), float(meta.get("height", 1)))
	)
	mat.set_shader_parameter("world_scale", Wc3Coords.WORLD_SCALE)
	mat.set_shader_parameter("albedo_scale", 1.0)
	mat.set_shader_parameter("dbg_center_offset", meta.get("center", Vector2.ZERO))
	mat.set_shader_parameter("dbg_tile_size", float(meta.get("tile_size", Wc3Coords.TILE_SIZE)))
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
