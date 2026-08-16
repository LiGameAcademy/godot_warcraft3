extends Node3D
## 地表笔刷：吸附中级栅格顶点（tilepoint）；悬停绿框以该顶点为中心、边长=1 格（对齐经典 WE）。


signal tile_hovered(tile: Vector2i) ## 实为顶点坐标 (ix, iy)
signal painted
signal rebuild_requested
signal ramp_feedback(message: String)
signal brush_settings_changed(size: int, shape: int)

const REBUILD_INTERVAL_MS := 80
## 略抬高，避免与地面 z-fight（Godot 单位）
const HOVER_LIFT := 0.015
const HOVER_COLOR := Color(0.18, 0.92, 0.28, 0.42)
const HOVER_EDGE := Color(0.35, 1.0, 0.45, 0.85)
## Ramp spine preview：调 peek_spine_at 算出的落旗点集（3 点直坡 / L 补心 / 对角 3×3）。
## 绿偏青，区别于地表笔刷的纯绿（HivEWE 经典 Ramp 工具风格）。
const RAMP_SPINE_COLOR := Color(0.20, 0.90, 0.55, 0.45)
const RAMP_SPINE_EDGE := Color(0.40, 1.0, 0.65, 0.95)
## Ramp 落坡会失败（plan_fail）时画红框单格，提示"点这无效"。
const RAMP_REJECT_COLOR := Color(0.95, 0.30, 0.30, 0.50)
const RAMP_REJECT_EDGE := Color(1.0, 0.50, 0.50, 0.95)
## Ramp 工具：Shift+RMB 单击删邻域（RMB 拖动留给相机平移）
const RAMP_ERASE_RADIUS := 1
const INVALID_VERT := Vector2i(-99999, -99999)

var document ## MapDocument（preload 实例）
var camera: Camera3D
var space: World3D
## 命令历史（MapEditor 注入）；为空则不记撤销
var history: EditorCommandHistory = null

var _painting: bool = false
var _last_vert: Vector2i = INVALID_VERT
var _hover_vert: Vector2i = INVALID_VERT
var _dirty_paint: bool = false
var _last_rebuild_ms: int = 0
var _enabled: bool = true
var enabled: bool:
	get:
		return _enabled
	set(v):
		_enabled = v
		if not _enabled:
			_painting = false
			_set_hover_vert(INVALID_VERT)
## 笔刷半径档：1=单点，5=半径 4；形状 0 圆 / 1 方
var brush_size: int = 1
var brush_shape: int = 0 ## 0 circle, 1 square
var apply_texture: bool = true
var apply_cliff: bool = true
## 特殊纹理：0 无 / 1 荒芜(未接) / 2 边界 / 3 去除边界（对齐 ToolPaletteWindow.SpecialTexture）
var special_texture: int = 0
## 悬崖/斜坡笔刷开启时 → 全 heightfield 快照（防 cliff 级联 clamp 漏快照）。
## 由 set_cliff_settings() 自动设；地表笔刷保持局部 CAPTURE_RADIUS 行为。
var use_full_snapshot: bool = false
## WorldEditData 悬崖工具 id："0".."4" / ShallowWater / DeepWater / Ramp
var cliff_tool_id: String = "2"
var cliff_type_index: int = 0
## 本笔划是否改过悬崖数据（决定重建是否含悬崖/水面）
var cliff_dirty: bool = false

var _hover_mesh: MeshInstance3D
var _hover_mat: StandardMaterial3D
var _edge_mesh: MeshInstance3D
var _edge_mat: StandardMaterial3D
## 整平工具：按下瞬间采样的目标层
var _cliff_level_anchor: int = -1
var _stroke: PaintStrokeRecorder = PaintStrokeRecorder.new()


func set_brush_settings(size: int, shape: int) -> void:
	brush_size = _sanitize_brush_size(size)
	brush_shape = 0 if shape == 0 else 1
	if _hover_vert != INVALID_VERT:
		_update_hover_preview(_hover_vert)


func nudge_brush_size(dir: int) -> void:
	const SIZES := [1, 2, 3, 5, 8]
	var idx: int = SIZES.find(brush_size)
	if idx < 0:
		idx = 0
	idx = clampi(idx + dir, 0, SIZES.size() - 1)
	set_brush_settings(SIZES[idx], brush_shape)
	brush_settings_changed.emit(brush_size, brush_shape)


