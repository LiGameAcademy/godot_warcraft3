class_name UnitSelector
extends Node
## 单位点选 / 框选（编辑器与游戏共用骨架）。
##
## 输入：专用全屏 Control（gui_input），挂在低于 HUD 的 CanvasLayer。
## 为何不用 `_unhandled_input` 做主路径：
## - HUD/Panel 等 Control 会先吃掉鼠标，框选矩形经常画不出来；
## - 全屏 STOP 层在 HUD 之下时，空白处进本层，按钮/小地图仍归 HUD。
##
## 点选：相机射线 vs 竖直胶囊（单位碰撞半径），不是屏幕 AABB。
## AABB 投影失误多（贴花/隐藏 geoset/透视变形），只作框选辅助。

const BuildingVisualScr = preload("res://scripts/map/presentation/building_visual.gd")

const SEL_CIRCLE_TEX := "ReplaceableTextures/Selection/SelectionCircleMed.png"
const SEL_RING_COLOR_OWN := Color(0.15, 1.0, 0.25, 1.0)
const SEL_RING_COLOR_NEUTRAL := Color(1.0, 0.92, 0.15, 1.0)
## 兼容旧名
const SEL_RING_COLOR := SEL_RING_COLOR_OWN
const SEL_RING_Y_BIAS := 0.06

enum RingKind {
	OWN = 1,
	NEUTRAL = 2,
}
## 无 SLK scale 时的默认拾取半径（Godot 单位 ≈ WC3 40）
const DEFAULT_UNIT_RADIUS := 0.40
const DEFAULT_BUILDING_RADIUS := 1.20
const DEFAULT_UNIT_HEIGHT := 1.20
const DEFAULT_BUILDING_HEIGHT := 3.50
## 射线未中胶囊时，脚底屏幕像素兜底半径
const FOOT_FALLBACK_PX := 36.0
## 建筑相对单位的射线距离惩罚（同屏重叠时优先点到农民）
const BUILDING_RAY_PENALTY := 1.75

signal selection_changed(primary: Node3D, selected: Array)

@export var enabled: bool = true
## ≥0 时只可选该 owner；-1 不限（点选仍可看中立金矿等）
@export var owner_filter: int = -1
## 框选（多选）仅保留该玩家单位/建筑；-1 不限。对齐原作：敌对/中立不可框选。
@export var marquee_owner: int = -1
@export var allow_buildings: bool = true
@export var allow_units: bool = true
## 输入层 CanvasLayer.layer；须低于 GameHud（默认 10）
@export var input_canvas_layer: int = 5

var camera: Camera3D
var unit_host: Node
var overlay_parent: Control
## 额外拾取（如树木 promote）：Callable(screen_pos: Vector2) -> Node3D
var pick_extra: Callable = Callable()

var _marquee: MarqueeSelection = MarqueeSelection.new()
var _overlay: MarqueeOverlay = null
var _input_root: Control = null
var _marqueeing: bool = false
var _selected: Array[Node3D] = []
var _primary: Node3D = null
var _ring_nodes: Dictionary = {} ## Node3D → MeshInstance3D
## typeId → 拾取半径缓存（Godot）
var _radius_cache: Dictionary = {}


func _ready() -> void:
	set_process(false)
	_ensure_input_layer()
	_ensure_overlay()
	# Director 若因脚本解析失败未 setup，下一帧自救绑定相机/单位层。
	call_deferred("_try_autobind")


func setup(p_camera: Camera3D, p_unit_host: Node, p_overlay_parent: Control = null) -> void:
	camera = p_camera
	unit_host = p_unit_host
	if p_overlay_parent != null:
		overlay_parent = p_overlay_parent
	set_process_input(true)
	if camera != null and not camera.is_inside_tree():
		pass
	elif camera != null:
		camera.make_current()
	_ensure_input_layer()
	# 允许 setup 时重建 overlay（_ready 可能已建在错误父节点下）
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
		_overlay = null
	_ensure_overlay()
	if camera == null or unit_host == null:
		push_warning("UnitSelector.setup: camera 或 unit_host 为空，点选/框选不可用")
	else:
		print("[UnitSelector] setup ok cam=%s host=%s children=%d filter=%d" % [
			camera.name, unit_host.name, unit_host.get_child_count(), owner_filter
		])


