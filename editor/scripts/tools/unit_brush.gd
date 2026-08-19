extends Node3D
## 单位笔刷：幽灵预览 + LMB 放置；点选 / 框选 / 多选拖动 / Delete / [ ] 旋转。
## 对齐 doodad_brush；单点放置（无笔刷形状），带队伍色；放置不做格子吸附。


signal rebuild_requested
signal placed(count: int)
signal selection_changed(creation_number: int)
signal deleted(count: int)
signal facing_changed(angle_deg: float)
signal palette_cleared
signal properties_requested(creation_number: int)

const UnitEditCommandScript := preload("res://editor/scripts/commands/unit_edit_command.gd")

const PLACE_SPACING_TILES := 0.5
const INVALID_POS := Vector2(1e20, 1e20)
const PICK_RADIUS_PX := 28.0
const GHOST_ALPHA := 0.45
const GHOST_INVALID_COLOR := Color(1.0, 0.2, 0.2, 0.5)
const ROTATE_STEP_DEG := 45.0
const SEL_RING_COLOR := Color(0.15, 1.0, 0.25, 1.0)
const SEL_RING_Y_BIAS := 0.04
const SEL_CIRCLE_TEX := "ReplaceableTextures/Selection/SelectionCircleMed.png"

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
			clear_selection()
			_hide_ghost()
			_cancel_marquee()
		set_process(_enabled)

var type_id: String = ""
var owner_id: int = 0
var angle_deg: float = 270.0
var random_rotation: bool = true

var _painting: bool = false
var _stroke_entries: Array = []
var _last_place_wc3: Vector2 = INVALID_POS

## 选中：_selected_cn 为 primary（Inspect / selection_changed）；_selected_cns 为多选全集
var _selected_cn: int = -1
var _selected_cns: PackedInt32Array = PackedInt32Array()
var _dragging: bool = false
var _drag_befores: Array = []
var _drag_anchor_cn: int = -1
var _sel_markers: Array[MeshInstance3D] = []

var _marquee: MarqueeSelection = null
var _marqueeing: bool = false

var _ghost: Node3D = null
var _ghost_type: String = ""
var _ghost_owner: int = -1
var _ghost_placement_ok: bool = true
var _ghost_tint_dirty: bool = true


func setup(doc, cam: Camera3D, world: World3D, p_history: EditorCommandHistory = null, loader: MapLoader = null) -> void:
	document = doc
	camera = cam
	space = world
	history = p_history
	map_loader = loader
	set_process(_enabled)


func set_marquee(m: MarqueeSelection) -> void:
	_marquee = m


func set_random_rotation(on: bool) -> void:
	random_rotation = on


func _process(_delta: float) -> void:
	if not _enabled or type_id.is_empty() or _painting or _dragging or _marqueeing:
		return
	_poll_ghost_from_mouse()


func set_palette(p_type_id: String, p_owner_id: int, p_angle_deg: float) -> void:
	var new_type := p_type_id.strip_edges()
	var new_owner := clampi(p_owner_id, 0, 15)
	var type_changed := type_id != new_type or owner_id != new_owner
	type_id = new_type
	owner_id = new_owner
	angle_deg = p_angle_deg
	if type_changed:
		_destroy_ghost()
	_poll_ghost_from_mouse()


func hover(screen_pos: Vector2) -> void:
	if not enabled or _painting or _dragging or _marqueeing:
		return
	if type_id.is_empty():
		_hide_ghost()
		return
	var hit: Vector3 = _ground_at(screen_pos)
	if hit == Vector3.INF:
		_hide_ghost()
		return
	var ws: float = Wc3Coords.WORLD_SCALE
	var wc3 := Vector2(hit.x / ws, -hit.z / ws)
	var ok: bool = _can_place_at(wc3.x, wc3.y)
	_show_ghost_at(_wc3_to_world(wc3))
	_set_ghost_placement_ok(ok)