func is_ramp_tool() -> bool:
	return apply_cliff and cliff_tool_id == "Ramp"


## —— 输入由 EditorInputRouter 调用 ——

func stroke_press(screen_pos: Vector2) -> void:
	if not enabled or document == null or camera == null:
		return
	_painting = true
	_cliff_level_anchor = -1
	_begin_stroke()
	_paint_at_mouse(screen_pos)


func stroke_drag(screen_pos: Vector2) -> void:
	if not enabled or not _painting:
		return
	_paint_at_mouse(screen_pos)


func stroke_release() -> void:
	_finish_paint_gesture()


func erase_ramp_at(screen_pos: Vector2) -> void:
	if not enabled or document == null or camera == null:
		return
	if not is_ramp_tool():
		return
	_cliff_level_anchor = -1
	_begin_stroke()
	_erase_ramp_at_mouse(screen_pos)
	_finish_paint_gesture()


func set_cliff_settings(p_apply: bool, tool_id: String, type_idx: int) -> void:
	apply_cliff = p_apply
	cliff_tool_id = tool_id if not tool_id.is_empty() else "2"
	cliff_type_index = maxi(type_idx, 0)
	# 悬崖/斜坡笔刷的修改可能级联传播到笔刷区域外（cliff 邻接 clamp、ramp 9-corner valid），
	# 用全 heightfield 快照防漏；地表笔刷继续走局部 CAPTURE_RADIUS。
	use_full_snapshot = p_apply
	if document != null and document.has_method("ensure_cliff_type_valid"):
		document.brush_cliff_type = cliff_type_index
		document.ensure_cliff_type_valid()
		cliff_type_index = int(document.brush_cliff_type)


func set_special_texture(kind: int) -> void:
	special_texture = clampi(kind, 0, 3)


func is_boundary_tool() -> bool:
	return special_texture == 2 or special_texture == 3


static func _sanitize_brush_size(p_size: int) -> int:
	const SIZES := [1, 2, 3, 5, 8]
	if p_size in SIZES:
		return p_size
	var best: int = SIZES[0]
	var best_d: int = absi(p_size - best)
	for s in SIZES:
		var d: int = absi(p_size - int(s))
		if d < best_d:
			best = int(s)
			best_d = d
	return best


## 方形外接半宽（tilepoint）：尺寸 N → 边长 N，半宽 (N-1)/2。
func _brush_half_extent() -> float:
	return float(maxi(brush_size - 1, 0)) * 0.5


## 圆形笔刷：欧氏格点 dx²+dy² ≤ R²。
## R 取自 WorldEditData 圆形尺寸图标序号 TextureBrush{00,01,02,04,07}：
##   尺寸 1 / 2 / 3 / 5 / 8  →  R = 0 / 1 / 2 / 4 / 7
## 行宽（从上到下）：
##   1 → [1]
##   2 → [1,3,1]                 十字（截图）
##   3 → [1,3,5,3,1]             菱形十字花（截图）
##   5 → [1,5,7,7,9,7,7,5,1]     外侧尖端十字花（非实心方）
##   8 → [1,7,9,11,13,13,13,15,…]
func _circle_radius_sq() -> int:
	match brush_size:
		1:
			return 0
		2:
			return 1
		3:
			return 4
		5:
			return 16
		8:
			return 49
		_:
			var r: int = maxi(brush_size - 1, 0)
			return r * r


func _ready() -> void:
	_ensure_hover_visuals()


func setup(doc, cam: Camera3D, world: World3D, p_history: EditorCommandHistory = null) -> void:
	document = doc
	camera = cam
	space = world
	history = p_history
	_ensure_hover_visuals()
	_hide_hover_preview()