## Director 未调用 setup 时，从当前场景查找 RtsCamera / MapRoot.Units。
func _try_autobind() -> void:
	if camera != null and unit_host != null:
		return
	var scene: Node = get_tree().current_scene if get_tree() else null
	if scene == null:
		scene = get_parent()
	if scene == null:
		return
	if camera == null:
		var rts := scene.get_node_or_null("RtsCamera")
		if rts != null and rts.has_method("get_camera"):
			camera = rts.call("get_camera") as Camera3D
		if camera == null:
			camera = scene.find_child("Camera3D", true, false) as Camera3D
	if unit_host == null:
		var map_root := scene.get_node_or_null("MapRoot")
		if map_root != null and map_root.has_method("get_unit_layer"):
			unit_host = map_root.call("get_unit_layer")
		if unit_host == null:
			unit_host = scene.find_child("Units", true, false)
	if camera != null and unit_host != null:
		set_process_input(true)
		_ensure_input_layer()
		_ensure_overlay()
		print("[UnitSelector] autobind ok cam=%s host=%s" % [camera.name, unit_host.name])


## 供 GameDirector._input 转发。处理了左键点选/框选则返回 true。
func handle_pointer_event(event: InputEvent) -> bool:
	_try_autobind()
	if not enabled or camera == null or unit_host == null:
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		# 框选进行中：松手/续按必须完成，即使光标已滑到 HUD（否则抬起被底栏吞掉）
		if _marqueeing:
			if mb.pressed:
				return true
			_on_release(mb.position)
			return true
		if _hud_blocks_screen(mb.position):
			return false
		if mb.pressed:
			_on_press(mb.position)
		else:
			_on_release(mb.position)
		return true
	if event is InputEventMouseMotion and _marqueeing:
		var mm := event as InputEventMouseMotion
		_marquee.update(mm.position)
		return true
	return false


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


## 主输入：全屏层 gui_input（可靠）。`_unhandled_input` 仅作无层时的兜底。
func _on_world_gui_input(event: InputEvent) -> void:
	_try_autobind()
	if not enabled or camera == null or unit_host == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		# 与 handle_pointer_event 一致：框选中不受 HUD 区限制
		if _marqueeing:
			if not mb.pressed:
				_on_release(mb.position)
			if _input_root != null:
				_input_root.accept_event()
			return
		if _hud_blocks_screen(mb.position):
			return
		if mb.pressed:
			_on_press(mb.position)
		else:
			_on_release(mb.position)
		if _input_root != null:
			_input_root.accept_event()
	elif event is InputEventMouseMotion:
		if _marqueeing:
			_marquee.update((event as InputEventMouseMotion).position)
			if _input_root != null:
				_input_root.accept_event()


func _input(event: InputEvent) -> void:
	# 自身也会收；主路径由 GameDirector.handle 转发（更稳）。此处仅兜底。
	if handle_pointer_event(event):
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# 兜底：松手事件被 HUD Control 吃掉时，仍结束框选
	if _marqueeing and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_on_release(get_viewport().get_mouse_position())


func _hud_blocks_screen(screen_pos: Vector2) -> bool:
	# 粗略避开底栏 / 右上资源条，避免抢走 HUD 按钮。
	# 注意：框选进行中不要调用此函数拦截松手（见 handle_pointer_event）。
	var vp := get_viewport().get_visible_rect().size
	if vp.y <= 1.0:
		return false
	if screen_pos.y >= vp.y * 0.78:
		return true
	if screen_pos.y <= 52.0 and screen_pos.x >= vp.x - 340.0:
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	# 仅当输入层未建好时兜底（编辑器嵌入等）。
	if _input_root != null and is_instance_valid(_input_root):
		return
	_on_world_gui_input(event)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _marqueeing:
		get_viewport().set_input_as_handled()


func _on_press(screen_pos: Vector2) -> void:
	_marqueeing = true
	set_process(true)
	_marquee.begin(screen_pos)


func _on_release(screen_pos: Vector2) -> void:
	if not _marqueeing:
		return
	_marqueeing = false
	set_process(false)
	_marquee.update(screen_pos)
	var rect := _marquee.finish()
	if rect.size.x >= 0.5 and rect.size.y >= 0.5:
		_select_in_rect(rect)
	else:
		var picked := _pick_at(screen_pos)
		if picked == null and pick_extra.is_valid():
			picked = pick_extra.call(screen_pos) as Node3D
		if picked != null:
			_set_selection([picked])
		else:
			clear_selection()


## 供智能右键 / 采集瞄准：屏幕点选单位（含金矿建筑）。不含树木（树走 pick_extra）。
func pick_at(screen_pos: Vector2) -> Node3D:
	_try_autobind()
	return _pick_at(screen_pos)


