class_name UnitSelector
extends Node

## 点选/框选中央裁决：选中集合 + 输入手势；拾取命中委托 [SelectionPicker]。
## 选中环 / 拾取半径数据在 SelectableComponent；交互闪环在 InteractableComponent。
##
## 游戏输入由 MatchInputController 转发；独立使用时启用自身 _input。
##
## 透明输入层与高图层由外部注入（[member input_layer_path] / [member overlay_layer_path]）。

signal selection_changed(primary: Node3D, selected: Array)

@export var enabled: bool = true:
	set(value):
		enabled = value
		if not value and _marquee != null:
			_cancel_gesture()
			_clear_hover()
@export var click_slop_px: float = 8.0
## ≥0 时只可选该 owner；-1 不限（点选可观察敌方/中立；下达指令看可控过滤）
@export var owner_filter: int = -1
## 框选（多选）仅保留该玩家单位/建筑；-1 不限。对齐原作：敌对/中立不可框选。
@export var marquee_owner: int = -1
@export var allow_buildings: bool = true
@export var allow_units: bool = true
## 输入层 CanvasLayer.layer；须低于 GameHud（默认 10）。仅在 [member input_layer] 为 null 时生效。
@export var input_canvas_layer: int = 5

## 外部注入的透明输入层（由 [code]GameMain[/code] 平级挂入）。
## .tscn 写 `input_layer = NodePath("../SelectorInputLayer")`，运行时 [code]setup[/code] 解析。
@export var input_layer_path: NodePath
@export var overlay_layer_path: NodePath

var camera: Camera3D
var unit_host: Node
## 额外拾取（如树木 promote）：Callable(screen_pos: Vector2) -> Node3D
var pick_extra: Callable = Callable()

var _picker: SelectionPicker = null
var _gate: SelectorInputGate = null
var _marquee: MarqueeSelection = MarqueeSelection.new()
## 由 overlay 层提供。
var _overlay: MarqueeOverlay = null
## 由 input 层提供；用于 [code]accept_event[/code] 与 HUD 阻挡豁免判定。
var _input_root: Control = null
var _marqueeing: bool = false
var _selected: Array[Node3D] = []
var _primary: Node3D = null
## 上一帧挂着选中环的宿主（用于取消选中时 hide）
var _ring_hosts: Array[Node3D] = []
## 当前悬停预览宿主（未选中单位/建筑；不含树木）
var _hover_host: Node3D = null
var _press_picked: Node3D = null
var _external_input := false


func _ready() -> void:
	set_process(false)
	_ensure_picker()
	_ensure_gate()
	_bind_input_layer()
	_bind_overlay_layer()


func setup(p_camera: Camera3D, p_unit_host: Node) -> void:
	camera = p_camera
	unit_host = p_unit_host
	set_process_input(not _external_input)
	Wc3DefStore.ensure_table(UnitBalanceDef.TABLE_NAME)
	Wc3DefStore.ensure_table(UnitUiDef.TABLE_NAME)
	_sync_picker()
	_picker.warm_bounds()
	if camera != null and camera.is_inside_tree():
		camera.make_current()
	_ensure_gate()
	_bind_input_layer()
	_bind_overlay_layer()
	if camera == null or unit_host == null:
		AppLog.warn(AppLog.Layer.GAME, "UnitSelector", "setup: camera 或 unit_host 为空，点选/框选不可用")
	else:
		AppLog.info(
			AppLog.Layer.GAME,
			"UnitSelector",
			"setup ok cam=%s host=%s children=%d filter=%d"
			% [camera.name, unit_host.name, unit_host.get_child_count(), owner_filter]
		)


## 供 GameDirector / MatchInputController 转发。处理了左键点选/框选则返回 true。
func handle_pointer_event(event: InputEvent) -> bool:
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
		if is_blocked_at(mb.position):
			return false
		if mb.pressed:
			_on_press(mb.position)
		else:
			_on_release(mb.position)
		return true
	if event is InputEventMouseMotion and _marqueeing:
		_marquee.update((event as InputEventMouseMotion).position)
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


## 屏幕点是否落在会吃世界点击的 HUD 上（委托 [SelectorInputGate]）。
func is_blocked_at(screen_pos: Vector2) -> bool:
	_ensure_gate()
	return _gate.is_blocked_at(screen_pos)


## 悬停预览：单位/建筑脚底半透明环；树木与已选中目标不显示。
func _update_hover(screen_pos: Vector2) -> void:
	if not enabled or camera == null or unit_host == null:
		_clear_hover()
		return
	if is_blocked_at(screen_pos):
		_clear_hover()
		return
	var picked := _picker_pick_at(screen_pos)
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


## 独立嵌入时的 GUI 兜底；正式对局输入由中央路由独占。
func _on_world_gui_input(event: InputEvent) -> void:
	if _external_input:
		return
	if handle_pointer_event(event) and _input_root != null:
		_input_root.accept_event()


func _input(event: InputEvent) -> void:
	# 仅独立使用时启用；中央路由绑定后 set_external_input 会停用此入口。
	if handle_pointer_event(event):
		get_viewport().set_input_as_handled()


