class_name MapWaterLayer
extends Node3D
## 水体层（HiveWE 第一层）：含水格网格 + 深度色 + Water 序列帧动画。


const WATER_SHADER: Shader = preload("res://shaders/wc3_water.gdshader")

## 相对官方 waterOffset 的微调（WC3 单位，正值抬高水面）。默认 0=纯数据。
@export var height_bias_wc3: float = 0.0

@onready var _water: HeightfieldMesh = $Surface

var last_cell_count: int = 0


func build(hf: Dictionary, main_tileset: String = "I") -> void:
	_water.clear_mesh()
	last_cell_count = 0

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
		"Water: cells=%d frames=%d id=%s offset=%.1f bias=%.1f texRate=%.0f (%.1fs/cycle)"
		% [
			last_cell_count,
			params.frame_pngs.size(),
			params.water_id,
			params.height_offset_wc3(),
			height_bias_wc3,
			params.tex_rate,
			float(params.frame_pngs.size()) / maxf(params.tex_rate, 0.001),
		]
	)