func stroke_press(screen_pos: Vector2) -> void:
	if not enabled or document == null:
		return
	if type_id.is_empty():
		_painting = false
		_stroke_entries.clear()
		var picked: int = _pick_creation_number(screen_pos)
		if picked >= 0:
			_cancel_marquee()
			if _is_cn_selected(picked):
				# 点在已多选集合内 → 整组拖动
				_begin_drag(picked)
			else:
				select_creation_number(picked)
				_begin_drag(picked)
		else:
			# 空白：开始框选；清掉单击拖动态
			_dragging = false
			_drag_befores.clear()
			_drag_anchor_cn = -1
			_marqueeing = true
			if _marquee != null:
				_marquee.begin(screen_pos)
		return
	_painting = true
	_stroke_entries.clear()
	_last_place_wc3 = INVALID_POS
	_hide_ghost()
	_place_at_mouse(screen_pos)


## 双击已放置单位 → 打开属性面板（由 Editor 接 properties_requested）。
func handle_double_click(screen_pos: Vector2) -> void:
	if not enabled or document == null:
		return
	var picked: int = _pick_creation_number(screen_pos)
	if picked < 0:
		return
	select_creation_number(picked)
	_dragging = false
	_drag_befores.clear()
	_drag_anchor_cn = -1
	_cancel_marquee()
	properties_requested.emit(picked)


func stroke_drag(screen_pos: Vector2) -> void:
	if not enabled:
		return
	if _marqueeing:
		if _marquee != null:
			_marquee.update(screen_pos)
		return
	if _dragging:
		_drag_to(screen_pos)
		return
	if not _painting:
		return
	_place_at_mouse(screen_pos)


func stroke_release() -> void:
	if _marqueeing:
		_marqueeing = false
		var rect := Rect2()
		if _marquee != null:
			rect = _marquee.finish()
		if rect.size.x >= 0.5 and rect.size.y >= 0.5:
			_select_units_in_rect(rect)
		else:
			# 未越过阈值 = 空白单击 → 清空选中
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
		history.record(UnitEditCommandScript.make_add(_stroke_entries, "Place Unit"))
	placed.emit(_stroke_entries.size())
	_stroke_entries.clear()
	rebuild_requested.emit()
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
			if _marqueeing:
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
			nudge_facing(-ROTATE_STEP_DEG)
			return true
		KEY_BRACKETRIGHT, KEY_PERIOD:
			nudge_facing(ROTATE_STEP_DEG)
			return true
		KEY_R:
			nudge_facing(-ROTATE_STEP_DEG if k.shift_pressed else ROTATE_STEP_DEG)
			return true
	return false


func select_creation_number(cn: int) -> void:
	_set_selection(PackedInt32Array([cn]) if cn >= 0 else PackedInt32Array(), cn)


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


func clear_palette() -> void:
	type_id = ""
	_destroy_ghost()
	palette_cleared.emit()


func delete_selection() -> bool:
	if document == null or _selected_cns.is_empty():
		return false
	var to_remove: PackedInt32Array = _selected_cns.duplicate()
	var removed: Array = []
	for cn in to_remove:
		var entry: Dictionary = document.remove_unit_by_creation_number(cn)
		if entry.is_empty():
			continue
		removed.append(entry)
		_sync_present_remove(cn)
	if removed.is_empty():
		clear_selection()
		return false
	if history != null:
		history.record(UnitEditCommandScript.make_remove(removed, "Delete Unit"))
	clear_selection()
	deleted.emit(removed.size())
	rebuild_requested.emit()
	return true


func nudge_facing(delta_deg: float) -> void:
	if _selected_cns.size() > 0:
		if _rotate_selected(delta_deg):
			return
		clear_selection()
	angle_deg = fposmod(angle_deg + delta_deg, 360.0)
	facing_changed.emit(angle_deg)
	_refresh_ghost_facing()


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
		document.update_unit_by_creation_number(cn, after)
		_sync_present_entry(after)
		befores.append(before)
		afters.append(after)
	if befores.is_empty():
		return
	if history != null:
		history.record(UnitEditCommandScript.make_modify(befores, afters, "Rotate Unit"))
	_update_sel_markers()
	angle_deg = target
	rebuild_requested.emit()


func get_selected_creation_number() -> int:
	return _selected_cn


func get_brush_facing() -> float:
	return angle_deg


