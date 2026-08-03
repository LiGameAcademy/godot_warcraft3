extends Node3D
## 装饰物笔刷：放置幽灵 + LMB 放置；点选 / 框选多选 / 拖动 / Delete / [ ] 旋转。
## 朝向来自 Inspect「放置朝向」，与预览环视分离。


signal rebuild_requested
signal brush_settings_changed(size: int, shape: int)
signal placed(count: int)
signal selection_changed(creation_number: int) ## primary cn；-1 = 无选中
signal deleted(count: int)
signal facing_changed(angle_deg: float) ## 笔刷朝向变化（无选中时 [ ] / R）
signal palette_cleared ## Esc 取消放置预览 / 清空笔刷类型

const DoodadEditCommandScript := preload("res://editor/scripts/commands/doodad_edit_command.gd")
const _Pe2 := preload("res://scripts/map/presentation/effects/wc3_pe2_particles.gd")

const REBUILD_INTERVAL_MS := 80
const PLACE_SPACING_TILES := 0.5 ## 拖拽节流：半格（与吸附步进一致）
const INVALID_POS := Vector2(1e20, 1e20)
const PICK_RADIUS_PX := 28.0
const GHOST_ALPHA := 0.45
const ROTATE_STEP_DEG := 45.0
## 吸附步进（地形格比例）。HiveWE 有 pathing 时：round(pos*2)*0.5 → 半格。
const SNAP_TILE_FRAC := 0.5

var document ## MapDocument
var camera: Camera3D
var space: World3D
var history: EditorCommandHistory = null
var map_loader: MapLoader = null

var _enabled: bool = false
var enabled: bool:
	get:
		return _enabled
	set(v):
		_enabled = v
		if not _enabled:
			_cancel_marquee()
			clear_selection()
			_hide_ghost()
		set_process(_enabled)

var brush_size: int = 1
var brush_shape: int = 0 ## 0 circle, 1 square

var type_id: String = ""
var variation: int = 0
var num_var: int = 1
var angle_deg: float = 270.0
var place_scale: float = 1.0
var random_variation: bool = true
## 放置随机（WE 四按钮）：旋转角 / 对称缩放 / WC3-Z 高度 / WC3-XY 水平面
var random_rotation: bool = true
var random_scale_sym: bool = false
var random_scale_z: bool = false
var random_scale_xy: bool = false

var _painting: bool = false
var _stroke_entries: Array = []
var _last_place_wc3: Vector2 = INVALID_POS
var _last_rebuild_ms: int = 0

## 框选（由 Editor 注入；仅 type_id 为空的选择态使用）
var _marquee: MarqueeSelection = null

## 选中 / 拖动（_selected_cn = primary，供 Inspect / selection_changed）
var _selected_cn: int = -1
var _selected_cns: PackedInt32Array = PackedInt32Array()
var _dragging: bool = false
var _drag_befores: Array = [] ## 多选拖动：各条目 before 快照
var _drag_anchor_cn: int = -1 ## 拖动锚点（按下时点中的实例）
var _sel_markers: Array[MeshInstance3D] = []

## 放置幽灵
var _ghost: Node3D = null
var _ghost_type: String = ""
var _ghost_var: int = -1
var _last_hover_screen: Vector2 = Vector2(1e20, 1e20)


func setup(doc, cam: Camera3D, world: World3D, p_history: EditorCommandHistory = null, loader: MapLoader = null) -> void:
	document = doc
	camera = cam
	space = world
	history = p_history
	map_loader = loader
	_update_sel_markers()
	set_process(_enabled)


func set_marquee(m: MarqueeSelection) -> void:
	_marquee = m


func _process(_delta: float) -> void:
	# 不依赖 MouseMotion：从面板点选后、快捷键旋转后也能立刻刷新幽灵
	if not _enabled or type_id.is_empty() or _painting or _dragging:
		return
	_poll_ghost_from_mouse()


func set_brush_settings(size: int, shape: int) -> void:
	brush_size = _sanitize_brush_size(size)
	brush_shape = 0 if shape == 0 else 1


func nudge_brush_size(dir: int) -> void:
	const SIZES := [1, 2, 3, 5, 8]
	var idx: int = SIZES.find(brush_size)
	if idx < 0:
		idx = 0
	idx = clampi(idx + dir, 0, SIZES.size() - 1)
	set_brush_settings(SIZES[idx], brush_shape)
	brush_settings_changed.emit(brush_size, brush_shape)


