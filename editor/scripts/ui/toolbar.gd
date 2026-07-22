extends HBoxContainer
## 顶栏：新建 / 打开 / 保存 + 当前贴图。


signal new_blank_pressed
signal open_lost_temple_pressed
signal save_pressed

@onready var _brush_label: Label = $BrushLabel
@onready var _dirty_label: Label = $DirtyLabel


func _ready() -> void:
	$BtnNew.pressed.connect(func() -> void: new_blank_pressed.emit())
	$BtnOpen.pressed.connect(func() -> void: open_lost_temple_pressed.emit())
	$BtnSave.pressed.connect(func() -> void: save_pressed.emit())


func set_brush_text(text: String) -> void:
	_brush_label.text = "笔刷: %s" % text


func set_dirty(dirty: bool) -> void:
	_dirty_label.text = "● 已修改" if dirty else ""
	_dirty_label.modulate = Color(1.0, 0.75, 0.35) if dirty else Color.WHITE
