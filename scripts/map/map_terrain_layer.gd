class_name MapTerrainLayer
extends Node3D
## 地面层：WC3 图集自动地形 + HeightfieldMesh（悬崖/斜坡格留空）。


const GROUND_SHADER: Shader = preload("res://shaders/wc3_ground.gdshader")

@onready var _ground: HeightfieldMesh = $Ground

var last_gap_count: int = 0


func build(hf: Dictionary, tiles: Wc3TerrainTiles) -> void:
	_ground.clear_mesh()
	last_gap_count = 0
	var ground_tilesets: Array = hf.get("groundTilesets", [])
	if ground_tilesets.is_empty():
		push_warning("MapTerrainLayer: groundTilesets 为空")
		return

	var extended := Wc3TerrainAutotile.build_extended_flags(ground_tilesets, tiles)
	var built := Wc3TerrainAutotile.build_ground_mesh(hf, extended, tiles)
	if built.is_empty():
		push_warning("MapTerrainLayer: 地面网格为空")
		return

	var tex_array := Wc3TerrainAutotile.build_tileset_array(ground_tilesets, tiles)
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

	var stats := Wc3CliffTiles.count_gaps(hf)
	print(
		"Terrain gaps: %d (cliff=%d ramp_tiles=%d ramp_models=%d / tiles=%d)"
		% [
			stats["gaps"],
			stats["cliffs"],
			stats["ramps"],
			stats.get("ramp_models", 0),
			stats["tiles"],
		]
	)