func set_palette(
	p_type_id: String,
	p_variation: int,
	p_angle_deg: float,
	p_scale: float,
	p_random: bool,
	p_num_var: int = 1,
	p_random_rotation: bool = false,
	p_random_scale_sym: bool = false,
	p_random_scale_z: bool = false,
	p_random_scale_xy: bool = false,
) -> void:
	var new_type := p_type_id.strip_edges()
	var type_changed := type_id != new_type or variation != p_variation
	type_id = new_type
	num_var = maxi(p_num_var, 1)
	variation = clampi(p_variation, 0, num_var - 1)
	angle_deg = p_angle_deg
	place_scale = maxf(p_scale, 0.01)
	random_variation = p_random
	random_rotation = p_random_rotation
	random_scale_sym = p_random_scale_sym
	random_scale_z = p_random_scale_z
	random_scale_xy = p_random_scale_xy
	if type_changed:
		_destroy_ghost()
	# 立刻按当前鼠标位置拉起/更新幽灵（不必等下一次 MouseMotion）
	_poll_ghost_from_mouse()


func set_place_random(
	p_rotation: bool,
	p_scale_sym: bool,
	p_scale_z: bool,
	p_scale_xy: bool,
) -> void:
	random_rotation = p_rotation
	random_scale_sym = p_scale_sym
	random_scale_z = p_scale_z
	random_scale_xy = p_scale_xy
	_poll_ghost_from_mouse()


## —— 输入由 EditorInputRouter 调用 ——

func hover(screen_pos: Vector2) -> void:
	if not enabled or _painting or _dragging or _is_marquee_active():
		return
	if type_id.is_empty():
		_hide_ghost()
		return
	_last_hover_screen = screen_pos
	var hit: Vector3 = _ground_at(screen_pos)
	if hit == Vector3.INF:
		_hide_ghost()
		return
	var ws: float = Wc3Coords.WORLD_SCALE
	var wc3 := _snap_wc3_xy(Vector2(hit.x / ws, -hit.z / ws))
	_show_ghost_at(_wc3_to_world(wc3))


func stroke_press(screen_pos: Vector2) -> void:
	if not enabled or document == null:
		return
	# 无放置预览：点选 / 框选（对齐 WE 选择态）
	if type_id.is_empty():
		_painting = false
		_stroke_entries.clear()
		var picked: int = _pick_creation_number(screen_pos)
		if picked >= 0:
			if _cn_in_selection(picked):
				# 已在选区 → 整组多选拖动；primary 切到点中项
				if _selected_cn != picked:
					_selected_cn = picked
					selection_changed.emit(_selected_cn)
				_begin_drag(picked)
			else:
				select_creation_number(picked)
				_begin_drag(picked)
		else:
			# 空白：开始框选（单击未达阈值则释放时清空）
			if _marquee != null:
				_marquee.begin(screen_pos)
			else:
				clear_selection()
		return
	# 有预览：只放置
	_cancel_marquee()
	_painting = true
	_stroke_entries.clear()
	_last_place_wc3 = INVALID_POS
	_hide_ghost()
	_place_at_mouse(screen_pos)


func stroke_drag(screen_pos: Vector2) -> void:
	if not enabled:
		return
	if _is_marquee_active():
		_marquee.update(screen_pos)
		return
	if _dragging:
		_drag_to(screen_pos)
		return
	if not _painting:
		return
	_place_at_mouse(screen_pos)


func stroke_release() -> void:
	if _is_marquee_active():
		var rect: Rect2 = _marquee.finish()
		if rect.size.x >= 0.5 and rect.size.y >= 0.5:
			_select_in_screen_rect(rect)
		else:
			clear_selection()
		return
	if _dragging:
		_end_drag()
		return
	if not _painting:
		return
	_painting = false
	if _stroke_entries.is_empty():
		return
	if history != null:
		var cmd = DoodadEditCommandScript.make_add(_stroke_entries, "Place Doodad")
		history.record(cmd)
	placed.emit(_stroke_entries.size())
	_stroke_entries.clear()
	_request_rebuild()
	_poll_ghost_from_mouse()


func handle_key(k: InputEventKey) -> bool:
	if not enabled:
		return false
	var code: Key = k.keycode
	if code == KEY_NONE:
		code = k.physical_keycode
	match code:
		KEY_DELETE, KEY_BACKSPACE:
			return delete_selection()
		KEY_ESCAPE:
			# 对齐 WE：框选中 → 选中 → 放置预览
			if _is_marquee_active():
				_cancel_marquee()
				return true
			if _selected_cn >= 0 or _selected_cns.size() > 0 or _dragging:
				clear_selection()
				return true
			if not type_id.is_empty():
				clear_palette()
				return true
			return false
		KEY_BRACKETLEFT, KEY_COMMA:
			# 逗号作备选（部分布局 [ ] 不好按）
			nudge_facing(-ROTATE_STEP_DEG)
			return true
		KEY_BRACKETRIGHT, KEY_PERIOD:
			nudge_facing(ROTATE_STEP_DEG)
			return true
		KEY_R:
			# Shift+R = −45°；R = +45°
			nudge_facing(-ROTATE_STEP_DEG if k.shift_pressed else ROTATE_STEP_DEG)
			return true
	return false


