class_name UnitSelector
extends Node
## 点选/框选中央裁决（输入 + 2D 脚底圆查询）。
## 选中环 / 拾取半径数据在 SelectableComponent；交互闪环在 InteractableComponent。
##
## 输入：专用全屏 Control（gui_input），挂在低于 HUD 的 CanvasLayer。

## 建筑略大半径惩罚：同点多圆重叠时优先小单位 / 近圆心
const BUILDING_RADIUS_SCORE_MUL := 0.35
## 射线近乎水平时：脚底屏幕像素兜底
const FOOT_FALLBACK_UNIT_PX := 52.0
const FOOT_FALLBACK_BUILDING_PX := 28.0

## 兼容旧 API
enum RingKind {
	OWN = 1,
	NEUTRAL = 2,
}

signal selection_changed(primary: Node3D, selected: Array)

@export var enabled: bool = true
## ≥0 时只可选该 owner；-1 不限（点选可观察敌方/中立；下达指令看可控过滤）
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
## 上一帧挂着选中环的宿主（用于取消选中时 hide）
var _ring_hosts: Array[Node3D] = []
## 当前悬停预览宿主（未选中单位/建筑；不含树木）
var _hover_host: Node3D = null


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
	# 预热表，避免首次点选 ensure_table 尖峰
	Wc3DefStore.ensure_table(UnitBalanceDef.TABLE_NAME)
	Wc3DefStore.ensure_table(UnitUiDef.TABLE_NAME)
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
		AppLog.warn(AppLog.Layer.GAME, "UnitSelector", "setup: camera 或 unit_host 为空，点选/框选不可用")
	else:
		AppLog.info(
			AppLog.Layer.GAME,
			"UnitSelector",
			"setup ok cam=%s host=%s children=%d filter=%d"
			% [camera.name, unit_host.name, unit_host.get_child_count(), owner_filter]
		)


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
		AppLog.info(
			AppLog.Layer.GAME,
			"UnitSelector",
			"autobind ok cam=%s host=%s" % [camera.name, unit_host.name]
		)


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
	if event is InputEventMouseMotion and not _marqueeing:
		_update_hover((event as InputEventMouseMotion).position)
		return false
	return false


func get_primary() -> Node3D:
	return _primary


func get_selected() -> Array[Node3D]:
	return _selected.duplicate()


## 多选时切换「当前选中」（肖像 / 命令卡跟随）。无人数上限。
func cycle_primary(step: int = 1) -> bool:
	if _selected.size() <= 1:
		return false
	var idx := _selected.find(_primary)
	if idx < 0:
		idx = 0
	var n := _selected.size()
	idx = posmod(idx + step, n)
	var next := _selected[idx]
	if next == _primary:
		return false
	_primary = next
	_refresh_rings()
	selection_changed.emit(_primary, _selected.duplicate())
	return true


