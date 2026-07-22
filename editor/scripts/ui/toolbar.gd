extends HBoxContainer
## 菜单栏下方的简易状态条（笔刷 / 脏标记）。


@onready var _brush_label: Label = $BrushLabel
@onready var _dirty_label: Label = $DirtyLabel

var _brush_name: String = ""
var _dirty: bool = false


func _ready() -> void:
	_brush_name = ""
	_refresh()
	EditorI18n.locale_changed.connect(func(_loc: String) -> void: _refresh())


func set_brush_text(text: String) -> void:
	_brush_name = text
	_refresh()


func set_dirty(dirty: bool) -> void:
	_dirty = dirty
	_refresh()


func _refresh() -> void:
	if _brush_name.is_empty():
		_brush_label.text = EditorI18n.t("EDITOR_TOOLBAR_BRUSH_EMPTY")
	else:
		_brush_label.text = EditorI18n.t("EDITOR_TOOLBAR_BRUSH", [_brush_name])
	_dirty_label.text = EditorI18n.t("EDITOR_TOOLBAR_DIRTY") if _dirty else ""
	_dirty_label.modulate = Color(1.0, 0.75, 0.35) if _dirty else Color.WHITE