## 点选：相机射线打竖直胶囊；未命中再脚底像素兜底。
func _pick_at(screen_pos: Vector2) -> Node3D:
	if camera == null or unit_host == null:
		return null
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if dir.length_squared() < 1e-10:
		return null
	dir = dir.normalized()

	var best_ray: Node3D = null
	var best_t := INF
	var best_foot: Node3D = null
	var best_foot_d2 := INF

	for n in _iter_unit_nodes():
		var d: Dictionary = n.get_meta("unit_data", {})
		var tid := str(d.get("typeId", ""))
		var is_bldg := _looks_building(tid, d)
		var radius := _pick_radius_world(n, tid, is_bldg)
		var height := _pick_height_world(n, is_bldg)
		var t := _ray_vertical_capsule(origin, dir, n.global_position, height, radius)
		if t >= 0.0:
			var score := t
			if is_bldg:
				score += BUILDING_RAY_PENALTY
			if score < best_t:
				best_t = score
				best_ray = n

		if camera.is_position_behind(n.global_position):
			continue
		var sp := camera.unproject_position(n.global_position)
		var d2 := sp.distance_squared_to(screen_pos)
		var foot_r := FOOT_FALLBACK_PX
		if is_bldg:
			foot_r *= 1.8
		if d2 > foot_r * foot_r:
			continue
		var foot_score := d2
		if is_bldg:
			foot_score += 900.0
		if foot_score < best_foot_d2:
			best_foot_d2 = foot_score
			best_foot = n

	if best_ray != null:
		return best_ray
	return best_foot


## 竖直胶囊（轴线 = 单位脚底沿 +Y）与射线求交，返回 t；未中返回 -1。
func _ray_vertical_capsule(
	origin: Vector3, dir: Vector3, base: Vector3, height: float, radius: float
) -> float:
	var h := maxf(height, 0.05)
	var r := maxf(radius, 0.05)
	# 胶囊 = 圆柱 + 两端半球；先测圆柱（足够 RTS 点选）
	var o := Vector2(origin.x, origin.z)
	var d := Vector2(dir.x, dir.z)
	var c := Vector2(base.x, base.z)
	var a := d.dot(d)
	var best_t := -1.0
	if a > 1e-10:
		var f := o - c
		var b := 2.0 * f.dot(d)
		var cc := f.dot(f) - r * r
		var disc := b * b - 4.0 * a * cc
		if disc >= 0.0:
			var sdisc := sqrt(disc)
			for ti in [( -b - sdisc) / (2.0 * a), ( -b + sdisc) / (2.0 * a)]:
				if ti < 0.0:
					continue
				var y: float = origin.y + dir.y * ti
				if y >= base.y - r and y <= base.y + h + r:
					if best_t < 0.0 or ti < best_t:
						best_t = ti
	else:
		# 射线近乎竖直：看 XZ 是否落在圆内
		if o.distance_to(c) <= r:
			var t_bottom := (base.y - origin.y) / dir.y if absf(dir.y) > 1e-6 else 0.0
			var t_top := (base.y + h - origin.y) / dir.y if absf(dir.y) > 1e-6 else 0.0
			var t0 := minf(t_bottom, t_top)
			var t1 := maxf(t_bottom, t_top)
			if t1 >= 0.0:
				best_t = maxf(t0, 0.0)
	return best_t


func _pick_radius_world(node: Node3D, type_id: String, is_bldg: bool) -> float:
	if _radius_cache.has(type_id):
		return float(_radius_cache[type_id])
	var r := DEFAULT_BUILDING_RADIUS if is_bldg else DEFAULT_UNIT_RADIUS
	# unitUI.scale ≈ 选中圈直径（WC3）；有则优先
	if not type_id.is_empty():
		Wc3DefStore.ensure_table(UnitUiDef.TABLE_NAME)
		var row: Resource = Wc3DefStore.get_row(UnitUiDef.TABLE_NAME, type_id)
		if row is UnitUiDef:
			var sc := (row as UnitUiDef).scale
			if sc > 1.0:
				r = sc * Wc3Coords.WORLD_SCALE * 0.5
	# 网格半宽兜底放大（避免 scale 偏小点不中）
	var mesh_r := _mesh_xz_diameter(node) * 0.45
	if mesh_r > r:
		r = mesh_r
	_radius_cache[type_id] = r
	return r


func _pick_height_world(node: Node3D, is_bldg: bool) -> float:
	var aabb := _local_visual_aabb(node)
	if aabb.size.y > 0.05:
		return maxf(aabb.size.y, 0.4)
	return DEFAULT_BUILDING_HEIGHT if is_bldg else DEFAULT_UNIT_HEIGHT