func _place_at_mouse(screen_pos: Vector2) -> void:
	var hit: Vector3 = _ground_at(screen_pos)
	if hit == Vector3.INF:
		return
	var ws: float = Wc3Coords.WORLD_SCALE
	var center_wc3 := Vector2(hit.x / ws, -hit.z / ws)
	if _last_place_wc3 != INVALID_POS:
		var min_dist: float = document.tile_size() * PLACE_SPACING_TILES * 0.5
		if center_wc3.distance_to(_last_place_wc3) < min_dist:
			return
	if not _can_place_at(center_wc3.x, center_wc3.y):
		return
	_last_place_wc3 = center_wc3
	_place_one(center_wc3.x, center_wc3.y)


func _place_one(wc3_x: float, wc3_y: float) -> void:
	if document == null or type_id.is_empty():
		return
	if not _can_place_at(wc3_x, wc3_y):
		return
	var place_angle: float = randf() * 360.0 if random_rotation else angle_deg
	var entry: Dictionary = document.make_unit_entry(type_id, wc3_x, wc3_y, owner_id, place_angle, 0)
	document.add_unit(entry)
	var stored: Dictionary = document.get_unit(document.units.count() - 1)
	if stored.is_empty():
		return
	_stroke_entries.append(stored.duplicate(true))
	if map_loader != null:
		map_loader.add_unit_instance(stored, document.as_build_dict())


func _can_place_at(wc3_x: float, wc3_y: float, ignore_cn: int = -1) -> bool:
	if document == null or type_id.is_empty():
		return false
	var catalog: Wc3IdCatalog = null
	if map_loader != null and map_loader.has_method("get_id_catalog"):
		catalog = map_loader.get_id_catalog()
	var pathing: Wc3PathingMap = null
	if document.pathing != null:
		pathing = document.pathing
	elif map_loader != null and map_loader.has_method("get_pathing_map"):
		pathing = map_loader.get_pathing_map()
	var entries: Array = document.unit_entries()
	return UnitPlacementRules.can_place(wc3_x, wc3_y, type_id, catalog, pathing, entries, ignore_cn)


func _begin_drag(cn: int) -> void:
	_drag_befores.clear()
	_drag_anchor_cn = cn
	for sel_cn in _selected_cns:
		var entry: Dictionary = _entry_by_cn(sel_cn)
		if entry.is_empty():
			continue
		_drag_befores.append(entry.duplicate(true))
	if _drag_befores.is_empty():
		_drag_anchor_cn = -1
		return
	_dragging = true


func _drag_to(screen_pos: Vector2) -> void:
	if document == null or _drag_befores.is_empty():
		return
	var hit: Vector3 = _ground_at(screen_pos)
	if hit == Vector3.INF:
		return
	var ws: float = Wc3Coords.WORLD_SCALE
	var mouse_wc3 := Vector2(hit.x / ws, -hit.z / ws)
	var anchor_pos := Vector2.ZERO
	var found_anchor := false
	for before in _drag_befores:
		if typeof(before) != TYPE_DICTIONARY:
			continue
		var bd: Dictionary = before
		if int(bd.get("creationNumber", -1)) == _drag_anchor_cn:
			var ap: Dictionary = bd.get("position", {})
			anchor_pos = Vector2(float(ap.get("x", 0.0)), float(ap.get("y", 0.0)))
			found_anchor = true
			break
	if not found_anchor:
		var first: Dictionary = _drag_befores[0]
		var fp: Dictionary = first.get("position", {})
		anchor_pos = Vector2(float(fp.get("x", 0.0)), float(fp.get("y", 0.0)))
	var delta := mouse_wc3 - anchor_pos
	# 先校验整组目标位置；任一非法则本帧不移动
	var catalog: Wc3IdCatalog = null
	if map_loader != null and map_loader.has_method("get_id_catalog"):
		catalog = map_loader.get_id_catalog()
	var pathing: Wc3PathingMap = null
	if document.pathing != null:
		pathing = document.pathing
	elif map_loader != null and map_loader.has_method("get_pathing_map"):
		pathing = map_loader.get_pathing_map()
	var entries: Array = document.unit_entries()
	for before in _drag_befores:
		if typeof(before) != TYPE_DICTIONARY:
			continue
		var b0: Dictionary = before
		var tid := str(b0.get("typeId", ""))
		var bp0: Dictionary = b0.get("position", {})
		var tx: float = float(bp0.get("x", 0.0)) + delta.x
		var ty: float = float(bp0.get("y", 0.0)) + delta.y
		if not UnitPlacementRules.can_place(tx, ty, tid, catalog, pathing, entries, -1, _selected_cns):
			return
	for before in _drag_befores:
		if typeof(before) != TYPE_DICTIONARY:
			continue
		var b: Dictionary = before
		var cn: int = int(b.get("creationNumber", -1))
		if cn < 0:
			continue
		var bp: Dictionary = b.get("position", {})
		var nx: float = float(bp.get("x", 0.0)) + delta.x
		var ny: float = float(bp.get("y", 0.0)) + delta.y
		var cur: Dictionary = b.duplicate(true)
		var pos: Dictionary = cur.get("position", {}).duplicate(true)
		if (
			absf(float(pos.get("x", 0.0)) - nx) < 0.01
			and absf(float(pos.get("y", 0.0)) - ny) < 0.01
		):
			continue
		pos["x"] = nx
		pos["y"] = ny
		if document.heightfield != null and document.heightfield.is_valid():
			pos["z"] = document.heightfield.interpolated_height(nx, ny)
		cur["position"] = pos
		document.update_unit_by_creation_number(cn, cur)
		_sync_present_entry(cur)
	_update_sel_markers()