func select_creation_number(cn: int) -> void:
	_selected_cns = PackedInt32Array()
	if cn >= 0:
		_selected_cns.append(cn)
	_selected_cn = cn
	_update_sel_markers()
	selection_changed.emit(_selected_cn)


func clear_selection() -> void:
	if _selected_cn < 0 and _selected_cns.is_empty() and not _dragging:
		_update_sel_markers()
		return
	_dragging = false
	_drag_befores.clear()
	_drag_anchor_cn = -1
	_selected_cn = -1
	_selected_cns = PackedInt32Array()
	_update_sel_markers()
	selection_changed.emit(-1)


## 清空笔刷类型与幽灵（Esc / 对齐 WE 取消预览）。
func clear_palette() -> void:
	type_id = ""
	variation = 0
	num_var = 1
	_destroy_ghost()
	palette_cleared.emit()


func delete_selection() -> bool:
	if document == null or _selected_cns.is_empty():
		return false
	var to_remove: PackedInt32Array = _selected_cns.duplicate()
	var removed_list: Array = []
	for cn in to_remove:
		var removed: Dictionary = document.remove_doodad_by_creation_number(cn)
		if removed.is_empty():
			continue
		removed_list.append(removed)
		_sync_present_remove(cn)
	if removed_list.is_empty():
		clear_selection()
		return false
	if history != null:
		history.record(DoodadEditCommandScript.make_remove(removed_list, "Delete Doodad"))
	clear_selection()
	deleted.emit(removed_list.size())
	_request_rebuild()
	return true


## 有选中则旋选中项；否则改笔刷朝向并发 facing_changed（Editor 同步 Inspect）。
func nudge_facing(delta_deg: float) -> void:
	if _selected_cns.size() > 0:
		if _rotate_selected(delta_deg):
			return
		# 选中已失效：清掉后改笔刷朝向
		clear_selection()
	angle_deg = fposmod(angle_deg + delta_deg, 360.0)
	facing_changed.emit(angle_deg)
	_refresh_ghost_facing()


## 将选中实例设为指定朝向（Inspect 朝向控件联动）。无选中则 no-op。
func apply_facing_to_selection(deg: float) -> void:
	if document == null or _selected_cns.is_empty():
		return
	var target: float = fposmod(deg, 360.0)
	var befores: Array = []
	var afters: Array = []
	for cn in _selected_cns:
		var before: Dictionary = _entry_by_cn(cn)
		if before.is_empty():
			continue
		var cur_deg: float = float(before.get("angleDegrees", rad_to_deg(float(before.get("angle", 0.0)))))
		if absf(fposmod(cur_deg - target + 180.0, 360.0) - 180.0) < 0.5:
			continue
		var after: Dictionary = before.duplicate(true)
		after["angleDegrees"] = target
		after["angle"] = deg_to_rad(target)
		document.update_doodad_by_creation_number(cn, after)
		_sync_present_entry(after)
		befores.append(before)
		afters.append(after)
	if befores.is_empty():
		return
	if history != null:
		history.record(DoodadEditCommandScript.make_modify(befores, afters, "Rotate Doodad"))
	_update_sel_markers()
	angle_deg = target
	_request_rebuild()


func get_selected_creation_number() -> int:
	return _selected_cn


func get_brush_facing() -> float:
	return angle_deg


# ---------------------------------------------------------------------------
# 放置
# ---------------------------------------------------------------------------

func _place_at_mouse(screen_pos: Vector2) -> void:
	var hit: Vector3 = _ground_at(screen_pos)
	if hit == Vector3.INF:
		return
	var ws: float = Wc3Coords.WORLD_SCALE
	var center_wc3 := _snap_wc3_xy(Vector2(hit.x / ws, -hit.z / ws))
	if _last_place_wc3 != INVALID_POS:
		var min_dist: float = document.tile_size() * PLACE_SPACING_TILES * 0.5
		if center_wc3.distance_to(_last_place_wc3) < min_dist:
			return
	_last_place_wc3 = center_wc3
	var offsets: Array[Vector2] = _shape_offsets_wc3()
	for off in offsets:
		_place_one(center_wc3.x + off.x, center_wc3.y + off.y)
	_throttle_rebuild()


