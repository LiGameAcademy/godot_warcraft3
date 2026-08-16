class_name MapBoundaryLayer
extends Node3D
## 不可玩区暗色 overlay：cell BL 带 FLAG_BOUNDARY | FLAG_MAP_EDGE 时盖一层半透明黑。
## HiveWE 3D 不画边界暗色；WE「实用区域」外缘靠我们自己提示。


const LIFT_WC3 := 2.0 ## 略抬高，避免与地面 z-fight
const OVERLAY_COLOR := Color(0.02, 0.02, 0.05, 0.55)

var last_cell_count: int = 0
var _mesh_inst: MeshInstance3D


func _ready() -> void:
	_ensure_mesh()


func build(ctx: MapBuildContext) -> void:
	_ensure_mesh()
	_mesh_inst.mesh = null
	last_cell_count = 0
	if ctx == null or ctx.heightfield == null or not ctx.heightfield.is_valid():
		return
	var hf: Wc3Heightfield = ctx.heightfield
	var tp_w: int = hf.width
	var tp_h: int = hf.height
	if tp_w < 2 or tp_h < 2:
		return
	var mw: int = hf.map_width if hf.map_width > 0 else tp_w - 1
	var mh: int = hf.map_height if hf.map_height > 0 else tp_h - 1
	var center: Vector2 = hf.center_offset
	var tile_size: float = hf.tile_size
	var heights: Array = hf.heights
	var flags: Array = hf.flags_packed

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	var cell_count := 0
	var up := Vector3.UP

	for iy in range(mh):
		for ix in range(mw):
			var i00: int = iy * tp_w + ix
			if i00 < 0 or i00 >= flags.size():
				continue
			if not Wc3Coords.is_unplayable_cell_flags(int(flags[i00])):
				continue
			cell_count += 1
			var i10: int = i00 + 1
			var i01: int = i00 + tp_w
			var i11: int = i01 + 1
			var h00: float = float(heights[i00]) + LIFT_WC3
			var h10: float = float(heights[i10]) + LIFT_WC3
			var h01: float = float(heights[i01]) + LIFT_WC3
			var h11: float = float(heights[i11]) + LIFT_WC3
			var p00 := HeightfieldMesh.sample_vert(ix, iy, h00, center, tile_size)
			var p10 := HeightfieldMesh.sample_vert(ix + 1, iy, h10, center, tile_size)
			var p01 := HeightfieldMesh.sample_vert(ix, iy + 1, h01, center, tile_size)
			var p11 := HeightfieldMesh.sample_vert(ix + 1, iy + 1, h11, center, tile_size)
			_emit_tri(verts, norms, cols, indices, p00, p01, p11, up)
			_emit_tri(verts, norms, cols, indices, p00, p11, p10, up)

	last_cell_count = cell_count
	if verts.is_empty():
		AppLog.debug(AppLog.Layer.PRESENT, "Boundary", "无不可玩格")
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_inst.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = 2
	_mesh_inst.material_override = mat
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	AppLog.info(
		AppLog.Layer.PRESENT,
		"Boundary",
		"unplayable cells=%d" % cell_count
	)


func _ensure_mesh() -> void:
	if _mesh_inst != null and is_instance_valid(_mesh_inst):
		return
	_mesh_inst = get_node_or_null("Overlay") as MeshInstance3D
	if _mesh_inst == null:
		_mesh_inst = MeshInstance3D.new()
		_mesh_inst.name = "Overlay"
		add_child(_mesh_inst)


func _emit_tri(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	cols: PackedColorArray,
	indices: PackedInt32Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	n: Vector3
) -> void:
	var base: int = verts.size()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	norms.append(n)
	norms.append(n)
	norms.append(n)
	cols.append(OVERLAY_COLOR)
	cols.append(OVERLAY_COLOR)
	cols.append(OVERLAY_COLOR)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
