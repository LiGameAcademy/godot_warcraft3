class_name MapTerrainLayer
extends Node3D
## 地面表现层：消费 MapBuildContext → Ground Mesh + shader。
## 纹理经 Catalog；网格经 Autotile/MeshBuilder；本节点只挂树。


const GROUND_SHADER: Shader = preload("res://shaders/wc3_ground.gdshader")

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
	var built := Wc3TerrainAutotile.build_ground_mesh(
		ctx.hf, extended, ctx.tiles, ctx.meta, ctx.cliff_romp, ctx.cliff_ramp_placements
	)
	if built.is_empty():
		push_warning("MapTerrainLayer: 地面网格为空")
		return

	var tex_array := Wc3GroundTileCatalog.build_texture_array(ground_tilesets, ctx.tiles)
	if tex_array == null:
		push_warning("MapTerrainLayer: Texture2DArray 失败")
		return

	var mesh: ArrayMesh = built["mesh"]
	last_gap_count = int(built.get("gap_count", 0))
	_ground.set_array_mesh(mesh)

	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("tilesets", tex_array)
	mat.set_shader_parameter("roughness_value", 0.92)
	mat.set_shader_parameter("albedo_scale", 1.0)
	mat.set_shader_parameter("world_scale", Wc3Coords.WORLD_SCALE)
	mat.set_shader_parameter("dbg_center_offset", ctx.meta.get("center", Vector2.ZERO))
	mat.set_shader_parameter("dbg_tile_size", float(ctx.meta.get("tile_size", Wc3Coords.TILE_SIZE)))
	_ground_mat = mat
	_ground.apply_uniform_material(mat)
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


## 寻路调试线框（GPU，写在 ground shader 内）。
func set_debug_grid(show_tile: bool, show_path: bool, show_fine: bool) -> void:
	if _ground_mat == null:
		return
	_ground_mat.set_shader_parameter("dbg_grid_tile", show_tile)
	_ground_mat.set_shader_parameter("dbg_grid_path", show_path)
	_ground_mat.set_shader_parameter("dbg_grid_fine", show_fine)