func _place_one(wc3_x: float, wc3_y: float) -> void:
	if document == null or type_id.is_empty():
		return
	var var_i: int = variation
	if random_variation and num_var > 1:
		var_i = randi() % num_var
	var ang: float = _roll_place_angle_deg()
	var sc: Vector3 = _roll_place_scale_xyz()
	var entry: Dictionary = document.make_doodad_entry(
		type_id, wc3_x, wc3_y, var_i, ang, sc
	)
	document.add_doodad(entry)
	var stored: Dictionary = document.get_doodad(document.doodads.count() - 1)
	if stored.is_empty():
		return
	_stroke_entries.append(stored.duplicate(true))
	if map_loader != null:
		map_loader.add_doodad_instance(stored, document.as_build_dict())


func _roll_place_angle_deg() -> float:
	if random_rotation:
		return randf() * 360.0
	return angle_deg


## 返回 WC3 坐标系 scale（x/y=水平面，z=高度）。Godot 显示时再映射为 (x,z,y)。
func _roll_place_scale_xyz() -> Vector3:
	var base := place_scale
	var sx := base
	var sy := base
	var sz := base
	var want_rand := random_scale_sym or random_scale_z or random_scale_xy
	if not want_rand:
		return Vector3(sx, sy, sz)
	var min_s := base
	var max_s := base
	var allow := true
	if map_loader != null and map_loader.has_method("get_id_catalog"):
		var catalog: Wc3IdCatalog = map_loader.get_id_catalog()
		if catalog != null:
			var info: Dictionary = catalog.lookup(type_id)
			if not info.is_empty():
				allow = bool(info.get("can_place_rand_scale", true))
				min_s = float(info.get("min_scale", base))
				max_s = float(info.get("max_scale", base))
	if not allow:
		return Vector3(sx, sy, sz)
	if max_s < min_s:
		var tmp := min_s
		min_s = max_s
		max_s = tmp
	# 对称优先：三轴同一随机值（对齐 HiveWE random_scale）
	if random_scale_sym:
		var u: float = randf_range(min_s, max_s)
		return Vector3(u, u, u)
	if random_scale_xy:
		var h: float = randf_range(min_s, max_s)
		sx = h
		sy = h
	if random_scale_z:
		sz = randf_range(min_s, max_s)
	return Vector3(sx, sy, sz)


# ---------------------------------------------------------------------------
# 选中 / 拖动 / 旋转
# ---------------------------------------------------------------------------

func _begin_drag(cn: int) -> void:
	if _selected_cns.is_empty():
		return
	_dragging = true
	_drag_anchor_cn = cn if cn >= 0 else _selected_cn
	_drag_befores.clear()
	for sel_cn in _selected_cns:
		var entry: Dictionary = _entry_by_cn(sel_cn)
		if entry.is_empty():
			continue
		_drag_befores.append(entry.duplicate(true))
	if _drag_befores.is_empty():
		_dragging = false
		_drag_anchor_cn = -1


func _drag_to(screen_pos: Vector2) -> void:
	if document == null or _drag_befores.is_empty() or _drag_anchor_cn < 0:
		return
	var hit: Vector3 = _ground_at(screen_pos)
	if hit == Vector3.INF:
		return
	var ws: float = Wc3Coords.WORLD_SCALE
	var snapped := _snap_wc3_xy(Vector2(hit.x / ws, -hit.z / ws))
	var anchor_before: Dictionary = {}
	for b in _drag_befores:
		if int(b.get("creationNumber", -1)) == _drag_anchor_cn:
			anchor_before = b
			break
	if anchor_before.is_empty():
		return
	var ap: Dictionary = anchor_before.get("position", {})
	var delta := Vector2(
		snapped.x - float(ap.get("x", 0.0)),
		snapped.y - float(ap.get("y", 0.0)),
	)
	# 锚点已在目标吸附格则跳过（避免每帧脏写）
	var cur_anchor: Dictionary = _entry_by_cn(_drag_anchor_cn)
	var cap: Dictionary = cur_anchor.get("position", {})
	if (
		absf(float(cap.get("x", 0.0)) - snapped.x) < 0.01
		and absf(float(cap.get("y", 0.0)) - snapped.y) < 0.01
	):
		return
	for before in _drag_befores:
		var cn: int = int(before.get("creationNumber", -1))
		if cn < 0:
			continue
		var bp: Dictionary = before.get("position", {})
		var wc3_x: float = float(bp.get("x", 0.0)) + delta.x
		var wc3_y: float = float(bp.get("y", 0.0)) + delta.y
		var cur: Dictionary = before.duplicate(true)
		var pos: Dictionary = cur.get("position", {}).duplicate(true)
		pos["x"] = wc3_x
		pos["y"] = wc3_y
		if document.heightfield != null and document.heightfield.is_valid():
			pos["z"] = document.heightfield.interpolated_height(wc3_x, wc3_y)
		cur["position"] = pos
		document.update_doodad_by_creation_number(cn, cur)
		_sync_present_entry(cur)
	_update_sel_markers()


