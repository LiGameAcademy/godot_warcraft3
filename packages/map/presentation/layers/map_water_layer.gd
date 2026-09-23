class_name MapWaterLayer
extends Node3D
## 水体层：消费 MapBuildContext → 水面网格 + 岸浪。
## 进局：mesh → await → 贴图/材质 → await → foam（贴图按 tileset 缓存）。


const WATER_SHADER: Shader = preload("res://assets/shaders/wc3_water.gdshader")

@export var height_bias_wc3: float = 0.0
## 由 MapRoot「岸浪微调」同步；也可直接改本节点。
@export_range(0.0, 0.40, 0.01) var foam_cliff_out_extra: float = 0.08
@export_range(0.0, 0.55, 0.01) var foam_ramp_pull_tiles: float = 0.38
@export_range(0.0, 0.40, 0.01) var foam_shore_pull_tiles: float = 0.10

@onready var _water: HeightfieldMesh = $Surface

var last_cell_count: int = 0
var last_shore_count: int = 0
var _shore_root: Node3D
## 重建世代：笔刷连点时丢弃过期 await 尾段
var _build_gen: int = 0


func build(ctx) -> void:
	_build_gen += 1
	var gen := _build_gen
	var t_all := Time.get_ticks_msec()

	_water.clear_mesh()
	_clear_shore()
	last_cell_count = 0
	last_shore_count = 0

	var t0 := Time.get_ticks_msec()
	var params := Wc3WaterParams.load_for_tileset(ctx.main_tileset)
	var ms_params := Time.get_ticks_msec() - t0

	t0 = Time.get_ticks_msec()
	var built := Wc3WaterMesh.build(ctx.hf, params, height_bias_wc3, ctx.meta)
	var ms_mesh := Time.get_ticks_msec() - t0
	if built.is_empty():
		AppLog.debug(AppLog.Layer.PRESENT, "Water", "无水面网格（地图无水时正常）")
		AppLog.debug(
			AppLog.Layer.PRESENT,
			"Water",
			"timing params=%dms mesh=%dms (no water) total=%dms" % [ms_params, ms_mesh, Time.get_ticks_msec() - t_all]
		)
		return

	var mesh: ArrayMesh = built["mesh"]
	last_cell_count = int(built.get("cell_count", 0))
	_water.set_array_mesh(mesh)
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# 分帧：网格先上屏，再装贴图 / 岸浪
	await get_tree().process_frame
	if gen != _build_gen or not is_inside_tree():
		return

	t0 = Time.get_ticks_msec()
	var tex_pack: Dictionary = params.build_texture_array_cached()
	var tex_array: Texture2DArray = tex_pack.get("tex", null) as Texture2DArray
	var tex_cache_hit := bool(tex_pack.get("cache_hit", false))
	var ms_tex := Time.get_ticks_msec() - t0
	if tex_array == null:
		AppLog.warn(AppLog.Layer.PRESENT, "Water", "水面贴图数组为空（检查 I_Water00.png …）")
		AppLog.debug(
			AppLog.Layer.PRESENT,
			"Water",
			"timing params=%dms mesh=%dms tex=%dms (fail) total=%dms"
			% [ms_params, ms_mesh, ms_tex, Time.get_ticks_msec() - t_all]
		)
		return

	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("water_frames", tex_array)
	mat.set_shader_parameter("frame_count", params.frame_pngs.size())
	mat.set_shader_parameter("tex_rate", params.tex_rate)
	mat.render_priority = 1
	_water.apply_uniform_material(mat)

	AppLog.info(
		AppLog.Layer.PRESENT,
		"Water",
		"tiles=%d underRamp=%d frames=%d id=%s tex0=%s offset=%.1f bias=%.1f texRate=%.0f uvCells=%.0f (%.1fs/cycle) texCache=%s"
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
			"hit" if tex_cache_hit else "miss",
		]
	)

	await get_tree().process_frame
	if gen != _build_gen or not is_inside_tree():
		return

	t0 = Time.get_ticks_msec()
	_build_shore_foam(ctx, params)
	var ms_foam := Time.get_ticks_msec() - t0
	AppLog.debug(
		AppLog.Layer.PRESENT,
		"Water",
		"timing params=%dms mesh=%dms tex=%dms foam=%dms total=%dms"
		% [ms_params, ms_mesh, ms_tex, ms_foam, Time.get_ticks_msec() - t_all]
	)


func _build_shore_foam(ctx, params: Wc3WaterParams) -> void:
	var cliff_on := bool(ctx.map_flags.get("waterWavesCliff", true))
	var roll_on := bool(ctx.map_flags.get("waterWavesRolling", true))
	var t0 := Time.get_ticks_msec()
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
	var ms_scan := Time.get_ticks_msec() - t0
	var list: Array = collected.get("placements", []) as Array
	if list.is_empty():
		AppLog.debug(
			AppLog.Layer.PRESENT,
			"Water",
			"Shore foam: none (candidates=%d shallowSkip=%d cliff=%s roll=%s) scan=%dms"
			% [
				int(collected.get("edge_candidates", 0)),
				int(collected.get("skipped_shallow", 0)),
				cliff_on,
				roll_on,
				ms_scan,
			]
		)
		return

	_shore_root = Node3D.new()
	_shore_root.name = "ShoreFoam"
	add_child(_shore_root)
	t0 = Time.get_ticks_msec()
	last_shore_count = Wc3ShoreFoam.build_systems(_shore_root, list)
	var ms_mm := Time.get_ticks_msec() - t0
	AppLog.info(
		AppLog.Layer.PRESENT,
		"Water",
		"Shore foam: S=%d OC=%d IC=%d contour=%d cliff=%d instances=%d pull(r=%.2f s=%.2f) cliffOut+=%.2f scan=%dms mm=%dms"
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
			ms_scan,
			ms_mm,
		]
	)


func _clear_shore() -> void:
	if _shore_root and is_instance_valid(_shore_root):
		_shore_root.queue_free()
	_shore_root = null
	for c in get_children():
		if c != _water and str(c.name).begins_with("Shore"):
			c.queue_free()