func _ensure_hover_visuals() -> void:
	if _hover_mesh != null:
		return
	_hover_mat = StandardMaterial3D.new()
	_hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hover_mat.albedo_color = HOVER_COLOR
	_hover_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_hover_mat.no_depth_test = true
	_hover_mat.render_priority = 100

	_hover_mesh = MeshInstance3D.new()
	_hover_mesh.name = "HoverFill"
	_hover_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hover_mesh.material_override = _hover_mat
	add_child(_hover_mesh)

	_edge_mat = StandardMaterial3D.new()
	_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_edge_mat.albedo_color = HOVER_EDGE
	_edge_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_edge_mat.no_depth_test = true
	_edge_mat.render_priority = 101

	_edge_mesh = MeshInstance3D.new()
	_edge_mesh.name = "HoverEdge"
	_edge_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_edge_mesh.material_override = _edge_mat
	add_child(_edge_mesh)


func _unhandled_input(_event: InputEvent) -> void:
	# 输入改由 EditorInputRouter 统一路由（editor_main 子节点）
	pass


func _process(_delta: float) -> void:
	# 工具面板 always_on_top 时，松键事件可能到不了主视口 → 笔划永不 record
	if _painting and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_paint_gesture()
	if _dirty_paint and not _painting:
		_request_rebuild(false)
	elif _dirty_paint and _painting:
		var now: int = Time.get_ticks_msec()
		if now - _last_rebuild_ms >= REBUILD_INTERVAL_MS:
			_request_rebuild(false)
	# 工具面板抢焦点后主窗口可能收不到 MouseMotion：按全局鼠标位置轮询悬停
	if not _painting:
		_poll_hover_from_global_mouse()


## 结束一次按下→抬起：入撤销栈并请求重建。
func _finish_paint_gesture() -> void:
	if not _painting and not _stroke.is_active():
		return
	_painting = false
	_cliff_level_anchor = -1
	_last_vert = INVALID_VERT
	_end_stroke()
	if _dirty_paint:
		_request_rebuild(true)


## 鼠标在主编辑窗口地图区时更新预览（不依赖窗口焦点 / 右键激活）。
func _poll_hover_from_global_mouse() -> void:
	if not enabled or document == null or camera == null:
		if _hover_vert != INVALID_VERT:
			_set_hover_vert(INVALID_VERT)
		return
	if not _is_mouse_over_main_window():
		if _hover_vert != INVALID_VERT:
			_set_hover_vert(INVALID_VERT)
		return
	var local: Vector2 = _main_window_mouse_local()
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null:
		# 停在菜单/工具条等 UI 上时不显示笔刷
		if _hover_vert != INVALID_VERT:
			_set_hover_vert(INVALID_VERT)
		return
	_set_hover_vert(_pick_vertex(local))


func _is_mouse_over_main_window() -> bool:
	var win := get_viewport().get_window()
	if win == null:
		return false
	var wid: int = win.get_window_id()
	var mp: Vector2i = DisplayServer.mouse_get_position()
	var rect := Rect2i(DisplayServer.window_get_position(wid), DisplayServer.window_get_size(wid))
	return rect.has_point(mp)


func _main_window_mouse_local() -> Vector2:
	# Viewport 坐标已处理缩放；勿用 DisplayServer 像素差（HiDPI 会偏）
	return get_viewport().get_mouse_position()


func _set_hover_vert(vert: Vector2i) -> void:
	if vert == _hover_vert:
		return
	_hover_vert = vert
	if vert == INVALID_VERT:
		_hide_hover_preview()
		return
	tile_hovered.emit(vert)
	_update_hover_preview(vert)


