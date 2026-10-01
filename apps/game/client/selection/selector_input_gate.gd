class_name SelectorInputGate
extends Node

## HUD / UI 是否挡住世界点击。
##
## 双轨：
## - 扫描 [code]world_input_blockers[/code] 组（现有 HUD 登记方式，保留）
## - [method add_blocker] / [method remove_blocker] 主动注册（推荐新代码）
##
## 选择器自建穿透层与框选 overlay 通过 [method set_exempt_controls] 豁免。

signal blocker_changed

const GROUP_BLOCKERS := "world_input_blockers"

var _extra_blockers: Array[Control] = []
var _exempt: Array[Control] = []


## 豁免控件（input 穿透层 / MarqueeOverlay 等不算 UI 阻挡）。
func set_exempt_controls(controls: Array) -> void:
	_exempt.clear()
	for item in controls:
		if item is Control and is_instance_valid(item):
			_exempt.append(item as Control)


func add_blocker(ctrl: Control) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	if _extra_blockers.has(ctrl):
		return
	_extra_blockers.append(ctrl)
	blocker_changed.emit()


func remove_blocker(ctrl: Control) -> void:
	if ctrl == null:
		return
	var idx := _extra_blockers.find(ctrl)
	if idx < 0:
		return
	_extra_blockers.remove_at(idx)
	blocker_changed.emit()


## screen_pos 是否落在会吃世界点击的 UI 上。
func is_blocked_at(screen_pos: Vector2) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for panel in tree.get_nodes_in_group(GROUP_BLOCKERS):
		if _control_blocks(panel as Control, screen_pos):
			return true
	for panel in _extra_blockers:
		if _control_blocks(panel, screen_pos):
			return true
	var viewport := get_viewport()
	if viewport == null:
		return false
	var hovered := viewport.gui_get_hovered_control()
	if hovered != null and hovered.is_visible_in_tree() \
			and hovered.get_global_rect().has_point(screen_pos) \
			and _is_ui_control_blocking(hovered):
		return true
	return false


func _control_blocks(panel: Control, screen_pos: Vector2) -> bool:
	if panel == null or not is_instance_valid(panel):
		return false
	if panel.get_viewport() != get_viewport():
		return false
	if not panel.is_visible_in_tree():
		return false
	return panel.get_global_rect().has_point(screen_pos)


func _is_ui_control_blocking(ctrl: Control) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	for ex in _exempt:
		if not is_instance_valid(ex):
			continue
		if ctrl == ex or ex.is_ancestor_of(ctrl):
			return false
	if ctrl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	return true
