extends Window
## 「打开地图」：列出 `assets/map-parsed/<slug>/` 中已解析地图。


signal confirmed(entry: Dictionary)

const MapDocumentScript := preload("res://editor/scripts/map_document.gd")

@onready var _hint: Label = %Hint
@onready var _list: ItemList = %MapList
@onready var _ok_btn: Button = %OkBtn
@onready var _cancel_btn: Button = %CancelBtn

var _entries: Array = [] ## { dir, slug, name, detail }


func _ready() -> void:
	hide()


func setup() -> void:
	_wire_signals()
	_apply_strings()
	_refresh_list()
	if not EditorI18n.locale_changed.is_connected(_on_locale_changed):
		EditorI18n.locale_changed.connect(_on_locale_changed)


func _on_locale_changed(_loc: String) -> void:
	_apply_strings()
	_refresh_list()


func _wire_signals() -> void:
	if close_requested.is_connected(hide):
		return
	close_requested.connect(hide)
	_ok_btn.pressed.connect(_on_ok)
	_cancel_btn.pressed.connect(hide)
	_list.item_activated.connect(func(_i: int) -> void: _on_ok())
	_list.item_selected.connect(_on_selection_changed)


func _apply_strings() -> void:
	title = EditorI18n.t("EDITOR_OPENMAP_TITLE")
	_hint.text = EditorI18n.t("EDITOR_OPENMAP_HINT")
	_ok_btn.text = EditorI18n.strip_accel(EditorI18n.t("WESTRING_OK"))
	_cancel_btn.text = EditorI18n.t("WESTRING_CANCEL")


func _refresh_list() -> void:
	_entries = MapDocumentScript.list_parsed_maps()
	_list.clear()
	for e in _entries:
		var row: Dictionary = e
		var label := "%s  —  %s" % [str(row.get("name", "")), str(row.get("detail", ""))]
		_list.add_item(label)
	_ok_btn.disabled = _entries.is_empty()
	if _entries.is_empty():
		_hint.text = EditorI18n.t("EDITOR_OPENMAP_EMPTY")
		return
	_hint.text = EditorI18n.t("EDITOR_OPENMAP_HINT")
	# 默认选中 Lost Temple，否则第一项
	var sel := 0
	for i in range(_entries.size()):
		if str(_entries[i].get("slug", "")) == "losttemple":
			sel = i
			break
	_list.select(sel)
	_on_selection_changed(sel)


func _on_selection_changed(_index: int) -> void:
	_ok_btn.disabled = not _list.is_anything_selected()


func _on_ok() -> void:
	var selected: PackedInt32Array = _list.get_selected_items()
	if selected.is_empty():
		return
	var i: int = selected[0]
	if i < 0 or i >= _entries.size():
		return
	confirmed.emit(_entries[i])
	hide()