func _end_drag() -> void:
	_dragging = false
	if document == null or _drag_befores.is_empty():
		_drag_befores.clear()
		_drag_anchor_cn = -1
		return
	var afters: Array = []
	var moved := false
	for before in _drag_befores:
		if typeof(before) != TYPE_DICTIONARY:
			continue
		var b: Dictionary = before
		var cn: int = int(b.get("creationNumber", -1))
		var after: Dictionary = _entry_by_cn(cn)
		if after.is_empty():
			continue
		afters.append(after)
		var bp: Dictionary = b.get("position", {})
		var ap: Dictionary = after.get("position", {})
		if (
			absf(float(bp.get("x", 0.0)) - float(ap.get("x", 0.0))) > 0.01
			or absf(float(bp.get("y", 0.0)) - float(ap.get("y", 0.0))) > 0.01
		):
			moved = true
	if moved and history != null and afters.size() == _drag_befores.size():
		history.record(UnitEditCommandScript.make_modify(_drag_befores, afters, "Move Unit"))
	_drag_befores.clear()
	_drag_anchor_cn = -1
	if moved:
		rebuild_requested.emit()


func _rotate_selected(delta_deg: float) -> bool:
	if document == null or _selected_cns.is_empty():
		return false
	var befores: Array = []
	var afters: Array = []
	var primary_deg: float = angle_deg
	for cn in _selected_cns:
		var before: Dictionary = _entry_by_cn(cn)
		if before.is_empty():
			continue
		var after: Dictionary = before.duplicate(true)
		var deg: float = float(after.get("angleDegrees", rad_to_deg(float(after.get("angle", 0.0)))))
		deg = fposmod(deg + delta_deg, 360.0)
		after["angleDegrees"] = deg
		after["angle"] = deg_to_rad(deg)
		document.update_unit_by_creation_number(cn, after)
		_sync_present_entry(after)
		befores.append(before)
		afters.append(after)
		if cn == _selected_cn:
			primary_deg = deg
	if befores.is_empty():
		return false
	if history != null:
		history.record(UnitEditCommandScript.make_modify(befores, afters, "Rotate Unit"))
	_update_sel_markers()
	angle_deg = primary_deg
	facing_changed.emit(angle_deg)
	_refresh_ghost_facing()
	rebuild_requested.emit()
	return true


func _pick_creation_number(screen_pos: Vector2) -> int:
	if document == null or camera == null or document.units == null or document.units.count() == 0:
		return -1
	var best_cn: int = -1
	var best_d2: float = PICK_RADIUS_PX * PICK_RADIUS_PX
	for i in range(document.units.count()):
		var d: Dictionary = document.get_unit(i)
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


