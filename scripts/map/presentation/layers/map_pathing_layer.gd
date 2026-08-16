class_name MapPathingLayer
extends Node3D
## View→路径-地面：把 WPM/合成寻路面写成贴图，叠到地表/悬崖 Shader（与栅格同源）。


@export var enabled: bool = false
@export var terrain_layer: MapTerrainLayer = null
@export var cliffs_layer: MapCliffLayer = null
@export var ramps_layer: MapRampLayer = null

## WE / war3mapPath.tga 通道：红=不可走，绿=不可飞，蓝=不可建；品红=不可走+不可建
const COLOR_NO_WALK := Color(1.0, 0.22, 0.18, 0.85)
const COLOR_NO_BUILD := Color(0.18, 0.42, 1.0, 0.85)
const COLOR_BOTH := Color(1.0, 0.2, 1.0, 0.9)

var last_cell_count: int = 0
var _tex: ImageTexture = null
var _placeholder: ImageTexture = null


func _ready() -> void:
	_resolve_layers()
	_ensure_placeholder()


func set_visible_overlay(on: bool) -> void:
	enabled = on
	if not on:
		_apply_uniforms(false, null, Vector2.ZERO, Vector2.ONE, Wc3Coords.PATHING_CELL)


func clear() -> void:
	last_cell_count = 0
	_tex = null
	_apply_uniforms(false, null, Vector2.ZERO, Vector2.ONE, Wc3Coords.PATHING_CELL)


## pathing: Wc3PathingMap；hf 仅用于对齐 origin（可选）。
func rebuild(pathing: Wc3PathingMap, hf: Wc3Heightfield = null) -> void:
	_resolve_layers()
	if not enabled or pathing == null or not pathing.is_valid():
		clear()
		return
	if hf != null and hf.is_valid():
		pathing.sync_origin_from_heightfield(hf)

	var w: int = pathing.width
	var h: int = pathing.height
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var blocked := 0
	for py in range(h):
		for px in range(w):
			var f: int = pathing.flag_at(px, py)
			var no_walk: bool = (f & Wc3PathingMap.FLAG_NO_WALK) != 0
			var no_build: bool = (f & Wc3PathingMap.FLAG_NO_BUILD) != 0
			if not no_walk and not no_build:
				continue
			var c: Color
			if no_walk and no_build:
				c = COLOR_BOTH
			elif no_walk:
				c = COLOR_NO_WALK
			else:
				c = COLOR_NO_BUILD
			# Image y=0 在顶 → 翻转写入，采样时再翻回
			img.set_pixel(px, h - 1 - py, c)
			blocked += 1
	last_cell_count = blocked
	# 原地更新纹理：已绑在地表 shader 上的 ImageTexture 必须 set_image，否则叠层看起来不刷新
	if _tex == null:
		_tex = ImageTexture.create_from_image(img)
	else:
		_tex.set_image(img)
	_apply_uniforms(
		true,
		_tex,
		pathing.origin_wc3,
		Vector2(float(w), float(h)),
		pathing.cell_size
	)
	AppLog.info(
		AppLog.Layer.PRESENT,
		"Pathing",
		"overlay %dx%d blocked=%d origin=%s"
		% [w, h, blocked, pathing.origin_wc3]
	)


func _ensure_placeholder() -> void:
	if _placeholder != null:
		return
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	_placeholder = ImageTexture.create_from_image(img)


func _resolve_layers() -> void:
	if terrain_layer == null:
		terrain_layer = get_node_or_null("../Terrain") as MapTerrainLayer
	if cliffs_layer == null:
		cliffs_layer = get_node_or_null("../Cliffs") as MapCliffLayer
	if ramps_layer == null:
		ramps_layer = get_node_or_null("../Ramps") as MapRampLayer


func _collect_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	if is_instance_valid(terrain_layer) and terrain_layer.has_method("get_debug_materials"):
		out.append_array(terrain_layer.get_debug_materials())
	if is_instance_valid(cliffs_layer) and cliffs_layer.has_method("get_debug_materials"):
		out.append_array(cliffs_layer.get_debug_materials())
	if is_instance_valid(ramps_layer) and ramps_layer.has_method("get_debug_materials"):
		out.append_array(ramps_layer.get_debug_materials())
	return out


func _apply_uniforms(
	on: bool,
	tex: Texture2D,
	origin: Vector2,
	size_cells: Vector2,
	cell: float
) -> void:
	_ensure_placeholder()
	_resolve_layers()
	var mats := _collect_materials()
	var use_tex: Texture2D = tex if tex != null else _placeholder
	for mat in mats:
		mat.set_shader_parameter("pathing_ground", on)
		mat.set_shader_parameter("pathing_map_tex", use_tex)
		mat.set_shader_parameter("pathing_origin", origin)
		mat.set_shader_parameter("pathing_size_cells", size_cells)
		mat.set_shader_parameter("pathing_cell", cell)
	if on and mats.is_empty():
		AppLog.warn(AppLog.Layer.PRESENT, "Pathing", "无可用地表材质，路径-地面无法显示")
