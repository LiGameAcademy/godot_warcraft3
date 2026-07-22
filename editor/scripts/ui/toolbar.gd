extends HBoxContainer
## 菜单栏下方的简易状态条（笔刷 / 脏标记）。原版此处为图标工具条，后续再补。


@onready var _brush_label: Label = $BrushLabel
@onready var _dirty_label: Label = $DirtyLabel


func set_brush_text(text: String) -> void:
	_brush_label.text = "笔刷: %s" % text


func set_dirty(dirty: bool) -> void:
	_dirty_label.text = "● 已修改" if dirty else ""
	_dirty_label.modulate = Color(1.0, 0.75, 0.35) if dirty else Color.WHITE