func _paint_at_mouse(screen_pos: Vector2) -> void:
	var vert: Vector2i = _pick_vertex(screen_pos)
	_set_hover_vert(vert)
	if vert == INVALID_VERT:
		return
	if vert == _last_vert and _painting:
		return
	_last_vert = vert
	var boundary_mode: bool = is_boundary_tool()
	if not apply_texture and not apply_cliff and not boundary_mode:
		return

	if apply_cliff and cliff_tool_id == "2" and _cliff_level_anchor < 0:
		_cliff_level_anchor = int(document.layer_at(vert.x, vert.y))

	var painted_any := false
	var cliff_any := false
	var boundary_enable: bool = special_texture == 2

	# 先悬崖后地表：cliff sync 会写 groundTile，必须让 paint_corner 最后盖住笔刷纹理
	# 边界特殊纹理：cell 模式写 BL（HiveWE Nothing）；不画普通地表
	if apply_cliff and cliff_tool_id == "Ramp" and not boundary_mode:
		# 鼠标相对角点的坡向（对齐 HiveWE apply_ramps）
		var dirs: Vector2i = _ramp_dirs_from_mouse(vert, screen_pos)
		var hx: int = dirs.x
		var hy: int = dirs.y
		# 先采足够大邻域 before（低侧意图原点≤2 + 臂长≤2 + L 补心）；避免只记 click 漏掉真正落旗点
		const RAMP_SNAP_R := 6
		_stroke.capture_before_at(vert.x, vert.y, RAMP_SNAP_R)
		var ramp_result: Dictionary = document.try_paint_ramp_at(vert.x, vert.y, hx, hy)
		document.last_ramp_message = str(ramp_result.get("message", ""))
		var ramp_changed: bool = bool(ramp_result.get("changed", false))
		_stroke.capture_after_at(vert.x, vert.y, RAMP_SNAP_R)
		# 结果 marked 再刷一遍 after（before 已在邻域内；勿在 paint 后再 capture_before）
		var marked: Array = ramp_result.get("marked", [])
		for v in marked:
			var mp: Vector2i = v as Vector2i
			_stroke.capture_after_at(mp.x, mp.y, 0)
		var msg: String = str(document.last_ramp_message)
		if not msg.is_empty():
			ramp_feedback.emit(msg)
		if ramp_changed:
			painted_any = true
			cliff_any = true
			_stroke.mark_cliff()
	else:
		for p in _brush_offsets():
			var ix: int = vert.x + p.x
			var iy: int = vert.y + p.y
			_stroke.capture_before_at(ix, iy)
			if apply_cliff and not boundary_mode and bool(
				document.paint_cliff_corner(
					ix, iy, cliff_tool_id, cliff_type_index, _cliff_level_anchor
				)
			):
				painted_any = true
				cliff_any = true
				_stroke.mark_cliff()
			if boundary_mode:
				if bool(document.paint_boundary_cell(ix, iy, boundary_enable)):
					painted_any = true
			elif apply_texture and bool(document.paint_corner(ix, iy)):
				painted_any = true
			_stroke.capture_after_at(ix, iy)
	if painted_any:
		_dirty_paint = true
		if cliff_any:
			cliff_dirty = true
		painted.emit()
		var brush_tex: int = int(document.brush_tile_index) if document != null else -1
		AppLog.info(
			AppLog.Layer.EDITOR,
			"Brush",
			"paint @(%d,%d) brush_tex=%d cliff=%s tex=%s special=%d tool=%s"
			% [vert.x, vert.y, brush_tex, cliff_any, apply_texture, special_texture, cliff_tool_id]
		)


## Ramp 工具：右击删邻域内所有 FLAG_RAMP（HivEWE 经典：单击即删）。
## stroke 已在 _unhandled_input 内 begin；本函数只做 erase + 收尾。
func _erase_ramp_at_mouse(screen_pos: Vector2) -> void:
	var vert: Vector2i = _pick_vertex(screen_pos)
	_set_hover_vert(vert)
	if vert == INVALID_VERT:
		return
	# 采邻域 before（与 paint 路径保持一致；erase 半径 1 不需 RAMP_SNAP_R）
	_stroke.capture_before_at(vert.x, vert.y, RAMP_ERASE_RADIUS)
	var n: int = document.erase_ramp_at(vert.x, vert.y, RAMP_ERASE_RADIUS)
	_stroke.capture_after_at(vert.x, vert.y, RAMP_ERASE_RADIUS)
	if n > 0:
		_stroke.mark_cliff()
		_dirty_paint = true
		cliff_dirty = true
		ramp_feedback.emit("已删斜坡 %d 点 @(ix=%d,iy=%d)" % [n, vert.x, vert.y])
		AppLog.info(
			AppLog.Layer.EDITOR,
			"Brush",
			"erase ramp @(%d,%d) cleared=%d radius=%d"
			% [vert.x, vert.y, n, RAMP_ERASE_RADIUS]
		)
	else:
		ramp_feedback.emit("当前角点无斜坡 @(ix=%d,iy=%d)" % [vert.x, vert.y])


