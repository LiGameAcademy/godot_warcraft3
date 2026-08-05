class_name UnitSelector
extends Node
## 单位点选 / 框选（编辑器与游戏共用骨架）。
## 数据源：unit_host 下带 unit_data meta 的 Node3D（MapUnitLayer 子节点）。
## 预留：Shift 加选、Ctrl 编队（本阶段只做替换选中）。

const BuildingVisualScr = preload("res://scripts/map/presentation/building_visual.gd")

const SEL_CIRCLE_TEX := "ReplaceableTextures/Selection/SelectionCircleMed.png"
const SEL_RING_COLOR := Color(0.15, 1.0, 0.25, 1.0)
const SEL_RING_Y_BIAS := 0.06
## 点选：屏幕 AABB 外扩像素（建筑点选靠 AABB，单位靠中心半径兜底）
const PICK_PAD_PX := 8.0

signal selection_changed(primary: Node3D, selected: Array)

@export var enabled: bool = true
@export var pick_radius_px: float = 28.0
## ≥0 时只可选该 owner；-1 不限
@export var owner_filter: int = -1
@export var allow_buildings: bool = true
@export var allow_units: bool = true

var camera: Camera3D
var unit_host: Node
var overlay_parent: Control

var _marquee: MarqueeSelection = MarqueeSelection.new()
var _overlay: MarqueeOverlay = null
var _marqueeing: bool = false
var _selected: Array[Node3D] = []
var _primary: Node3D = null
var _ring_nodes: Dictionary = {} ## Node3D → MeshInstance3D


func _ready() -> void:
	_ensure_overlay()


func setup(p_camera: Camera3D, p_unit_host: Node, p_overlay_parent: Control = null) -> void:
	camera = p_camera
	unit_host = p_unit_host
	if p_overlay_parent != null:
		overlay_parent = p_overlay_parent
	_ensure_overlay()


func get_primary() -> Node3D:
	return _primary


func get_selected() -> Array[Node3D]:
	return _selected.duplicate()


func clear_selection() -> void:
	_set_selection([])


