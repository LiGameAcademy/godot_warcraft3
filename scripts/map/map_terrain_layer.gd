class_name MapTerrainLayer
extends Node3D
## 地面层：消费 MapBuildContext → Autotile 网格 + shader。


const GROUND_SHADER: Shader = preload("res://shaders/wc3_ground.gdshader")

@onready var _ground: HeightfieldMesh = $Ground

var last_gap_count: int = 0


func build(ctx) -> void:
	_ground.clear_mesh()
	last_gap_count = 0
	ctx.ensure_cliff_topology()

	var ground_tilesets: Array = ctx.hf.get("groundTilesets", [])
	if ground_tilesets.is_empty():
		push_warning("MapTerrainLayer: groundTilesets 为空")
		return

	var extended := Wc3TerrainAutotile.build_extended_flags(ground_tilesets, ctx.tiles)
	var built := Wc3TerrainAutotile.build_ground_mesh(
		ctx.hf, extended, ctx.tiles, ctx.meta, ctx.cliff_romp
	)
	if built.is_empty():
		push_warning("MapTerrainLayer: 地面网格为空")
		return

	var tex_array := Wc3TerrainAutotile.build_tileset_array(ground_tilesets, ctx.tiles)
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
	_ground.apply_uniform_material(mat)
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var stats: Dictionary = ctx.cliff_gap_stats
	print(
		"Terrain gaps: %d (cliff=%d ramp_tiles=%d ramp_models=%d / tiles=%d)"
		% [
			int(stats.get("gaps", last_gap_count)),
			int(stats.get("cliffs", 0)),
			int(stats.get("ramps", 0)),
			int(stats.get("ramp_models", 0)),
			int(stats.get("tiles", 0)),
		]
	)