func _begin_stroke() -> void:
	if history == null or document == null:
		return
	_stroke.begin(document, use_full_snapshot)


func _end_stroke() -> void:
	if history == null or not _stroke.is_active():
		_stroke.cancel()
		return
	var label := "Paint"
	if is_boundary_tool():
		label = "Boundary" if special_texture == 2 else "BoundaryRemove"
	elif apply_cliff and cliff_tool_id == "Ramp":
		label = "Ramp"
	elif apply_cliff and not apply_texture:
		label = "Cliff"
	elif apply_texture and not apply_cliff:
		label = "Ground"
	var cmd: PaintStrokeCommand = _stroke.finish(label)
	if cmd != null:
		AppLog.info(
			AppLog.Layer.EDITOR,
			"Brush",
			"record %s verts=%d cliff=%s" % [label, cmd.after.size(), cmd.affects_cliffs_water()]
		)
		history.record(cmd)
	else:
		AppLog.debug(AppLog.Layer.EDITOR, "Brush", "stroke empty（无数据变化）")


func _request_rebuild(force: bool) -> void:
	if not _dirty_paint and not force:
		return
	_dirty_paint = false
	_last_rebuild_ms = Time.get_ticks_msec()
	rebuild_requested.emit()
	if _hover_vert != INVALID_VERT:
		_update_hover_preview(_hover_vert)


func _pick_vertex(screen_pos: Vector2) -> Vector2i:
	if document == null or bool(document.is_empty()) or camera == null:
		return INVALID_VERT
	# 悬崖格地面挖洞，物理射线会穿过洞打到后方地面 → 预览偏移。
	# 始终对高度场求交（含悬崖顶），与 WE 一致。
	var hit: Vector3 = _raycast_heightfield(screen_pos)
	if hit == Vector3.INF:
		hit = _raycast_ground(screen_pos)
	if hit == Vector3.INF:
		hit = _ray_plane_fallback(screen_pos)
	if hit == Vector3.INF:
		return INVALID_VERT
	var vert: Vector2i = document.world_godot_to_tilepoint(hit) as Vector2i
	var tp: Vector2i = document.tilepoint_size()
	if vert.x < 0 or vert.y < 0 or vert.x >= tp.x or vert.y >= tp.y:
		return INVALID_VERT
	return vert


## 鼠标相对 tilepoint 的 ±1 坡向（HiveWE：mouse 与角点比较；本仓库加轴向主导以降单列难度）。
## Modifier（经典 WE 行为）：
##   Shift → 整体反向（让鼠标对侧也能 paint）
##   Alt   → 强制单轴（覆盖 soften_dirs 的 2x 软化，强行取主轴）
func _ramp_dirs_from_mouse(vert: Vector2i, screen_pos: Vector2) -> Vector2i:
	if document == null or camera == null:
		return Vector2i.ZERO
	var hit: Vector3 = _raycast_heightfield(screen_pos)
	if hit == Vector3.INF:
		hit = _raycast_ground(screen_pos)
	if hit == Vector3.INF:
		hit = _ray_plane_fallback(screen_pos)
	if hit == Vector3.INF:
		return Vector2i.ZERO
	var ws: float = Wc3Coords.WORLD_SCALE
	var mouse_wc3 := Vector2(hit.x / ws, -hit.z / ws)
	var corner: Vector2 = Wc3Coords.tilepoint_wc3(
		vert.x, vert.y, document.center_offset(), document.tile_size()
	)
	var dirs: Vector2i = Wc3RampPaint.soften_dirs(
		mouse_wc3.x - corner.x, mouse_wc3.y - corner.y
	)
	# Shift 反向（HivEWE apply_ramps 行为）
	if Input.is_key_pressed(KEY_SHIFT):
		dirs = Vector2i(-dirs.x, -dirs.y)
	# Alt 强制单轴（覆盖 soften_dirs 的 2x 软化，保留 abs 大的轴）
	if Input.is_key_pressed(KEY_ALT) and dirs.x != 0 and dirs.y != 0:
		if absi(dirs.x) >= absi(dirs.y):
			dirs = Vector2i(dirs.x, 0)
		else:
			dirs = Vector2i(0, dirs.y)
	return dirs