func _select_units_in_rect(rect: Rect2) -> void:
	if document == null or camera == null or document.units == null:
		_set_selection(PackedInt32Array(), -1)
		return
	var cns := PackedInt32Array()
	for i in range(document.units.count()):
		var d: Dictionary = document.get_unit(i)
		if d.is_empty():
			continue
		var pos: Dictionary = d.get("position", {})
		var gpos: Vector3 = _wc3_to_world(Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0))))
		if MarqueeSelection.world_in_rect(camera, gpos, rect):
			cns.append(int(d.get("creationNumber", -1)))
	_set_selection(cns, cns[0] if cns.size() > 0 else -1)


func _set_selection(cns: PackedInt32Array, primary: int = -1) -> void:
	_selected_cns = PackedInt32Array()
	for cn in cns:
		if cn >= 0:
			_selected_cns.append(cn)
	if primary >= 0 and _is_cn_selected(primary):
		_selected_cn = primary
	elif _selected_cns.size() > 0:
		_selected_cn = _selected_cns[_selected_cns.size() - 1]
	else:
		_selected_cn = -1
	_update_sel_markers()
	selection_changed.emit(_selected_cn)


func _is_cn_selected(cn: int) -> bool:
	for sel in _selected_cns:
		if sel == cn:
			return true
	return false


func _cancel_marquee() -> void:
	_marqueeing = false
	if _marquee != null and _marquee.active:
		_marquee.cancel()


func _entry_by_cn(cn: int) -> Dictionary:
	if document == null:
		return {}
	var idx: int = document.find_unit_index_by_creation_number(cn)
	if idx < 0:
		return {}
	return document.get_unit(idx)


func _sync_present_entry(entry: Dictionary) -> void:
	if map_loader == null:
		return
	if map_loader.has_method("update_unit_instance"):
		if map_loader.update_unit_instance(entry, document.as_build_dict()):
			return
	if map_loader.has_method("rebuild_units_from_list"):
		map_loader.rebuild_units_from_list(document.as_build_dict(), document.unit_entries())


func _sync_present_remove(cn: int) -> void:
	if map_loader == null:
		return
	if map_loader.has_method("remove_unit_instance"):
		if map_loader.remove_unit_instance(cn):
			return
	if map_loader.has_method("rebuild_units_from_list"):
		map_loader.rebuild_units_from_list(document.as_build_dict(), document.unit_entries())


func _poll_ghost_from_mouse() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var win := vp.get_window()
	if win != null:
		var mouse_g: Vector2i = DisplayServer.mouse_get_position()
		var wr := Rect2i(win.position, win.size)
		if not wr.has_point(mouse_g):
			_hide_ghost()
			return
	var hovered: Control = vp.gui_get_hovered_control()
	if hovered != null:
		_hide_ghost()
		return
	hover(vp.get_mouse_position())


func _refresh_ghost_facing() -> void:
	if _ghost != null and is_instance_valid(_ghost) and _ghost.visible:
		_ghost.rotation.y = Wc3Coords.yaw_wc3_unit_to_godot(deg_to_rad(angle_deg))
		return
	_poll_ghost_from_mouse()


func _show_ghost_at(world_pos: Vector3) -> void:
	_ensure_ghost()
	if _ghost == null:
		return
	_ghost.visible = true
	_ghost.global_position = world_pos
	_ghost.rotation.y = Wc3Coords.yaw_wc3_unit_to_godot(deg_to_rad(angle_deg))


func _hide_ghost() -> void:
	if _ghost != null:
		_ghost.visible = false


func _set_ghost_placement_ok(ok: bool) -> void:
	if _ghost_placement_ok == ok and not _ghost_tint_dirty:
		return
	_ghost_placement_ok = ok
	_ghost_tint_dirty = false
	if _ghost != null and is_instance_valid(_ghost):
		_apply_ghost_tint(_ghost)


