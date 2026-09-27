class_name SelectionPresenter
extends Node

## 选中 VM 推送：订阅 UnitSelector.selection_changed → UiManager.push_selection(vm)。
## VM 由 SelectionInfoBuilder 组装；本 Presenter 只负责"信号 → push"路由。
## SelectionHudModule 仍负责 portrait/buff/timed_life 等非 selection VM 职责。
##
## 挂在 UiGameplayBridge 子节点；attach(selector) / detach() 由 director 控制。
##
## 设计：docs/design/game/UI_FRAMEWORK.md §5

var _selector: Node = null
var _on_selection_changed: Callable = Callable()


func _ready() -> void:
	_on_selection_changed = _on_selection_changed_handler


func attach(selector: Node) -> void:
	detach()
	_selector = selector
	if _selector == null:
		return
	if _selector.has_signal("selection_changed"):
		var sig: Signal = _selector.get("selection_changed")
		sig.connect(_on_selection_changed)
	_push_current()


func detach() -> void:
	if _selector == null:
		return
	if _selector.has_signal("selection_changed"):
		var sig: Signal = _selector.get("selection_changed")
		if sig.is_connected(_on_selection_changed):
			sig.disconnect(_on_selection_changed)
	_selector = null


func _on_selection_changed_handler(_primary: Node3D, selected: Array) -> void:
	_push_current(selected)


func _push_current(selected: Array = []) -> void:
	if _selector == null or not is_instance_valid(_selector):
		return
	if not is_instance_valid(UiManager):
		return
	var primary: Node3D = null
	if _selector.has_method("get_primary"):
		primary = _selector.call("get_primary") as Node3D
	var use_selected: Array = selected
	if use_selected.is_empty() and _selector.has_method("get_selected"):
		use_selected = _selector.call("get_selected")
	if primary == null and use_selected.is_empty():
		# 空选也推一次空 VM，让 HUD 收到"清空"
		UiManager.push_selection(SelectionInfoBuilder.build_empty())
		return
	var vm: Dictionary = SelectionInfoBuilder.build(primary, use_selected)
	UiManager.push_selection(vm)