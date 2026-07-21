class_name MapWaterLayer
extends Node3D
## 水体层：消费 MapBuildContext → 水面网格 + 岸浪。


const WATER_SHADER: Shader = preload("res://shaders/wc3_water.gdshader")

@export var height_bias_wc3: float = 0.0
## 由 MapRoot「岸浪微调」同步；也可直接改本节点。
@export_range(0.0, 0.40, 0.01) var foam_cliff_out_extra: float = 0.08
@export_range(0.0, 0.55, 0.01) var foam_ramp_pull_tiles: float = 0.38
@export_range(0.0, 0.40, 0.01) var foam_shore_pull_tiles: float = 0.10

@onready var _water: HeightfieldMesh = $Surface

var last_cell_count: int = 0
var last_shore_count: int = 0
var _shore_root: Node3D


func build(ctx) -> void:
	_water.clear_mesh()
	_clear_shore()
	last_cell_count = 0
	last_shore_count = 0

	var params := Wc3WaterParams.load_for_tileset(ctx.main_tileset)
	var built := Wc3WaterMesh.build(ctx.hf, params, height_bias_wc3, ctx.meta)
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
		"Water: tiles=%d underRamp=%d frames=%d id=%s tex0=%s offset=%.1f bias=%.1f texRate=%.0f uvCells=%.0f (%.1fs/cycle)"
		% [
			last_cell_count,
			int(built.get("under_ramp", 0)),
			params.frame_pngs.size(),
			params.water_id,
			params.frame_pngs[0].get_file() if params.frame_pngs.size() else "?",
			params.height_offset_wc3(),
			height_bias_wc3,
			params.tex_rate,
			params.cells,
			float(params.frame_pngs.size()) / maxf(params.tex_rate, 0.001),
		]
	)

	_build_shore_foam(ctx, params)


func _build_shore_foam(ctx, params: Wc3WaterParams) -> void:
	var cliff_on := bool(ctx.map_flags.get("waterWavesCliff", true))
	var roll_on := bool(ctx.map_flags.get("waterWavesRolling", true))
	var collected := Wc3ShorelineBuilder.collect_foam_placements(
		ctx.hf,
		params,
		height_bias_wc3,
		cliff_on,
		roll_on,
		ctx.meta,
		foam_shore_pull_tiles,
		foam_ramp_pull_tiles,
		foam_cliff_out_extra,
	)
	var list: Array = collected.get("placements", []) as Array
	if list.is_empty():
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
	last_shore_count = Wc3ShoreFoam.build_systems(_shore_root, list)
	print(
		"Shore foam: S=%d OC=%d IC=%d contour=%d cliff=%d instances=%d pull(r=%.2f s=%.2f) cliffOut+=%.2f"
		% [
			int(collected.get("count_s", 0)),
			int(collected.get("count_oc", 0)),
			int(collected.get("count_ic", 0)),
			int(collected.get("count_contour", 0)),
			int(collected.get("count_cliff_l1", 0)) + int(collected.get("count_cliff_l2", 0)),
			last_shore_count,
			foam_ramp_pull_tiles,
			foam_shore_pull_tiles,
			foam_cliff_out_extra,
		]
	)


func _clear_shore() -> void:
	if _shore_root and is_instance_valid(_shore_root):
		_shore_root.queue_free()
	_shore_root = null
	for c in get_children():
		if c != _water and str(c.name).begins_with("Shore"):
			c.queue_free()