func _ensure_ghost() -> void:
	if (
		type_id == _ghost_type
		and owner_id == _ghost_owner
		and _ghost != null
		and is_instance_valid(_ghost)
	):
		return
	_destroy_ghost()
	_ghost_type = type_id
	_ghost_owner = owner_id
	if type_id.is_empty() or map_loader == null:
		return
	var catalog: Wc3IdCatalog = map_loader.get_id_catalog() if map_loader.has_method("get_id_catalog") else null
	var cache: MapModelCache = map_loader.get_model_cache() if map_loader.has_method("get_model_cache") else null
	if catalog == null:
		return
	var glb: String = catalog.converted_glb_path(type_id, 0)
	var node: Node3D = null
	if not glb.is_empty() and cache != null:
		node = cache.instance_glb_preview(glb) if cache.has_method("instance_glb_preview") else cache.instance_glb(glb)
		if node != null:
			if cache.has_method("autoplay_stand"):
				cache.autoplay_stand(node, true)
			cache.apply_team_color(
				node,
				MapUnitLayer.resolve_team_color_index(type_id, owner_id),
				false
			)
	if node == null:
		node = MapPlaceholders.make_entity(type_id, owner_id, true)
	node.name = "UnitGhost"
	add_child(node)
	_ghost_placement_ok = true
	_ghost_tint_dirty = true
	_apply_ghost_look(node)
	call_deferred("_apply_ghost_look", node)
	_ghost = node
	_ghost.visible = false


func _destroy_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_type = ""
	_ghost_owner = -1
	_ghost_placement_ok = true
	_ghost_tint_dirty = true


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
		if gi is GPUParticles3D:
			continue
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.transparency = clampf(1.0 - GHOST_ALPHA, 0.0, 1.0)
		if gi.material_override != null:
			if gi.material_override is BaseMaterial3D and (gi.material_override as BaseMaterial3D).has_meta("_ghost_base_albedo"):
				pass
			else:
				gi.material_override = _as_ghost_material(gi.material_override)
			continue
		if not (gi is MeshInstance3D):
			continue
		var mi := gi as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for si in range(mesh.get_surface_count()):
			var existing: Material = mi.get_surface_override_material(si)
			if existing is BaseMaterial3D and (existing as BaseMaterial3D).has_meta("_ghost_base_albedo"):
				continue
			if existing == null:
				existing = mesh.surface_get_material(si)
			if existing != null:
				mi.set_surface_override_material(si, _as_ghost_material(existing))
	_apply_ghost_tint(root)
	_ghost_tint_dirty = false


func _as_ghost_material(src: Material) -> Material:
	if src == null:
		return null
	if src is BaseMaterial3D and (src as BaseMaterial3D).has_meta("_ghost_base_albedo"):
		return src
	var m: Material = src.duplicate()
	if m is BaseMaterial3D:
		var bm := m as BaseMaterial3D
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c: Color = bm.albedo_color
		c.a = minf(c.a, GHOST_ALPHA)
		bm.albedo_color = c
		bm.set_meta("_ghost_base_albedo", c)
	return m


func _apply_ghost_tint(root: Node) -> void:
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
		if gi is GPUParticles3D:
			continue
		if gi.material_override is BaseMaterial3D:
			_tint_ghost_material(gi.material_override as BaseMaterial3D)
		if not (gi is MeshInstance3D):
			continue
		var mi := gi as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for si in range(mesh.get_surface_count()):
			var ov: Material = mi.get_surface_override_material(si)
			if ov is BaseMaterial3D:
				_tint_ghost_material(ov as BaseMaterial3D)


func _tint_ghost_material(bm: BaseMaterial3D) -> void:
	if bm == null:
		return
	if _ghost_placement_ok:
		var base: Color = bm.get_meta("_ghost_base_albedo", bm.albedo_color) as Color
		base.a = minf(base.a, GHOST_ALPHA)
		bm.albedo_color = base
	else:
		bm.albedo_color = GHOST_INVALID_COLOR


func _make_sel_marker() -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = "UnitSelMarker"
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


