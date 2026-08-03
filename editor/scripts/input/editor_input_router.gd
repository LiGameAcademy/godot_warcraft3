extends Node
## 编辑器输入路由（WE / HiveWE 风格，非游戏 RTS）。
## 挂在 editor_main.tscn 下，统一吃鼠标/键盘，再调用 Camera / Brush API。
##
## 约定：
##   LMB           → 笔刷绘制
##   RMB 拖动      → 相机平移
##   Ctrl+RMB 拖动 → 相机旋转
##   Shift+RMB     → Ramp 工具删坡（扩展；避免与 RMB 平移冲突）
##   滚轮          → 缩放；Shift+滚轮 → 笔刷尺寸
##   方向键        → 相机平移（WE 主路径）
##   WASD / QE     → 相机平移/升降（编辑器便利，可选）
##   Ctrl+Z / Y    → 撤销/重做


@export var camera_rig: Node3D
@export var brush: Node3D
@export var editor: Node

const BRUSH_SIZES := [1, 2, 3, 5, 8]
const PAN_DRAG_SCALE := 0.0025
const RMB_CLICK_SLOP_PX := 4.0

var _lmb_down: bool = false
var _rmb_down: bool = false
var _rmb_orbit: bool = false ## Ctrl+RMB
var _rmb_press_pos: Vector2 = Vector2.ZERO
var _rmb_dragged: bool = false
var _rmb_shift_erase: bool = false


func _ready() -> void:
	_resolve_exports()


func _resolve_exports() -> void:
	if camera_rig == null:
		camera_rig = get_node_or_null("../EditorCamera") as Node3D
	if brush == null:
		brush = get_node_or_null("../TerrainBrush") as Node3D
	if editor == null:
		editor = get_node_or_null("../Editor")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _handle_edit_hotkeys(event as InputEventKey):
			get_viewport().set_input_as_handled()
			return
		if _handle_brush_size_keys(event as InputEventKey):
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		if _handle_mouse_button(event as InputEventMouseButton):
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		if _handle_mouse_motion(event as InputEventMouseMotion):
			get_viewport().set_input_as_handled()
			return


func _process(delta: float) -> void:
	_resolve_exports()
	if camera_rig == null:
		return
	# 松键兜底（浮窗抢焦点时）
	if _lmb_down and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_lmb_down = false
		if brush != null and brush.has_method("stroke_release"):
			brush.stroke_release()
	if _rmb_down and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_finish_rmb()

	var dir := _keyboard_move_dir()
	var sprint := Input.is_key_pressed(KEY_SHIFT) and not _lmb_down
	if camera_rig.has_method("set_keyboard_move"):
		camera_rig.set_keyboard_move(dir, sprint, delta)
	elif dir != Vector3.ZERO and camera_rig.has_method("apply_keyboard_pan"):
		camera_rig.apply_keyboard_pan(dir, sprint, delta)


func _handle_edit_hotkeys(k: InputEventKey) -> bool:
	if editor == null:
		return false
	if k.ctrl_pressed and k.keycode == KEY_Z and not k.shift_pressed:
		if editor.has_method("_undo"):
			editor.call("_undo")
			return true
	if (
		(k.ctrl_pressed and k.keycode == KEY_Y)
		or (k.ctrl_pressed and k.shift_pressed and k.keycode == KEY_Z)
	):
		if editor.has_method("_redo"):
			editor.call("_redo")
			return true
	# 装饰物：Delete / Esc / [ ] / R — 交给当前 brush
	if brush != null and brush.has_method("handle_key"):
		if brush.handle_key(k):
			return true
	return false


func _handle_brush_size_keys(k: InputEventKey) -> bool:
	if k.keycode == KEY_EQUAL or k.keycode == KEY_KP_ADD:
		_nudge_brush_size(1)
		return true
	if k.keycode == KEY_MINUS or k.keycode == KEY_KP_SUBTRACT:
		_nudge_brush_size(-1)
		return true
	return false


