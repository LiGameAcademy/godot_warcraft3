extends PanelContainer
## 现代化底栏 HUD：状态 / 坐标 / 笔刷 / 物件属性 分段芯片。


@onready var _status: Label = %StatusValue
@onready var _coords: Label = %CoordsValue
@onready var _brush: Label = %BrushValue
@onready var _props: Label = %PropsValue
@onready var _caption_status: Label = %StatusCaption
@onready var _caption_coords: Label = %CoordsCaption
@onready var _caption_brush: Label = %BrushCaption
@onready var _caption_props: Label = %PropsCaption

var _status_text: String = ""
var _coords_text: String = ""
var _brush_text: String = ""
var _props_text: String = ""


func _ready() -> void:
	_apply_chrome()
	_apply_locale()
	if not EditorI18n.locale_changed.is_connected(_on_locale):
		EditorI18n.locale_changed.connect(_on_locale)
	_refresh()


func _on_locale(_loc: String) -> void:
	_apply_locale()
	_refresh()


func _apply_chrome() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.08, 0.1, 0.92)
	bg.border_width_top = 1
	bg.border_color = Color(0.95, 0.72, 0.28, 0.55)
	bg.content_margin_left = 12
	bg.content_margin_right = 12
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	add_theme_stylebox_override("panel", bg)


func _apply_locale() -> void:
	_caption_status.text = EditorI18n.t("EDITOR_HUD_STATUS")
	_caption_coords.text = EditorI18n.t("EDITOR_HUD_COORDS")
	_caption_brush.text = EditorI18n.t("EDITOR_HUD_BRUSH")
	_caption_props.text = EditorI18n.t("EDITOR_HUD_PROPS")


func set_status_text(text: String) -> void:
	_status_text = text
	_refresh()


func set_coords_text(text: String) -> void:
	_coords_text = text
	_refresh()


func set_brush_text(text: String) -> void:
	_brush_text = text
	_refresh()


func set_props_text(text: String) -> void:
	_props_text = text
	_refresh()


## 兼容旧 API：当作状态文案。
func set_status_label_text(text: String) -> void:
	set_status_text(text)


func _refresh() -> void:
	if _status != null:
		_status.text = _status_text if not _status_text.is_empty() else EditorI18n.t("EDITOR_STATUS_IDLE")
	if _coords != null:
		_coords.text = _coords_text if not _coords_text.is_empty() else "—"
	if _brush != null:
		_brush.text = _brush_text if not _brush_text.is_empty() else "—"
	if _props != null:
		_props.text = _props_text if not _props_text.is_empty() else "—"