func _select_in_rect(rect: Rect2) -> void:
	var hits: Array[Node3D] = []
	for n in _iter_unit_nodes():
		if MarqueeSelection.world_in_rect(camera, n.global_position, rect):
			hits.append(n)
			continue
		# 建筑脚底可能偏中心：屏幕盒相交作补充
		var d: Dictionary = n.get_meta("unit_data", {})
		if _looks_building(str(d.get("typeId", "")), d):
			var box := _screen_aabb(n)
			if box.has_area() and box.intersects(rect):
				hits.append(n)
	# 框选：只收己方（中立金矿/敌对野怪不可多选）
	if marquee_owner >= 0:
		var owned: Array[Node3D] = []
		for n in hits:
			var ud: Dictionary = n.get_meta("unit_data", {})
			if int(ud.get("owner", -1)) == marquee_owner:
				owned.append(n)
		hits = owned
	# WC3：框选同时命中单位+建筑 → 只留单位；纯建筑框仍可选中建筑。
	_set_selection(_prefer_units_over_buildings(hits))


## 混合命中时优先单位（对齐原作框选）；仅建筑则原样返回。
func _prefer_units_over_buildings(nodes: Array[Node3D]) -> Array[Node3D]:
	var units: Array[Node3D] = []
	var buildings: Array[Node3D] = []
	for n in nodes:
		var d: Dictionary = n.get_meta("unit_data", {})
		if _looks_building(str(d.get("typeId", "")), d):
			buildings.append(n)
		else:
			units.append(n)
	if not units.is_empty():
		return units
	return buildings


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


func _iter_unit_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if unit_host == null:
		return out
	for c in unit_host.get_children():
		if not (c is Node3D):
			continue
		var n := c as Node3D
		# 离场单位（进矿 / 工地 / 训练中）不可点选、不可框选
		if not WorldMembership.is_in_world(n):
			continue
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


func _ensure_input_layer() -> void:
	if _input_root != null and is_instance_valid(_input_root):
		return
	var layer := CanvasLayer.new()
	layer.name = "SelectorInputLayer"
	layer.layer = input_canvas_layer
	add_child(layer)
	_input_root = Control.new()
	_input_root.name = "WorldInput"
	_input_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_input_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_input_root.gui_input.connect(_on_world_gui_input)
	layer.add_child(_input_root)


func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	# 始终用独立高图层，避免挂到 HUD Root 后被底栏盖住或坐标错位
	var layer := CanvasLayer.new()
	layer.name = "SelectorOverlayLayer"
	layer.layer = 100
	add_child(layer)
	var root := Control.new()
	root.name = "OverlayRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 0
	root.offset_top = 0
	root.offset_right = 0
	root.offset_bottom = 0
	layer.add_child(root)
	_overlay = MarqueeOverlay.new()
	_overlay.name = "MarqueeOverlay"
	root.add_child(_overlay)
	_overlay.bind(_marquee)
	# 下一帧强制铺满视口（部分环境下 anchor 首帧 size=0）
	if is_inside_tree():
		var vp_size := get_viewport().get_visible_rect().size
		root.set_deferred("size", vp_size)


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


func ring_kind_for(node: Node3D) -> int:
	if node == null:
		return RingKind.OWN
	var ud: Dictionary = node.get_meta("unit_data", {})
	var tid := str(ud.get("typeId", "")).strip_edges()
	# 树不可左键选中；黄环仅中立金矿等单位
	if tid == "ngol":
		return RingKind.NEUTRAL
	# 中立玩家（常见 12–15）选中也偏黄
	var owner_id := int(ud.get("owner", 0))
	if owner_id >= 12:
		return RingKind.NEUTRAL
	return RingKind.OWN


func _ring_color(kind: int) -> Color:
	match kind:
		RingKind.NEUTRAL:
			return SEL_RING_COLOR_NEUTRAL
		_:
			return SEL_RING_COLOR_OWN


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
	mat.albedo_color = _ring_color(ring_kind_for(host))
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
	var mat := mi.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = _ring_color(ring_kind_for(host))
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
		var vname := str(vi.name)
		if (
			vname == "SelectionRing"
			or vname == "DeathDropRing"
			or vname == "UberSplat"
		):
			continue
		if _is_under_named(vi, "Pe2Root"):
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


func _is_under_named(n: Node, root_name: String) -> bool:
	var p := n.get_parent()
	while p != null:
		if str(p.name) == root_name:
			return true
		p = p.get_parent()
	return false
