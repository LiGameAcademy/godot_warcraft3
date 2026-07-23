class_name MapRampDebugLayer
extends Node3D
## 斜坡调试层：每个 FLAG_RAMP 的 tilepoint 画蓝菱形（对齐 WE 标记）。
## Y 优先贴 ramp 平面（与甲板一致），避免落在台阶 heights 上显得悬空/埋地。


@export var enabled: bool = true

const COLOR := Color(0.22, 0.52, 1.0, 0.92)
const HALF_WC3 := 22.0 ## 菱形半宽（WC3 单位）；略大于中级栅格交点，便于目视
const Y_BIAS := 0.08 ## Godot 米，避免 z-fight

var last_count: int = 0
var _mesh_inst: MeshInstance3D


func build(ctx) -> void:
	_clear()
	last_count = 0
	if not enabled or ctx == null:
		return
	var meta: Dictionary = ctx.meta
	if meta.is_empty():
		meta = HeightfieldMeshBuilder.read_heightfield_meta(ctx.hf)
	var tp_w: int = int(meta.get("width", 0))
	var tp_h: int = int(meta.get("height", 0))
	var flags: Array = meta.get("flags", []) as Array
	var raw_heights: Array = meta.get("heights", []) as Array
	var layer_heights: Array = meta.get("layer_heights", []) as Array
	# 与地面甲板同一套入口抬升，避免菱形悬空/埋地
	var heights: Array = Wc3CliffTiles.apply_ramp_entrance_heights(
		raw_heights, layer_heights, flags, tp_w, tp_h
	)
	var center: Vector2 = meta.get("center", Vector2.ZERO)
	var tile_size: float = float(meta.get("tile_size", Wc3Coords.TILE_SIZE))
	if tp_w < 1 or tp_h < 1 or flags.is_empty():
		return

	var placements: Array = ctx.cliff_ramp_placements
	if placements.is_empty() and not ctx.hf.is_empty():
		var rd: Dictionary = Wc3CliffTiles.collect_ramp_placements(ctx.hf, meta)
		placements = rd.get("placements", []) as Array

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
			# 贴坡面：与地面甲板同一套 A→B 插值
			var rh: float = Wc3CliffTiles.sample_ramp_plane_height(
				heights, placements, tp_w, tp_h, float(ix), float(iy)
			)
			if not is_nan(rh):
				h = rh
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
	# XZ 平面菱形（Godot：Y-up）
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