## 沿视线与 heightfield（含层高）求交；悬崖挖洞处仍可命中台顶。
func _raycast_heightfield(screen_pos: Vector2) -> Vector3:
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if dir.length_squared() < 1e-12:
		return Vector3.INF
	dir = dir.normalized()
	var t_lo := -1.0
	var t_hi := -1.0
	var t_prev := 0.25
	var prev_above := _godot_point_above_hf(from + dir * t_prev)
	var t_max := 4000.0
	var steps := 64
	for i in range(1, steps + 1):
		var t: float = 0.25 + (t_max - 0.25) * float(i) / float(steps)
		var above: bool = _godot_point_above_hf(from + dir * t)
		if above != prev_above:
			t_lo = t_prev
			t_hi = t
			break
		t_prev = t
		prev_above = above
	if t_lo < 0.0:
		return Vector3.INF
	for _k in range(18):
		var tm: float = (t_lo + t_hi) * 0.5
		if _godot_point_above_hf(from + dir * tm):
			t_lo = tm
		else:
			t_hi = tm
	return from + dir * t_hi


func _godot_point_above_hf(p: Vector3) -> bool:
	return p.y >= _heightfield_y_at_godot(p) - 0.0001


func _heightfield_y_at_godot(p: Vector3) -> float:
	var ws: float = Wc3Coords.WORLD_SCALE
	var center: Vector2 = document.center_offset()
	var ts: float = document.tile_size()
	if ts <= 0.0:
		return 0.0
	var fx: float = (p.x / ws - center.x) / ts
	var fy: float = (-p.z / ws - center.y) / ts
	return float(document.sample_height_at_xy(fx, fy)) * ws


func _hide_hover_preview() -> void:
	if _hover_mesh:
		_hover_mesh.visible = false
		_hover_mesh.mesh = null
	if _edge_mesh:
		_edge_mesh.visible = false
		_edge_mesh.mesh = null


func _update_hover_preview(vert: Vector2i) -> void:
	_ensure_hover_visuals()
	if document == null or bool(document.is_empty()):
		_hide_hover_preview()
		return
	# Ramp 工具：spine preview（点集）+ 失败时红框（HivEWE 经典 Ramp UX）
	if apply_cliff and cliff_tool_id == "Ramp":
		_update_ramp_hover_preview(vert)
		return
	var fill: ArrayMesh
	var edge: ArrayMesh
	if brush_shape == 0:
		_hover_mat.albedo_color = HOVER_COLOR
		_edge_mat.albedo_color = HOVER_EDGE
		fill = _make_offsets_fill_mesh(vert.x, vert.y)
		edge = _make_offsets_edge_mesh(vert.x, vert.y)
	else:
		_hover_mat.albedo_color = HOVER_COLOR
		_edge_mat.albedo_color = HOVER_EDGE
		var corners: Array = _brush_aabb_corners_godot(vert.x, vert.y)
		if corners.is_empty():
			_hide_hover_preview()
			return
		var bl: Vector3 = corners[0]
		var br: Vector3 = corners[1]
		var tl: Vector3 = corners[2]
		var p_tr: Vector3 = corners[3]
		var lift := Vector3(0.0, HOVER_LIFT, 0.0)
		fill = _make_fill_mesh(bl + lift, br + lift, tl + lift, p_tr + lift)
		edge = _make_edge_mesh(bl + lift, br + lift, tl + lift, p_tr + lift)
	if fill == null or edge == null:
		_hide_hover_preview()
		return
	_hover_mesh.mesh = fill
	_hover_mesh.visible = true
	_edge_mesh.mesh = edge
	_edge_mesh.visible = true