## 将已在选中集合内的单位设为当前选中。
func set_primary(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not _selected.has(node):
		return false
	if node == _primary:
		return true
	_primary = node
	_refresh_rings()
	selection_changed.emit(_primary, _selected.duplicate())
	return true


func clear_selection() -> void:
	_set_selection([])


## 从选中集合移除单个单位（死亡 / 离场）；若为空则清空 primary。
func deselect_unit(node: Node3D) -> void:
	if node == null:
		return
	if not _selected.has(node):
		return
	var next: Array = []
	for n in _selected:
		if n != node and is_instance_valid(n):
			next.append(n)
	_set_selection(next)


func select_node(node: Node3D) -> void:
	if node == null:
		clear_selection()
		return
	_set_selection([node])


## 悬停预览：单位/建筑脚底半透明环；树木与已选中目标不显示。
func _update_hover(screen_pos: Vector2) -> void:
	_try_autobind()
	if not enabled or camera == null or unit_host == null:
		_clear_hover()
		return
	if _hud_blocks_screen(screen_pos):
		_clear_hover()
		return
	var picked := _pick_at(screen_pos)
	if picked != null and _is_tree_like(picked):
		picked = null
	if picked != null and _selected.has(picked):
		picked = null
	if picked == _hover_host:
		return
	_clear_hover()
	if picked == null:
		return
	InteractionSetup.attach(picked)
	var sel := InteractionSetup.get_selectable(picked)
	if sel == null:
		return
	sel.show_hover()
	_hover_host = picked


func _clear_hover() -> void:
	if _hover_host == null:
		return
	if is_instance_valid(_hover_host):
		var sel := InteractionSetup.get_selectable(_hover_host)
		if sel != null:
			sel.hide_hover()
	_hover_host = null


func _is_tree_like(n: Node3D) -> bool:
	if n == null:
		return false
	if n.has_meta("tree_runtime") or n.has_meta("doodad_data"):
		return true
	return false


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
		else:
			_update_hover((event as InputEventMouseMotion).position)


func _input(event: InputEvent) -> void:
	# 自身也会收；主路径由 GameDirector.handle 转发（更稳）。此处仅兜底。
	if handle_pointer_event(event):
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# 兜底：松手事件被 HUD Control 吃掉时，仍结束框选
	if _marqueeing and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_on_release(get_viewport().get_mouse_position())


func _hud_blocks_screen(screen_pos: Vector2) -> bool:
	# 注意：框选进行中不要调用此函数拦截松手（见 handle_pointer_event）。
	# 主判据：鼠标下已有接事件的 Control（HUD / GM / 命令卡 / Option 弹出项）。
	# 框选走 _input 早于 GUI；若不让路，GM 勾选/下拉会被点选吃掉。
	var viewport := get_viewport()
	if viewport == null:
		return false
	var hovered := viewport.gui_get_hovered_control()
	if hovered != null and _is_ui_control_blocking(hovered):
		return true
	# 兜底：底栏 / 右上资源条（hovered 偶发为空时）
	var vp := viewport.get_visible_rect().size
	if vp.y <= 1.0:
		return false
	if screen_pos.y >= vp.y * 0.78:
		return true
	if screen_pos.y <= 52.0 and screen_pos.x >= vp.x - 340.0:
		return true
	return false


func _is_ui_control_blocking(ctrl: Control) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	# 选择器自建穿透层 / 框选 overlay：不算 UI
	if _input_root != null and is_instance_valid(_input_root):
		if ctrl == _input_root or _input_root.is_ancestor_of(ctrl):
			return false
	if _overlay != null and is_instance_valid(_overlay):
		if ctrl == _overlay or _overlay.is_ancestor_of(ctrl):
			return false
	# IGNORE 控件不抢点击（全屏 HUD 根常为 IGNORE）
	if ctrl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	return true


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
	_clear_hover()
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


## 供智能右键 / 采集瞄准：屏幕点选单位（含金矿建筑）。不含树木（树走 TreeRegistry）。
func pick_at(screen_pos: Vector2) -> Node3D:
	_try_autobind()
	return _pick_at(screen_pos)


## 脚底到屏幕点的像素距离；不可见/无相机返回 INF。
func screen_foot_distance(node: Node3D, screen_pos: Vector2) -> float:
	if camera == null or node == null or not is_instance_valid(node):
		return INF
	if camera.is_position_behind(node.global_position):
		return INF
	return camera.unproject_position(node.global_position).distance_to(screen_pos)


## 点选：射线 ∩ 脚底水平面，世界 XZ 落在拾取圆内即命中（无高度胶囊）。
## 半径：UnitBalance.collision → UnitUI.scale → 有限 mesh 放宽。
## 优先级：单位圆 > 建筑圆；同分取距圆心更近 / 半径更小。
## 注意：热路径不调用 InteractionSetup.attach——否则首次点击会给全图单位实例化 SelectionRing。
func _pick_at(screen_pos: Vector2) -> Node3D:
	if camera == null or unit_host == null:
		return null
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if dir.length_squared() < 1e-10:
		return null
	dir = dir.normalized()

	var best_unit: Node3D = null
	var best_unit_score := INF
	var best_bldg: Node3D = null
	var best_bldg_score := INF

	for n in _iter_unit_nodes():
		var is_bldg := _node_is_building(n)
		var radius := _pick_radius_of(n)
		var hit := _ray_foot_plane_hit(origin, dir, n.global_position)
		var score := INF
		var hit_ok := false
		if hit.t >= 0.0:
			var dist_xz := Vector2(hit.pos.x, hit.pos.z).distance_to(
				Vector2(n.global_position.x, n.global_position.z)
			)
			if dist_xz <= radius:
				hit_ok = true
				score = dist_xz + radius * (BUILDING_RADIUS_SCORE_MUL if is_bldg else 0.05)
				score += hit.t * 0.02
		# 近水平射线或圆未命中：脚底屏幕像素兜底（仍是 2D）
		if not hit_ok:
			if camera.is_position_behind(n.global_position):
				continue
			var sp := camera.unproject_position(n.global_position)
			var d2 := sp.distance_squared_to(screen_pos)
			var foot_px := FOOT_FALLBACK_BUILDING_PX if is_bldg else FOOT_FALLBACK_UNIT_PX
			if d2 > foot_px * foot_px:
				continue
			hit_ok = true
			score = 40.0 + sqrt(d2) * 0.02 + radius * (BUILDING_RADIUS_SCORE_MUL if is_bldg else 0.05)
		if not hit_ok:
			continue
		if is_bldg:
			if score < best_bldg_score:
				best_bldg_score = score
				best_bldg = n
		elif score < best_unit_score:
			best_unit_score = score
			best_unit = n

	if best_unit != null:
		return best_unit
	return best_bldg


## 射线与脚底水平面（y = foot.y）求交；t < 0 表示在相机后方。
func _ray_foot_plane_hit(origin: Vector3, dir: Vector3, foot: Vector3) -> Dictionary:
	if absf(dir.y) < 1e-8:
		return {"t": -1.0, "pos": Vector3.ZERO}
	var t := (foot.y - origin.y) / dir.y
	if t < 0.0:
		return {"t": -1.0, "pos": Vector3.ZERO}
	return {"t": t, "pos": origin + dir * t}


func _select_in_rect(rect: Rect2) -> void:
	var hits: Array[Node3D] = []
	for n in _iter_unit_nodes():
		# 框选热路径不 attach；allow_marquee 用 owner/中立启发式
		if not _allows_marquee(n):
			continue
		var radius := _pick_radius_of(n)
		if _footprint_in_marquee(n, radius, rect):
			hits.append(n)
	# 框选：只收己方（中立金矿/敌对野怪不可多选）
	if marquee_owner >= 0:
		var owned: Array[Node3D] = []
		for n in hits:
			var oid := _owner_of(n)
			if oid == marquee_owner:
				owned.append(n)
		hits = owned
	# WC3：框选同时命中单位+建筑 → 只留单位；纯建筑框仍可选中建筑。
	_set_selection(_prefer_units_over_buildings(hits))


## 框选命中：脚底投影在框内，或脚底圆在屏幕上与框相交（不用 mesh AABB）。
func _footprint_in_marquee(node: Node3D, radius: float, rect: Rect2) -> bool:
	if camera == null or node == null:
		return false
	if MarqueeSelection.world_in_rect(camera, node.global_position, rect):
		return true
	if camera.is_position_behind(node.global_position):
		return false
	var foot_sp := camera.unproject_position(node.global_position)
	var edge := node.global_position + Vector3(maxf(radius, 0.12), 0.0, 0.0)
	if camera.is_position_behind(edge):
		return false
	var r_px := foot_sp.distance_to(camera.unproject_position(edge))
	r_px = clampf(r_px, 4.0, 120.0)
	return _distance_point_to_rect(foot_sp, rect) <= r_px


func _distance_point_to_rect(p: Vector2, rect: Rect2) -> float:
	var x := clampf(p.x, rect.position.x, rect.position.x + rect.size.x)
	var y := clampf(p.y, rect.position.y, rect.position.y + rect.size.y)
	return p.distance_to(Vector2(x, y))


## 混合命中时优先单位（对齐原作框选）；仅建筑则原样返回。
func _prefer_units_over_buildings(nodes: Array[Node3D]) -> Array[Node3D]:
	var units: Array[Node3D] = []
	var buildings: Array[Node3D] = []
	for n in nodes:
		if _node_is_building(n):
			buildings.append(n)
		else:
			units.append(n)
	if not units.is_empty():
		return units
	return buildings


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
		var is_bldg := _node_is_building(n, tid)
		if is_bldg and not allow_buildings:
			continue
		if not is_bldg and not allow_units:
			continue
		out.append(n)
	return out


## 不触发 attach / mesh 遍历；有 Selectable 则用其缓存半径。
func _pick_radius_of(n: Node3D) -> float:
	var sel := InteractionSetup.get_selectable(n)
	if sel != null:
		return sel.pick_radius_world()
	return _estimate_pick_radius(n)


func _estimate_pick_radius(n: Node3D) -> float:
	var tid := _type_id_of(n)
	var is_bldg := BuildingVisual.is_building(tid)
	var r := (
		SelectableComponent.DEFAULT_BUILDING_RADIUS
		if is_bldg
		else SelectableComponent.DEFAULT_UNIT_RADIUS
	)
	if not tid.is_empty():
		Wc3DefStore.ensure_table(UnitBalanceDef.TABLE_NAME)
		var bal: Resource = Wc3DefStore.get_row(UnitBalanceDef.TABLE_NAME, tid)
		if bal is UnitBalanceDef:
			var col := (bal as UnitBalanceDef).collision
			if col > 0.0:
				r = col * Wc3Coords.WORLD_SCALE
	var cap := (
		SelectableComponent.MAX_BUILDING_PICK_RADIUS
		if is_bldg
		else SelectableComponent.MAX_UNIT_PICK_RADIUS
	)
	return clampf(r, 0.12, cap)


func _node_is_building(n: Node3D, tid: String = "") -> bool:
	var sel := InteractionSetup.get_selectable(n)
	if sel != null:
		return sel.is_building()
	if tid.is_empty():
		tid = _type_id_of(n)
	return BuildingVisual.is_building(tid)


func _type_id_of(n: Node3D) -> String:
	if n == null:
		return ""
	var d: Dictionary = n.get_meta("unit_data", {})
	return str(d.get("typeId", "")).strip_edges()


func _owner_of(n: Node3D) -> int:
	var sel := InteractionSetup.get_selectable(n)
	if sel != null:
		return sel.owner_id()
	if n == null:
		return -1
	return int(n.get_meta("unit_data", {}).get("owner", -1))


func _allows_marquee(n: Node3D) -> bool:
	var sel := InteractionSetup.get_selectable(n)
	if sel != null:
		return sel.allow_marquee
	# 无 Selectable：中立不可框选（与 SelectableComponent._refresh_allow_marquee 一致）
	var oid := _owner_of(n)
	if oid >= 12 or _type_id_of(n) == "ngol":
		return false
	return true


func _set_selection(nodes: Array) -> void:
	# 故意不设原作 12 人框选上限：选中集合可任意大。
	_clear_hover()
	_selected.clear()
	for n in nodes:
		if n is Node3D and is_instance_valid(n):
			_selected.append(n as Node3D)
	if _selected.is_empty():
		_primary = null
	else:
		if _primary == null or not is_instance_valid(_primary) or not _selected.has(_primary):
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
	var multi := _selected.size()
	for n in _selected:
		if not is_instance_valid(n):
			continue
		keep[n] = true
		var sel := InteractionSetup.get_selectable(n)
		if sel == null:
			InteractionSetup.attach(n)
			sel = InteractionSetup.get_selectable(n)
		if sel != null:
			sel.show_selected(n == _primary, multi)
	for n2 in _ring_hosts:
		if not is_instance_valid(n2) or keep.has(n2):
			continue
		var sel2 := InteractionSetup.get_selectable(n2)
		if sel2 != null:
			sel2.hide_selected()
	_ring_hosts.clear()
	for n3 in _selected:
		if is_instance_valid(n3):
			_ring_hosts.append(n3)


func ring_kind_for(node: Node3D) -> int:
	InteractionSetup.attach(node)
	var sel := InteractionSetup.get_selectable(node)
	if sel != null:
		return sel.ring_kind()
	return RingKind.OWN


## 选中圈直径（世界单位）；供右键交互闪环复用。
func selection_ring_diameter_for(host: Node3D) -> float:
	InteractionSetup.attach(host)
	var sel := InteractionSetup.get_selectable(host)
	if sel != null:
		return sel.ring_diameter_world()
	return 1.1