func _sel_ring_diameter_world(entry: Dictionary) -> float:
	var sid := str(entry.get("typeId", ""))
	var info: Dictionary = {}
	if map_loader != null and map_loader.has_method("get_id_catalog"):
		var catalog: Wc3IdCatalog = map_loader.get_id_catalog()
		if catalog != null:
			info = catalog.lookup(sid)
	# 建筑 / 有 pathTex：用配置脚印（已与绿圈对齐）
	var cells: Vector2i = Wc3IdCatalog.parse_path_tex_cells(str(info.get("path_tex", "")))
	var use_config_footprint: bool = (
		cells != Vector2i.ZERO or bool(info.get("is_building", false)) or bool(info.get("is_start_location", false))
	)
	if not use_config_footprint:
		# 普通单位：对齐 HiveWE — 用模型水平包围盒当选框直径
		var cn := int(entry.get("creationNumber", -1))
		if map_loader != null and cn >= 0 and map_loader.has_method("find_unit_node"):
			var node: Node3D = map_loader.find_unit_node(cn)
			if node != null and is_instance_valid(node) and not bool(node.get_meta("is_placeholder", false)):
				var from_mesh: float = _mesh_selection_diameter_world(node)
				if from_mesh > 0.08:
					return clampf(from_mesh, Wc3Coords.PATHING_CELL * Wc3Coords.WORLD_SCALE * 0.5, Wc3Coords.TILE_SIZE * 24.0 * Wc3Coords.WORLD_SCALE)
	var diam_wc3: float = Wc3IdCatalog.selection_diameter_wc3(info) if not info.is_empty() else Wc3Coords.PATHING_CELL
	diam_wc3 = clampf(diam_wc3, Wc3Coords.PATHING_CELL * 0.5, Wc3Coords.TILE_SIZE * 24.0)
	return diam_wc3 * Wc3Coords.WORLD_SCALE


## HiveWE：selection_scale = mdx.bounds_radius / 128；此处用实例水平 AABB。
func _mesh_selection_diameter_world(node: Node3D) -> float:
	var aabb := AABB()
	var first := true
	for c in node.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if vi == null or not vi.visible:
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
		return 0.0
	return maxf(aabb.size.x, aabb.size.z)


func _update_sel_markers() -> void:
	var n: int = _selected_cns.size()
	_ensure_sel_markers(n)
	for i in range(_sel_markers.size()):
		var marker: MeshInstance3D = _sel_markers[i]
		if marker == null or not is_instance_valid(marker):
			continue
		if i >= n:
			marker.visible = false
			continue
		var entry: Dictionary = _entry_by_cn(_selected_cns[i])
		if entry.is_empty():
			marker.visible = false
			continue
		var pos: Dictionary = entry.get("position", {})
		var world := _wc3_to_world(Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0))))
		world.y += SEL_RING_Y_BIAS
		marker.global_transform = Transform3D(Basis.IDENTITY, world)
		var diam: float = _sel_ring_diameter_world(entry)
		var plane := marker.mesh as PlaneMesh
		if plane == null:
			plane = PlaneMesh.new()
			plane.orientation = PlaneMesh.FACE_Y
			marker.mesh = plane
		plane.size = Vector2(diam, diam)
		marker.visible = true


func _wc3_to_world(wc3: Vector2) -> Vector3:
	var z: float = 0.0
	if document != null and document.heightfield != null and document.heightfield.is_valid():
		z = document.heightfield.interpolated_height(wc3.x, wc3.y)
	var local := Wc3Coords.wc3_xy_to_godot(wc3.x, wc3.y, z)
	if map_loader != null and map_loader is Node3D:
		return (map_loader as Node3D).to_global(local)
	return local


func _ground_at(screen_pos: Vector2) -> Vector3:
	var hit: Vector3 = _raycast_ground(screen_pos)
	if hit == Vector3.INF:
		hit = _ray_plane_fallback(screen_pos)
	return hit


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	if camera == null or space == null:
		return Vector3.INF
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var to: Vector3 = from + dir * 20000.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0xFFFFFFFF
	var hit: Dictionary = space.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	return hit.get("position", Vector3.INF)


func _ray_plane_fallback(screen_pos: Vector2) -> Vector3:
	if camera == null:
		return Vector3.INF
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 1e-5:
		return Vector3.INF
	var t: float = -from.y / dir.y
	if t < 0.0:
		return Vector3.INF
	return from + dir * t