func _end_drag() -> void:
	_dragging = false
	if document == null or _drag_befores.is_empty():
		_drag_befores.clear()
		_drag_anchor_cn = -1
		return
	var befores: Array = []
	var afters: Array = []
	for before in _drag_befores:
		var cn: int = int(before.get("creationNumber", -1))
		var after: Dictionary = _entry_by_cn(cn)
		if after.is_empty():
			continue
		var bp: Dictionary = before.get("position", {})
		var ap: Dictionary = after.get("position", {})
		var moved: bool = (
			absf(float(bp.get("x", 0.0)) - float(ap.get("x", 0.0))) > 0.01
			or absf(float(bp.get("y", 0.0)) - float(ap.get("y", 0.0))) > 0.01
		)
		if not moved:
			continue
		befores.append(before)
		afters.append(after)
	if not befores.is_empty() and history != null:
		history.record(
			DoodadEditCommandScript.make_modify(befores, afters, "Move Doodad")
		)
	_drag_befores.clear()
	_drag_anchor_cn = -1
	_request_rebuild()


func _rotate_selected(delta_deg: float) -> bool:
	if document == null or _selected_cns.is_empty():
		return false
	var befores: Array = []
	var afters: Array = []
	var last_deg: float = angle_deg
	for cn in _selected_cns:
		var before: Dictionary = _entry_by_cn(cn)
		if before.is_empty():
			continue
		var after: Dictionary = before.duplicate(true)
		var deg: float = float(after.get("angleDegrees", rad_to_deg(float(after.get("angle", 0.0)))))
		deg = fposmod(deg + delta_deg, 360.0)
		after["angleDegrees"] = deg
		after["angle"] = deg_to_rad(deg)
		document.update_doodad_by_creation_number(cn, after)
		_sync_present_entry(after)
		befores.append(before)
		afters.append(after)
		if cn == _selected_cn:
			last_deg = deg
	if befores.is_empty():
		return false
	if history != null:
		history.record(DoodadEditCommandScript.make_modify(befores, afters, "Rotate Doodad"))
	_update_sel_markers()
	angle_deg = last_deg
	facing_changed.emit(angle_deg)
	_refresh_ghost_facing()
	_request_rebuild()
	return true


func _pick_creation_number(screen_pos: Vector2) -> int:
	if document == null or camera == null or document.doodads == null or document.doodads.count() == 0:
		return -1
	var best_cn: int = -1
	var best_d2: float = PICK_RADIUS_PX * PICK_RADIUS_PX
	for i in range(document.doodads.count()):
		var d: Dictionary = document.get_doodad(i)
		if d.is_empty():
			continue
		var pos: Dictionary = d.get("position", {})
		var gpos: Vector3 = _wc3_to_world(Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0))))
		if camera.is_position_behind(gpos):
			continue
		var sp: Vector2 = camera.unproject_position(gpos)
		var d2: float = sp.distance_squared_to(screen_pos)
		if d2 < best_d2:
			best_d2 = d2
			best_cn = int(d.get("creationNumber", -1))
	return best_cn


func _entry_by_cn(cn: int) -> Dictionary:
	if document == null:
		return {}
	var idx: int = document.find_doodad_index_by_creation_number(cn)
	if idx < 0:
		return {}
	return document.get_doodad(idx)


func _cn_in_selection(cn: int) -> bool:
	for c in _selected_cns:
		if c == cn:
			return true
	return false


func _set_selection(cns: PackedInt32Array) -> void:
	_selected_cns = cns
	_selected_cn = int(_selected_cns[0]) if _selected_cns.size() > 0 else -1
	_update_sel_markers()
	selection_changed.emit(_selected_cn)