## MatchInputController 绑定后独占路由；独立使用时恢复自身输入。
func set_external_input(value: bool) -> void:
	_external_input = value
	set_process_input(not value)
	_cancel_gesture()


func _cancel_gesture() -> void:
	_marqueeing = false
	_press_picked = null
	_marquee.cancel()
	set_process(false)


func _process(_delta: float) -> void:
	# 兜底：松手事件被 HUD Control 吃掉时，仍结束框选
	if _marqueeing and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_on_release(get_viewport().get_mouse_position())


func _on_press(screen_pos: Vector2) -> void:
	_clear_hover()
	_marqueeing = true
	set_process(true)
	_marquee.drag_threshold_px = click_slop_px
	_marquee.begin(screen_pos)
	_press_picked = _picker_pick_at(screen_pos)
	if _press_picked == null and pick_extra.is_valid():
		_press_picked = pick_extra.call(screen_pos) as Node3D
	# 按下即反馈；松开时不重新拾取已经移动的目标。
	if _press_picked != null:
		_set_selection([_press_picked])


func _on_release(screen_pos: Vector2) -> void:
	if not _marqueeing:
		return
	_marqueeing = false
	set_process(false)
	_marquee.update(screen_pos)
	var rect := _marquee.finish()
	if rect.size.x >= 0.5 and rect.size.y >= 0.5:
		_sync_picker()
		_set_selection(_picker.pick_in_rect(rect))
	else:
		if not is_instance_valid(_press_picked):
			clear_selection()
	_press_picked = null


## 供智能右键 / 采集瞄准：屏幕点选单位（含金矿建筑）。不含树木（树走 TreeRegistry）。
func pick_at(screen_pos: Vector2) -> Node3D:
	return _picker_pick_at(screen_pos)


## 脚底到屏幕点的像素距离；不可见/无相机返回 INF。
func screen_foot_distance(node: Node3D, screen_pos: Vector2) -> float:
	_sync_picker()
	return _picker.screen_foot_distance(node, screen_pos)


func _picker_pick_at(screen_pos: Vector2) -> Node3D:
	_sync_picker()
	return _picker.pick_at(screen_pos)


func _ensure_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		return
	_picker = SelectionPicker.new()
	_picker.name = "SelectionPicker"
	add_child(_picker)


func _ensure_gate() -> void:
	if _gate != null and is_instance_valid(_gate):
		return
	_gate = SelectorInputGate.new()
	_gate.name = "SelectorInputGate"
	add_child(_gate)


func _sync_picker() -> void:
	_ensure_picker()
	_picker.bind(camera, unit_host)
	_picker.set_filters(owner_filter, marquee_owner, allow_buildings, allow_units)


func _sync_gate_exempts() -> void:
	_ensure_gate()
	_gate.set_exempt_controls([_input_root, _overlay])


func _set_selection(nodes: Array) -> void:
	# 故意不设原作 12 人框选上限：选中集合可任意大。
	_clear_hover()
	var next: Array[Node3D] = []
	for n in nodes:
		if n is Node3D and is_instance_valid(n):
			next.append(n as Node3D)
	# 重复点击同一目标不重建命令卡、详情、肖像与集结反馈。
	if next == _selected:
		return
	_selected = next
	if _selected.is_empty():
		_primary = null
	else:
		if _primary == null or not is_instance_valid(_primary) or not _selected.has(_primary):
			_primary = _selected[0]
	_refresh_rings()
	selection_changed.emit(_primary, _selected.duplicate())


## 绑定外部输入层：取 [code]WorldInput[/code] Control。
func _bind_input_layer() -> void:
	if _input_root != null and is_instance_valid(_input_root):
		return
	var layer := _resolve_node(input_layer_path) as SelectorInputLayer
	if layer == null:
		return
	layer.layer = input_canvas_layer
	var world_input := layer.world_input()
	if world_input == null:
		AppLog.warn(AppLog.Layer.GAME, "UnitSelector", "_bind_input_layer: SelectorInputLayer 缺 WorldInput 子节点")
		return
	if not world_input.gui_input.is_connected(_on_world_gui_input):
		world_input.gui_input.connect(_on_world_gui_input)
	_input_root = world_input
	_sync_gate_exempts()


## 绑定外部高图层：取 [code]MarqueeOverlay[/code]，订阅 [signal MarqueeSelection.changed]。
func _bind_overlay_layer() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	var layer := _resolve_node(overlay_layer_path) as SelectorOverlayLayer
	if layer == null:
		return
	layer.bind_marquee(_marquee)
	_overlay = layer.marquee_overlay()
	_sync_gate_exempts()


## 解析 [code]@export NodePath[/code] 引用的兄弟节点。
## 空路径视为「未注入」（独立 selftest 正常），不报警。
func _resolve_node(path: NodePath) -> Node:
	if path.is_empty():
		return null
	var raw := get_node_or_null(path)
	if raw == null:
		AppLog.warn(AppLog.Layer.GAME, "UnitSelector", "_resolve_node: 未找到 %s" % [path])
		return null
	return raw


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