## Ramp 工具 hover：调 peek_spine_at 算落旗点集，画 spine preview；
## 失败时降级为单格红框（提示"点这无效"）。
func _update_ramp_hover_preview(vert: Vector2i) -> void:
	var dirs: Vector2i = _ramp_dirs_from_mouse(vert, _main_window_mouse_local())
	var spine: Array[Vector2i] = document.peek_ramp_spine_at(vert.x, vert.y, dirs.x, dirs.y)
	if spine.is_empty():
		# 落坡会失败：画当前点红框
		_hover_mat.albedo_color = RAMP_REJECT_COLOR
		_edge_mat.albedo_color = RAMP_REJECT_EDGE
		_hover_mesh.mesh = _make_offsets_fill_mesh(vert.x, vert.y)
		_edge_mesh.mesh = _make_offsets_edge_mesh(vert.x, vert.y)
	else:
		# 落坡将成功：画点集 spine
		_hover_mat.albedo_color = RAMP_SPINE_COLOR
		_edge_mat.albedo_color = RAMP_SPINE_EDGE
		_hover_mesh.mesh = _make_points_fill_mesh(spine)
		_edge_mesh.mesh = _make_points_edge_mesh(spine)
	_hover_mesh.visible = true
	_edge_mesh.visible = true


## spine preview fill：每个点画 1×1 方块（不走笔刷形状）。
## 直坡 → 3 格；L 补心 → 5 格；外角对角 → 9 格。
func _make_points_fill_mesh(points: Array[Vector2i]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in points:
		var bl := _tp_to_godot(float(p.x) - 0.5, float(p.y) - 0.5)
		var br := _tp_to_godot(float(p.x) + 0.5, float(p.y) - 0.5)
		var tl := _tp_to_godot(float(p.x) - 0.5, float(p.y) + 0.5)
		var p_tr := _tp_to_godot(float(p.x) + 0.5, float(p.y) + 0.5)
		_add_tri(st, bl, br, p_tr)
		_add_tri(st, bl, p_tr, tl)
	return st.commit()


## spine preview edge：每个点画 1×1 方框。
func _make_points_edge_mesh(points: Array[Vector2i]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for p in points:
		var bl := _tp_to_godot(float(p.x) - 0.5, float(p.y) - 0.5)
		var br := _tp_to_godot(float(p.x) + 0.5, float(p.y) - 0.5)
		var tl := _tp_to_godot(float(p.x) - 0.5, float(p.y) + 0.5)
		var p_tr := _tp_to_godot(float(p.x) + 0.5, float(p.y) + 0.5)
		_add_line(st, bl, br)
		_add_line(st, br, p_tr)
		_add_line(st, p_tr, tl)
		_add_line(st, tl, bl)
	return st.commit()


## 以 tilepoint 为中心的 1×1 预览（西南角 = vert-0.5），对齐顶点拾取。
func _make_vertex_fill_mesh(ix: int, iy: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bl := _tp_to_godot(float(ix) - 0.5, float(iy) - 0.5)
	var br := _tp_to_godot(float(ix) + 0.5, float(iy) - 0.5)
	var tl := _tp_to_godot(float(ix) - 0.5, float(iy) + 0.5)
	var p_tr := _tp_to_godot(float(ix) + 0.5, float(iy) + 0.5)
	_add_tri(st, bl, br, p_tr)
	_add_tri(st, bl, p_tr, tl)
	return st.commit()


func _make_vertex_edge_mesh(ix: int, iy: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var bl := _tp_to_godot(float(ix) - 0.5, float(iy) - 0.5)
	var br := _tp_to_godot(float(ix) + 0.5, float(iy) - 0.5)
	var tl := _tp_to_godot(float(ix) - 0.5, float(iy) + 0.5)
	var p_tr := _tp_to_godot(float(ix) + 0.5, float(iy) + 0.5)
	_add_line(st, bl, br)
	_add_line(st, br, p_tr)
	_add_line(st, p_tr, tl)
	_add_line(st, tl, bl)
	return st.commit()


## 笔刷外接方框四角（方形预览）。
func _brush_aabb_corners_godot(ix: int, iy: int) -> Array:
	var center: Vector2 = document.center_offset()
	var ts: float = document.tile_size()
	var half: float = _brush_half_extent() + 0.5
	var out: Array = []
	for c in [
		Vector2(float(ix) - half, float(iy) - half),
		Vector2(float(ix) + half, float(iy) - half),
		Vector2(float(ix) - half, float(iy) + half),
		Vector2(float(ix) + half, float(iy) + half),
	]:
		var h: float = float(document.sample_height_at_xy(c.x, c.y))
		var xy := Vector2(center.x + c.x * ts, center.y + c.y * ts)
		out.append(Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, h))
	return out


## 笔刷覆盖的相对偏移（tilepoint）。
## 圆形：欧氏格点（见 _circle_radius_sq）；方形：严格 size×size。
func _brush_offsets() -> Array:
	var out: Array = []
	if brush_shape == 0:
		var r2: int = _circle_radius_sq()
		var r_iter: int = int(ceil(sqrt(float(r2)))) if r2 > 0 else 0
		for dy in range(-r_iter, r_iter + 1):
			for dx in range(-r_iter, r_iter + 1):
				if dx * dx + dy * dy > r2:
					continue
				out.append(Vector2i(dx, dy))
	else:
		var x0: int = -int((brush_size - 1) / 2.0)
		var y0: int = x0
		for dy in range(brush_size):
			for dx in range(brush_size):
				out.append(Vector2i(x0 + dx, y0 + dy))
	if out.is_empty():
		out.append(Vector2i.ZERO)
	return out


func _tp_to_godot(fx: float, fy: float) -> Vector3:
	var center: Vector2 = document.center_offset()
	var ts: float = document.tile_size()
	var h: float = float(document.sample_height_at_xy(fx, fy))
	var xy := Vector2(center.x + fx * ts, center.y + fy * ts)
	var p: Vector3 = Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, h)
	p.y += HOVER_LIFT
	return p


## 每个笔刷格点画 1×1 方块并集（圆形预览用）。
func _make_offsets_fill_mesh(ix: int, iy: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for o in _brush_offsets():
		var ox: int = ix + int(o.x)
		var oy: int = iy + int(o.y)
		var bl := _tp_to_godot(float(ox) - 0.5, float(oy) - 0.5)
		var br := _tp_to_godot(float(ox) + 0.5, float(oy) - 0.5)
		var tl := _tp_to_godot(float(ox) - 0.5, float(oy) + 0.5)
		var p_tr := _tp_to_godot(float(ox) + 0.5, float(oy) + 0.5)
		_add_tri(st, bl, br, p_tr)
		_add_tri(st, bl, p_tr, tl)
	return st.commit()


func _make_offsets_edge_mesh(ix: int, iy: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for o in _brush_offsets():
		var ox: int = ix + int(o.x)
		var oy: int = iy + int(o.y)
		var bl := _tp_to_godot(float(ox) - 0.5, float(oy) - 0.5)
		var br := _tp_to_godot(float(ox) + 0.5, float(oy) - 0.5)
		var tl := _tp_to_godot(float(ox) - 0.5, float(oy) + 0.5)
		var p_tr := _tp_to_godot(float(ox) + 0.5, float(oy) + 0.5)
		_add_line(st, bl, br)
		_add_line(st, br, p_tr)
		_add_line(st, p_tr, tl)
		_add_line(st, tl, bl)
	return st.commit()


func _make_fill_mesh(bl: Vector3, br: Vector3, tl: Vector3, p_tr: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_tri(st, bl, br, p_tr)
	_add_tri(st, bl, p_tr, tl)
	return st.commit()


func _make_edge_mesh(bl: Vector3, br: Vector3, tl: Vector3, p_tr: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	_add_line(st, bl, br)
	_add_line(st, br, p_tr)
	_add_line(st, p_tr, tl)
	_add_line(st, tl, bl)
	return st.commit()


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_normal(Vector3.UP)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _add_line(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	if space == null:
		return Vector3.INF
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 5000.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result: Dictionary = space.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return Vector3.INF
	return result.position as Vector3


func _ray_plane_fallback(screen_pos: Vector2) -> Vector3:
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector3.INF
	var h_guess: float = 0.0
	if not bool(document.is_empty()):
		h_guess = float(document.sample_height_at_tile(0, 0)) * Wc3Coords.WORLD_SCALE
	var t: float = (h_guess - from.y) / dir.y
	if t < 0.0:
		return Vector3.INF
	var p: Vector3 = from + dir * t
	var vert: Vector2i = document.world_godot_to_tilepoint(p) as Vector2i
	var h2: float = float(document.sample_height_at_xy(float(vert.x), float(vert.y))) * Wc3Coords.WORLD_SCALE
	t = (h2 - from.y) / dir.y
	if t < 0.0:
		return Vector3.INF
	return from + dir * t