func _select_in_screen_rect(rect: Rect2) -> void:
	var cns := PackedInt32Array()
	if document == null or camera == null or document.doodads == null:
		_set_selection(cns)
		return
	for i in range(document.doodads.count()):
		var d: Dictionary = document.get_doodad(i)
		if d.is_empty():
			continue
		var pos: Dictionary = d.get("position", {})
		var gpos: Vector3 = _wc3_to_world(Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0))))
		if MarqueeSelection.world_in_rect(camera, gpos, rect):
			var cn: int = int(d.get("creationNumber", -1))
			if cn >= 0:
				cns.append(cn)
	_set_selection(cns)


func _is_marquee_active() -> bool:
	return _marquee != null and _marquee.active


func _cancel_marquee() -> void:
	if _marquee != null and _marquee.active:
		_marquee.cancel()


# ---------------------------------------------------------------------------
# Present 同步
# ---------------------------------------------------------------------------

func _sync_present_entry(entry: Dictionary) -> void:
	if map_loader == null:
		return
	var cn: int = int(entry.get("creationNumber", -1))
	if map_loader.has_method("update_doodad_instance"):
		if map_loader.update_doodad_instance(entry, document.as_build_dict()):
			return
	# MultiMesh 组无法精确更新 → 全量
	if map_loader.has_method("rebuild_doodads_from_list"):
		map_loader.rebuild_doodads_from_list(document.as_build_dict(), document.doodad_entries())


func _sync_present_remove(cn: int) -> void:
	if map_loader == null:
		return
	if map_loader.has_method("remove_doodad_instance"):
		if map_loader.remove_doodad_instance(cn):
			return
	if map_loader.has_method("rebuild_doodads_from_list"):
		map_loader.rebuild_doodads_from_list(document.as_build_dict(), document.doodad_entries())


# ---------------------------------------------------------------------------
# 幽灵预览
# ---------------------------------------------------------------------------

func _poll_ghost_from_mouse() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	# 鼠标在其它浮动窗上时隐藏，避免幽灵钉在旧坐标
	var win := vp.get_window()
	if win != null:
		var mouse_g: Vector2i = DisplayServer.mouse_get_position()
		var wr := Rect2i(win.position, win.size)
		if not wr.has_point(mouse_g):
			_hide_ghost()
			return
	# 主视口上若正悬停控件（如底栏），不画幽灵
	var hovered: Control = vp.gui_get_hovered_control()
	if hovered != null:
		_hide_ghost()
		return
	hover(vp.get_mouse_position())


func _refresh_ghost_facing() -> void:
	if _ghost != null and is_instance_valid(_ghost) and _ghost.visible:
		_ghost.rotation.y = Wc3Coords.yaw_wc3_to_godot(deg_to_rad(angle_deg))
		return
	_poll_ghost_from_mouse()


func _show_ghost_at(world_pos: Vector3) -> void:
	_ensure_ghost()
	if _ghost == null:
		return
	_ghost.visible = true
	_ghost.global_position = world_pos
	_ghost.rotation.y = Wc3Coords.yaw_wc3_to_godot(deg_to_rad(angle_deg))
	var base: Vector3 = _ghost.get_meta("ghost_base_scale", Vector3.ONE)
	_ghost.scale = base * place_scale


func _hide_ghost() -> void:
	if _ghost != null:
		_ghost.visible = false


func _ensure_ghost() -> void:
	var var_i: int = variation
	if type_id == _ghost_type and var_i == _ghost_var and _ghost != null and is_instance_valid(_ghost):
		return
	_destroy_ghost()
	_ghost_type = type_id
	_ghost_var = var_i
	if type_id.is_empty() or map_loader == null:
		return
	var catalog: Wc3IdCatalog = map_loader.get_id_catalog() if map_loader.has_method("get_id_catalog") else null
	var cache: MapModelCache = map_loader.get_model_cache() if map_loader.has_method("get_model_cache") else null
	if catalog == null:
		return
	var info: Dictionary = catalog.lookup(type_id)
	var glb: String = catalog.converted_glb_path(type_id, var_i)
	var node: Node3D = null
	var base_scale := Vector3.ONE
	if not glb.is_empty() and cache != null:
		node = cache.instance_glb(glb)
		if node != null:
			base_scale = node.scale
			if cache.has_method("autoplay_stand"):
				cache.autoplay_stand(node, true)
	if node == null:
		if bool(info.get("use_click_helper", false)):
			node = Node3D.new()
			node.add_child(MapPlaceholders.make_click_helper(float(info.get("sel_size", 0.0))))
			node.add_child(MapPlaceholders.make_effect_particles())
			base_scale = Vector3.ONE
		else:
			node = MapPlaceholders.make_entity(type_id, -1, false)
			base_scale = node.scale * 0.8 * Wc3Coords.WORLD_SCALE
			node.scale = base_scale
	node.name = "DoodadGhost"
	node.set_meta("ghost_base_scale", base_scale)
	var has_mesh: bool = MapPlaceholders.node_has_mesh(node)
	if not glb.is_empty():
		_Pe2.attach_to(node, glb)
	MapPlaceholders.attach_editor_helpers(node, info, has_mesh)
	add_child(node)
	_apply_ghost_look(node)
	call_deferred("_apply_ghost_look", node)
	_ghost = node
	_ghost.visible = false


