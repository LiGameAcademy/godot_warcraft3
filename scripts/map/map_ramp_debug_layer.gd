class_name MapRampDebugLayer
extends Node3D

## 斜坡逻辑调试：每个 FLAG_RAMP tilepoint 画蓝菱形（对齐 WE 标记）。
## 只读 flags + heights，不依赖 CliffTrans Present。

@export var enabled: bool = true

const COLOR := Color(0.22, 0.52, 1.0, 0.92)
const HALF_WC3 := 22.0
const Y_BIAS := 0.08

var last_count: int = 0
var _mesh_inst: MeshInstance3D


func build(ctx) -> void:
	_clear()
	last_count = 0
	if not enabled or ctx == null:
		return
	var meta: Dictionary = ctx.meta
	if meta.is_empty():
		meta = Wc3Heightfield.build_meta_from_dict(ctx.hf)
	var tp_w: int = int(meta.get("width", 0))
	var tp_h: int = int(meta.get("height", 0))
	var flags: Array = meta.get("flags", []) as Array
	var heights: Array = meta.get("heights", []) as Array
	var center: Vector2 = meta.get("center", Vector2.ZERO)
	var tile_size: float = float(meta.get("tile_size", Wc3Coords.TILE_SIZE))
	if tp_w < 1 or tp_h < 1 or flags.is_empty():
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	var half := HALF_WC3 * Wc3Coords.WORLD_SCALE
	for iy in range(tp_h):
		for ix in range(tp_w):
			var i: int = iy * tp_w + ix
			if i >= flags.size():
				continue
			if (int(flags[i]) & Wc3Coords.FLAG_RAMP) == 0:
				continue
			var h: float = float(heights[i]) if i < heights.size() else 0.0
			var xy := Wc3Coords.tilepoint_wc3(ix, iy, center, tile_size)
			var p: Vector3 = Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, h)
			p.y += Y_BIAS
			_add_diamond(st, p, half)
			n += 1
	if n == 0:
		return
	var mesh: ArrayMesh = st.commit()
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.name = "RampDiamonds"
	_mesh_inst.mesh = mesh
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = COLOR
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 90
	_mesh_inst.material_override = mat
	add_child(_mesh_inst)
	last_count = n


func _add_diamond(st: SurfaceTool, c: Vector3, half: float) -> void:
	var e := Vector3(c.x + half, c.y, c.z)
	var n := Vector3(c.x, c.y, c.z - half)
	var w := Vector3(c.x - half, c.y, c.z)
	var s := Vector3(c.x, c.y, c.z + half)
	st.set_normal(Vector3.UP)
	st.add_vertex(e)
	st.add_vertex(n)
	st.add_vertex(w)
	st.add_vertex(e)
	st.add_vertex(w)
	st.add_vertex(s)


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_mesh_inst = null
