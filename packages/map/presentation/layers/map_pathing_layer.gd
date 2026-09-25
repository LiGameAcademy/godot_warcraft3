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
var _image: Image = null
var _static_snapshot: PackedByteArray = PackedByteArray()
var _dynamic_snapshot: PackedByteArray = PackedByteArray()


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
	_image = null
	_static_snapshot.clear()
	_dynamic_snapshot.clear()
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
	var full: bool = _image == null or _image.get_width() != w or _image.get_height() != h
	var changed: bool = full or _static_snapshot != pathing.cells or _dynamic_snapshot != pathing.cells_dynamic
	if changed:
		if full:
			_image = Image.create(w, h, false, Image.FORMAT_RGBA8)
			_image.fill(Color(0, 0, 0, 0))
			last_cell_count = 0
		for chunk in range(0, w * h, 1024):
			var end: int = mini(chunk + 1024, w * h)
			if not full and _static_snapshot.slice(chunk, end) == pathing.cells.slice(chunk, end) and _dynamic_snapshot.slice(chunk, end) == pathing.cells_dynamic.slice(chunk, end):
				continue
			for index in range(chunk, end):
				var flags: int = int(pathing.cells[index])
				if index < pathing.cells_dynamic.size():
					flags |= int(pathing.cells_dynamic[index])
				flags &= Wc3PathingMap.FLAG_NO_WALK | Wc3PathingMap.FLAG_NO_BUILD
				var previous: int = 0
				if not full:
					previous = int(_static_snapshot[index])
					if index < _dynamic_snapshot.size():
						previous |= int(_dynamic_snapshot[index])
					previous &= Wc3PathingMap.FLAG_NO_WALK | Wc3PathingMap.FLAG_NO_BUILD
				if flags == previous:
					continue
				last_cell_count += int(flags != 0) - int(previous != 0)
				var color: Color = Color(0, 0, 0, 0)
				if flags == (Wc3PathingMap.FLAG_NO_WALK | Wc3PathingMap.FLAG_NO_BUILD):
					color = COLOR_BOTH
				elif flags == Wc3PathingMap.FLAG_NO_WALK:
					color = COLOR_NO_WALK
				elif flags == Wc3PathingMap.FLAG_NO_BUILD:
					color = COLOR_NO_BUILD
				_image.set_pixel(index % w, h - 1 - int(index / w), color)
		_static_snapshot = pathing.cells.duplicate()
		_dynamic_snapshot = pathing.cells_dynamic.duplicate()
		if _tex == null:
			_tex = ImageTexture.create_from_image(_image)
		elif full:
			_tex.set_image(_image)
		else:
			_tex.update(_image)
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
		% [w, h, last_cell_count, pathing.origin_wc3]
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
