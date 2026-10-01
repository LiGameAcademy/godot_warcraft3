class_name SelectorInputLayer
extends CanvasLayer

## 透明世界点击层（仅转发 gui_input，不处理业务）。
##
## 由 [code]GameMain[/code] 作为平级子节点挂入；[code]UnitSelector[/code]
## 通过 [code]@export var input_layer: SelectorInputLayer[/code] 注入，
## 并订 [signal gui_input_received] 转给自身 [method _on_world_gui_input]。
##
## 选择器不再自己 [code]add_child(CanvasLayer/Control)[/code]，
## 子树结构可在场景编辑器中可视化调整。

## 子层 Control 名，供 [code]UnitSelector[/code] 读取「自己人」以豁免 HUD 阻挡判定。
const WORLD_INPUT_NAME := "WorldInput"

## 转发 [code]Control.gui_input[/code]；订阅方决定是否 [code]accept_event[/code]。
signal gui_input_received(event: InputEvent)


## 场景内 [code]WorldInput.gui_input[/code] 直连此方法，再 emit 外部信号，
## 避免外部必须通过 [code]find_child[/code] 抓取节点。
func _on_world_gui_input(event: InputEvent) -> void:
	gui_input_received.emit(event)


## 给选择器 / 调用方用：取透明 Control 引用（用于 [code]accept_event[/code] 等）。
func world_input() -> Control:
	return get_node_or_null(WORLD_INPUT_NAME) as Control