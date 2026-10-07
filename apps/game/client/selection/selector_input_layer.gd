class_name SelectorInputLayer
extends CanvasLayer

## 透明世界点击层壳（[code]WorldInput[/code] mouse_filter=Ignore）。
##
## 由 [code]GameMain[/code] 平级挂入；[code]UnitSelector[/code] 通过
## [member UnitSelector.input_layer_path] 取 [method world_input]，
## 独立嵌入时再订 [signal Control.gui_input]。
## 正式对局输入由 [MatchInputController] 独占，不经过本层信号。

## 子层 Control 名，供选择器读取「自己人」以豁免 HUD 阻挡判定。
const WORLD_INPUT_NAME := "WorldInput"


## 透明 Control（[code]accept_event[/code] / Gate 豁免用）。
func world_input() -> Control:
	return get_node_or_null(WORLD_INPUT_NAME) as Control