func select_node(node: Node3D) -> void:
	if node == null:
		clear_selection()
		return
	_set_selection([node])


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or camera == null or unit_host == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_on_press(mb.position)
			get_viewport().set_input_as_handled()
		else:
			_on_release(mb.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _marqueeing:
			_marquee.update((event as InputEventMouseMotion).position)
			get_viewport().set_input_as_handled()


func _on_press(screen_pos: Vector2) -> void:
	_marqueeing = true
	_marquee.begin(screen_pos)


func _on_release(screen_pos: Vector2) -> void:
	if not _marqueeing:
		return
	_marqueeing = false
	_marquee.update(screen_pos)
	var rect := _marquee.finish()
	if rect.size.x >= 0.5 and rect.size.y >= 0.5:
		_select_in_rect(rect)
	else:
		var picked := _pick_at(screen_pos)
		if picked != null:
			_set_selection([picked])
		else:
			clear_selection()


## 点选：优先「屏幕包围盒含鼠标」且面积最小（点农民不误点身后主城）；
## 否则回退到脚底投影点 + 动态半径（建筑半径按脚印放大）。
func _pick_at(screen_pos: Vector2) -> Node3D:
	if camera == null or unit_host == null:
		return null
	var best_box: Node3D = null
	var best_area := INF
	var best_dist: Node3D = null
	var best_d2 := INF
	for n in _iter_unit_nodes():
		var box := _screen_aabb(n)
		if box.has_area():
			var padded := box.grow(PICK_PAD_PX)
			if padded.has_point(screen_pos):
				var area := maxf(padded.get_area(), 1.0)
				if area < best_area:
					best_area = area
					best_box = n
		var world := n.global_position
		if camera.is_position_behind(world):
			continue
		var sp := camera.unproject_position(world)
		var rad := _pick_radius_for(n, sp)
		var d2 := sp.distance_squared_to(screen_pos)
		if d2 <= rad * rad and d2 < best_d2:
			best_d2 = d2
			best_dist = n
	if best_box != null:
		return best_box
	return best_dist


func _pick_radius_for(node: Node3D, screen_center: Vector2) -> float:
	var diam_w := _mesh_xz_diameter(node)
	if diam_w < 0.05:
		return pick_radius_px
	# 世界直径 → 屏幕近似半径：脚底点沿右轴偏移半直径再投影
	var half := diam_w * 0.5
	var edge_world := node.global_position + camera.global_transform.basis.x * half
	if camera.is_position_behind(edge_world):
		return maxf(pick_radius_px, 48.0)
	var edge_sp := camera.unproject_position(edge_world)
	var rad := screen_center.distance_to(edge_sp)
	return maxf(pick_radius_px, rad + PICK_PAD_PX)


func _screen_aabb(node: Node3D) -> Rect2:
	var aabb := _local_visual_aabb(node)
	if aabb.size.length() < 1e-5:
		return Rect2()
	var xf := node.global_transform
	var min_s := Vector2(INF, INF)
	var max_s := Vector2(-INF, -INF)
	var any := false
	for i in range(8):
		var corner := aabb.position + aabb.size * Vector3(
			float(i & 1),
			float((i >> 1) & 1),
			float((i >> 2) & 1)
		)
		var world := xf * corner
		if camera.is_position_behind(world):
			continue
		var sp := camera.unproject_position(world)
		min_s = min_s.min(sp)
		max_s = max_s.max(sp)
		any = true
	if not any:
		return Rect2()
	return Rect2(min_s, max_s - min_s)


func _select_in_rect(rect: Rect2) -> void:
	var hits: Array[Node3D] = []
	for n in _iter_unit_nodes():
		# 建筑：脚底或屏幕盒与框相交即可
		var box := _screen_aabb(n)
		if box.has_area() and box.intersects(rect):
			hits.append(n)
			continue
		if MarqueeSelection.world_in_rect(camera, n.global_position, rect):
			hits.append(n)
	_set_selection(hits)


func _iter_unit_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if unit_host == null:
		return out
	for c in unit_host.get_children():
		if not (c is Node3D):
			continue
		var n := c as Node3D
		if not n.has_meta("unit_data"):
			continue
		var d: Dictionary = n.get_meta("unit_data", {})
		var tid := str(d.get("typeId", ""))
		if tid == "sloc":
			continue
		if owner_filter >= 0 and int(d.get("owner", -1)) != owner_filter:
			continue
		var is_bldg := _looks_building(tid, d)
		if is_bldg and not allow_buildings:
			continue
		if not is_bldg and not allow_units:
			continue
		out.append(n)
	return out


func _looks_building(type_id: String, _d: Dictionary) -> bool:
	return BuildingVisualScr.is_building(type_id)


func _set_selection(nodes: Array) -> void:
	_selected.clear()
	for n in nodes:
		if n is Node3D and is_instance_valid(n):
			_selected.append(n as Node3D)
	if _selected.is_empty():
		_primary = null
	else:
		_primary = _selected[0]
	_refresh_rings()
	selection_changed.emit(_primary, _selected.duplicate())


func _ensure_overlay() -> void:
	if _overlay != null:
		return
	var parent: Node = overlay_parent
	if parent == null:
		var layer := CanvasLayer.new()
		layer.name = "SelectorOverlayLayer"
		layer.layer = 20
		add_child(layer)
		var root := Control.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(root)
		parent = root
	_overlay = MarqueeOverlay.new()
	_overlay.name = "MarqueeOverlay"
	parent.add_child(_overlay)
	_overlay.bind(_marquee)


func _refresh_rings() -> void:
	var keep: Dictionary = {}
	for n in _selected:
		if not is_instance_valid(n):
			continue
		keep[n] = true
		if _ring_nodes.has(n) and is_instance_valid(_ring_nodes[n]):
			_update_ring(_ring_nodes[n] as MeshInstance3D, n)
		else:
			_ring_nodes[n] = _make_ring(n)
	var stale: Array = []
	for k in _ring_nodes.keys():
		if not keep.has(k) or not is_instance_valid(k):
			stale.append(k)
	for k in stale:
		var ring: Node = _ring_nodes[k]
		_ring_nodes.erase(k)
		if is_instance_valid(ring):
			ring.queue_free()


func _make_ring(host: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "SelectionRing"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	plane.orientation = PlaneMesh.FACE_Y
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = 20
	mat.albedo_color = SEL_RING_COLOR
	var tex: Texture2D = RuntimeAssets.load_converted_texture(SEL_CIRCLE_TEX)
	if tex != null:
		mat.albedo_texture = tex
	mi.material_override = mat
	host.add_child(mi)
	_update_ring(mi, host)
	return mi


func _update_ring(mi: MeshInstance3D, host: Node3D) -> void:
	if mi == null or host == null:
		return
	var diam := _mesh_xz_diameter(host)
	if diam < 0.2:
		diam = 0.8
	var plane := mi.mesh as PlaneMesh
	if plane == null:
		plane = PlaneMesh.new()
		plane.orientation = PlaneMesh.FACE_Y
		mi.mesh = plane
	plane.size = Vector2(diam, diam)
	mi.position = Vector3(0.0, SEL_RING_Y_BIAS, 0.0)
	mi.visible = true


func _mesh_xz_diameter(node: Node3D) -> float:
	var aabb := _local_visual_aabb(node)
	if aabb.size.length() < 1e-5:
		return 0.0
	return maxf(aabb.size.x, aabb.size.z)


func _local_visual_aabb(node: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	for c in node.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		if str(vi.name) == "SelectionRing" or str(vi.name) == "DeathDropRing":
			continue
		var local := vi.get_aabb()
		if local.size.length() < 1e-5:
			continue
		var xf: Transform3D = node.global_transform.affine_inverse() * vi.global_transform
		var box := xf * local
		if first:
			aabb = box
			first = false
		else:
			aabb = aabb.merge(box)
	if first:
		return AABB()
	return aabb