func _handle_mouse_button(mb: InputEventMouseButton) -> bool:
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			_lmb_down = mb.pressed
			if brush == null:
				return false
			if mb.pressed:
				if mb.double_click and brush.has_method("handle_double_click"):
					brush.handle_double_click(mb.position)
					return true
				if brush.has_method("stroke_press"):
					brush.stroke_press(mb.position)
			else:
				if brush.has_method("stroke_release"):
					brush.stroke_release()
			return true
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rmb_down = true
				_rmb_press_pos = mb.position
				_rmb_dragged = false
				_rmb_orbit = mb.ctrl_pressed
				_rmb_shift_erase = mb.shift_pressed and _is_ramp_tool()
			else:
				_finish_rmb(mb.position)
			return true
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				if mb.ctrl_pressed and brush != null and brush.has_method("nudge_facing"):
					brush.nudge_facing(-45.0)
					return true
				if mb.shift_pressed:
					_nudge_brush_size(1)
				elif camera_rig != null and camera_rig.has_method("apply_zoom"):
					camera_rig.apply_zoom(-1)
			return true
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				if mb.ctrl_pressed and brush != null and brush.has_method("nudge_facing"):
					brush.nudge_facing(45.0)
					return true
				if mb.shift_pressed:
					_nudge_brush_size(-1)
				elif camera_rig != null and camera_rig.has_method("apply_zoom"):
					camera_rig.apply_zoom(1)
			return true
		MOUSE_BUTTON_MIDDLE:
			# 中键：平移（备选，对齐部分编辑器习惯）
			if mb.pressed:
				_rmb_down = true
				_rmb_press_pos = mb.position
				_rmb_dragged = false
				_rmb_orbit = false
				_rmb_shift_erase = false
			else:
				_rmb_down = false
			return true
	return false


func _handle_mouse_motion(mm: InputEventMouseMotion) -> bool:
	if _lmb_down and brush != null and brush.has_method("stroke_drag"):
		brush.stroke_drag(mm.position)
		return true
	if _rmb_down and camera_rig != null:
		if mm.relative.length() > 0.5:
			_rmb_dragged = true
		if _rmb_orbit and camera_rig.has_method("apply_orbit"):
			camera_rig.apply_orbit(mm.relative)
			return true
		if not _rmb_shift_erase and camera_rig.has_method("apply_pan_screen"):
			camera_rig.apply_pan_screen(mm.relative)
			return true
	# 装饰物幽灵 / 悬停预览（不吞事件，便于其它 UI）
	if not _lmb_down and not _rmb_down and brush != null and brush.has_method("hover"):
		brush.hover(mm.position)
	return false


func _finish_rmb(release_pos: Vector2 = Vector2.INF) -> void:
	var was_shift_erase := _rmb_shift_erase
	var dragged := _rmb_dragged
	var press_pos := _rmb_press_pos
	_rmb_down = false
	_rmb_orbit = false
	_rmb_shift_erase = false
	_rmb_dragged = false
	if not was_shift_erase:
		return
	if dragged:
		return
	var pos := release_pos if release_pos != Vector2.INF else press_pos
	if pos.distance_to(press_pos) > RMB_CLICK_SLOP_PX:
		return
	if brush != null and brush.has_method("erase_ramp_at"):
		brush.erase_ramp_at(pos)


func _is_ramp_tool() -> bool:
	if brush == null:
		return false
	if brush.has_method("is_ramp_tool"):
		return bool(brush.is_ramp_tool())
	return bool(brush.get("apply_cliff")) and str(brush.get("cliff_tool_id")) == "Ramp"


func _nudge_brush_size(dir: int) -> void:
	if brush == null or not brush.has_method("nudge_brush_size"):
		return
	brush.nudge_brush_size(dir)
	# 同步工具面板 / HUD
	if editor != null and editor.has_method("_on_brush_settings_changed"):
		var sz: int = int(brush.get("brush_size"))
		var shape: int = int(brush.get("brush_shape"))
		editor.call("_on_brush_settings_changed", sz, shape)


func _keyboard_move_dir() -> Vector3:
	var input_dir := Vector3.ZERO
	# WE 主路径：方向键
	if Input.is_key_pressed(KEY_UP):
		input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		input_dir.z += 1.0
	if Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0
	# 编辑器便利：WASD / QE
	if Input.is_key_pressed(KEY_W):
		input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_key_pressed(KEY_Q):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_E):
		input_dir.y += 1.0
	return input_dir