func _destroy_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_type = ""
	_ghost_var = -1


func _apply_ghost_look(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	var gis: Array[GeometryInstance3D] = []
	if root is GeometryInstance3D:
		gis.append(root as GeometryInstance3D)
	for c in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := c as GeometryInstance3D
		if gi != null:
			gis.append(gi)
	for gi in gis:
		# 保留 PE2 粒子观感，勿改成半透明 ghost 材质
		if gi is GPUParticles3D:
			continue
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 实例级淡出 + 材质 alpha（部分不透明材质会忽略前者）
		gi.transparency = clampf(1.0 - GHOST_ALPHA, 0.0, 1.0)
		_ghostify_geometry_materials(gi)


func _ghostify_geometry_materials(gi: GeometryInstance3D) -> void:
	if gi.material_override != null:
		gi.material_override = _as_ghost_material(gi.material_override)
		return
	if not (gi is MeshInstance3D):
		return
	var mi := gi as MeshInstance3D
	var mesh: Mesh = mi.mesh
	if mesh == null:
		return
	for si in range(mesh.get_surface_count()):
		var existing: Material = mi.get_surface_override_material(si)
		if existing == null:
			existing = mesh.surface_get_material(si)
		if existing != null:
			mi.set_surface_override_material(si, _as_ghost_material(existing))


func _as_ghost_material(src: Material) -> Material:
	if src == null:
		return null
	var m: Material = src.duplicate()
	if m is BaseMaterial3D:
		var bm := m as BaseMaterial3D
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c: Color = bm.albedo_color
		c.a = minf(c.a, GHOST_ALPHA)
		bm.albedo_color = c
	return m


# ---------------------------------------------------------------------------
# 选中标记（对齐 WE：贴地绿圈；直径来自 SLK selSize / pathTex 占地）
# ---------------------------------------------------------------------------

const SEL_RING_COLOR := Color(0.15, 1.0, 0.25, 1.0)
const SEL_RING_Y_BIAS := 0.04
const SEL_CIRCLE_TEX := "ReplaceableTextures/Selection/SelectionCircleMed.png"


func _make_sel_marker() -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = "DoodadSelMarker"
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 脱离父节点旋转，保证永远贴 XZ 地面（PlaneMesh 默认法线 +Y）
	marker.top_level = true
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	plane.orientation = PlaneMesh.FACE_Y
	marker.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = 20
	mat.albedo_color = SEL_RING_COLOR
	var tex: Texture2D = RuntimeAssets.load_converted_texture(SEL_CIRCLE_TEX)
	if tex != null:
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	marker.material_override = mat
	marker.visible = false
	add_child(marker)
	return marker


func _ensure_sel_markers(count: int) -> void:
	while _sel_markers.size() < count:
		_sel_markers.append(_make_sel_marker())
	for i in range(_sel_markers.size()):
		var m: MeshInstance3D = _sel_markers[i]
		if m == null or not is_instance_valid(m):
			_sel_markers[i] = _make_sel_marker()
			m = _sel_markers[i]
		# 热重载后可能仍是旧 Torus；强制换成贴地 Plane
		if not (m.mesh is PlaneMesh and m.top_level):
			m.queue_free()
			_sel_markers[i] = _make_sel_marker()
		if i >= count:
			_sel_markers[i].visible = false


## 直径来自配置：selSize → pathTex(NxN×32) → 默认 1 寻路格；再乘实例水平 scale。
func _sel_ring_diameter_world(entry: Dictionary) -> float:
	var diam_wc3 := Wc3Coords.PATHING_CELL
	var sid := str(entry.get("id", ""))
	if map_loader != null and map_loader.has_method("get_id_catalog"):
		var catalog: Wc3IdCatalog = map_loader.get_id_catalog()
		if catalog != null:
			var info: Dictionary = catalog.lookup(sid)
			if not info.is_empty():
				diam_wc3 = Wc3IdCatalog.selection_diameter_wc3(info)
	var scale_data: Dictionary = entry.get("scale", {})
	var sx: float = float(scale_data.get("x", 1.0))
	var sy: float = float(scale_data.get("y", 1.0))
	diam_wc3 *= maxf(maxf(sx, sy), 0.01)
	diam_wc3 = clampf(diam_wc3, Wc3Coords.PATHING_CELL * 0.5, Wc3Coords.TILE_SIZE * 24.0)
	return diam_wc3 * Wc3Coords.WORLD_SCALE


func _update_sel_markers() -> void:
	var n: int = _selected_cns.size()
	_ensure_sel_markers(n)
	for i in range(n):
		var marker: MeshInstance3D = _sel_markers[i]
		var entry: Dictionary = _entry_by_cn(_selected_cns[i])
		if entry.is_empty():
			marker.visible = false
			continue
		var pos: Dictionary = entry.get("position", {})
		var world := _wc3_to_world(Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0))))
		world.y += SEL_RING_Y_BIAS
		# top_level：用全局变换钉死贴地，不受 DoodadBrush 父节点影响
		marker.global_transform = Transform3D(Basis.IDENTITY, world)
		var diam: float = _sel_ring_diameter_world(entry)
		var plane := marker.mesh as PlaneMesh
		if plane == null:
			plane = PlaneMesh.new()
			plane.orientation = PlaneMesh.FACE_Y
			marker.mesh = plane
		plane.size = Vector2(diam, diam)
		marker.visible = true
	for i in range(n, _sel_markers.size()):
		_sel_markers[i].visible = false


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

