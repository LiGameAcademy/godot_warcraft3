class_name MapWaterLayer
extends Node3D
## 水体层：HiveWE 水面网格 + 官方 Shoreline PE2 泡沫（直边/内外角）。


const WATER_SHADER: Shader = preload("res://shaders/wc3_water.gdshader")

@export var height_bias_wc3: float = 0.0
@export var build_shore_foam: bool = true
## 已弃用：ShorelineWave 网格浪（非 Water.slk 自动岸线）
@export var build_shore_mesh_waves: bool = false

@onready var _water: HeightfieldMesh = $Surface

var last_cell_count: int = 0
var last_shore_count: int = 0
var _shore_root: Node3D


func build(hf: Dictionary, main_tileset: String = "I", map_flags: Dictionary = {}) -> void:
	_water.clear_mesh()
	_clear_shore()
	last_cell_count = 0
	last_shore_count = 0

	var params := Wc3WaterParams.load_for_tileset(main_tileset)
	var built := Wc3WaterMesh.build(hf, params, height_bias_wc3)
	if built.is_empty():
		push_warning("MapWaterLayer: 无水面网格")
		return

	var tex_array := params.build_texture_array()
	if tex_array == null:
		push_warning("MapWaterLayer: 水面贴图数组为空（检查 I_Water00.png …）")
		return

	var mesh: ArrayMesh = built["mesh"]
	last_cell_count = int(built.get("cell_count", 0))
	_water.set_array_mesh(mesh)
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("water_frames", tex_array)
	mat.set_shader_parameter("frame_count", params.frame_pngs.size())
	mat.set_shader_parameter("tex_rate", params.tex_rate)
	mat.render_priority = 1
	_water.apply_uniform_material(mat)

	print(
		"Water: tiles=%d skipRamp=%d frames=%d id=%s offset=%.1f bias=%.1f texRate=%.0f uvCells=%.0f (%.1fs/cycle)"
		% [
			last_cell_count,
			int(built.get("skipped_ramp", 0)),
			params.frame_pngs.size(),
			params.water_id,
			params.height_offset_wc3(),
			height_bias_wc3,
			params.tex_rate,
			params.cells,
			float(params.frame_pngs.size()) / maxf(params.tex_rate, 0.001),
		]
	)

	if build_shore_foam:
		_build_shore_foam(hf, params, map_flags)


func _build_shore_foam(hf: Dictionary, params: Wc3WaterParams, map_flags: Dictionary) -> void:
	var cliff_on := bool(map_flags.get("waterWavesCliff", true))
	var roll_on := bool(map_flags.get("waterWavesRolling", true))
	var collected := Wc3ShorelineBuilder.collect_foam_placements(
		hf, params, height_bias_wc3, cliff_on, roll_on
	)
	var n_s: int = (collected.get("straight", []) as Array).size()
	var n_o: int = (collected.get("outside", []) as Array).size()
	var n_i: int = (collected.get("inside", []) as Array).size()
	if n_s + n_o + n_i == 0:
		print(
			"Shore foam: none (candidates=%d shallowSkip=%d cliff=%s roll=%s)"
			% [
				int(collected.get("edge_candidates", 0)),
				int(collected.get("skipped_shallow", 0)),
				cliff_on,
				roll_on,
			]
		)
		return

	_shore_root = Node3D.new()
	_shore_root.name = "ShoreFoam"
	add_child(_shore_root)
	last_shore_count = Wc3ShoreFoam.build_systems(_shore_root, collected)
	print(
		"Shore foam: points=%d (S=%d OC=%d IC=%d) candidates=%d shallowSkip=%d"
		% [
			last_shore_count,
			n_s,
			n_o,
			n_i,
			int(collected.get("edge_candidates", 0)),
			int(collected.get("skipped_shallow", 0)),
		]
	)


func _clear_shore() -> void:
	if _shore_root and is_instance_valid(_shore_root):
		_shore_root.queue_free()
	_shore_root = null
	for c in get_children():
		if c != _water and str(c.name).begins_with("Shore"):
			c.queue_free()
