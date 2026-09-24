class_name ResourceBar
extends PanelContainer

## 顶栏资源条：金 / 木 / 人口。只消费展示数值，不读 PlayerStock。

@onready var _gold_label: Label = %GoldValue
@onready var _lumber_label: Label = %LumberValue
@onready var _food_label: Label = %FoodValue


func set_resources(gold: int, lumber: int, food: int, food_max: int) -> void:
	if _gold_label:
		_gold_label.text = str(gold)
	if _lumber_label:
		_lumber_label.text = str(lumber)
	if _food_label:
		_food_label.text = "%d/%d" % [food, food_max]


## 响应式：右上角资源条宽度/高度。
func apply_layout(width: float, height: float, margin: float) -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -maxf(width, 160.0)
	offset_right = -maxf(margin, 4.0)
	offset_top = maxf(margin * 0.5, 0.0)
	offset_bottom = offset_top + maxf(height, 28.0)