## 网格吸附（对齐 HiveWE 有 pathing：半格）。现阶段一律吸附，无自由放置。
func _snap_wc3_xy(wc3: Vector2) -> Vector2:
	var ts: float = document.tile_size() if document != null else Wc3Coords.TILE_SIZE
	var co: Vector2 = document.center_offset() if document != null else Vector2.ZERO
	if ts <= 0.0:
		return wc3
	var step: float = ts * SNAP_TILE_FRAC
	var local := wc3 - co
	local.x = roundf(local.x / step) * step
	local.y = roundf(local.y / step) * step
	return local + co


func _wc3_to_world(wc3: Vector2) -> Vector3:
	## 与 MapDoodadLayer._apply_doodad_xform 同一套坐标，保证幽灵=落笔。
	var z: float = 0.0
	if document != null and document.heightfield != null and document.heightfield.is_valid():
		z = document.heightfield.interpolated_height(wc3.x, wc3.y)
	var local := Wc3Coords.wc3_xy_to_godot(wc3.x, wc3.y, z)
	# 幽灵挂在 DoodadBrush 下；实例在 MapRoot 下——若 MapRoot 有位移则转成全局
	if map_loader != null and map_loader is Node3D:
		return (map_loader as Node3D).to_global(local)
	return local


func _ground_at(screen_pos: Vector2) -> Vector3:
	var hit: Vector3 = _raycast_ground(screen_pos)
	if hit == Vector3.INF:
		hit = _ray_plane_fallback(screen_pos)
	return hit


func _shape_offsets_wc3() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var ts: float = document.tile_size() if document != null else Wc3Coords.TILE_SIZE
	var radius: int = maxi(brush_size - 1, 0)
	if radius <= 0:
		out.append(Vector2.ZERO)
		return out
	var r2: int = radius * radius
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if brush_shape == 0:
				if dx * dx + dy * dy > r2:
					continue
			out.append(Vector2(float(dx) * ts, float(dy) * ts))
	if out.is_empty():
		out.append(Vector2.ZERO)
	return out


func _sanitize_brush_size(size: int) -> int:
	const SIZES := [1, 2, 3, 5, 8]
	if SIZES.has(size):
		return size
	return 1


func _throttle_rebuild() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_rebuild_ms < REBUILD_INTERVAL_MS:
		return
	_last_rebuild_ms = now
	rebuild_requested.emit()


func _request_rebuild() -> void:
	_last_rebuild_ms = Time.get_ticks_msec()
	rebuild_requested.emit()


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	if camera == null or space == null:
		return Vector3.INF
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 5000.0)
	var result: Dictionary = space.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return Vector3.INF
	return result.position


func _ray_plane_fallback(screen_pos: Vector2) -> Vector3:
	if camera == null or document == null or document.is_empty():
		return Vector3.INF
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 1e-6:
		return Vector3.INF
	var y0: float = 0.0
	if document.heightfield != null:
		y0 = (
			float(document.heightfield.heights[0]) * Wc3Coords.WORLD_SCALE
			if document.heightfield.heights.size() > 0
			else 0.0
		)
	var t: float = (y0 - from.y) / dir.y
	if t < 0.0:
		return Vector3.INF
	return from + dir * t
