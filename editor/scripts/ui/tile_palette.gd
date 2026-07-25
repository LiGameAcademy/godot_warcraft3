extends VBoxContainer
## 侧栏：当前地图 groundTilesets 列表。


signal tile_selected(index: int)

@onready var _title: Label = $Title
@onready var _list: ItemList = $ItemList


func _ready() -> void:
	_list.item_selected.connect(_on_item_selected)
	_apply_locale()
	EditorI18n.locale_changed.connect(func(_loc: String) -> void: _apply_locale())


func _apply_locale() -> void:
	_title.text = EditorI18n.t("EDITOR_PALETTE_TITLE")


func rebuild(doc, tiles: Wc3TerrainTileCatalog, _strings = null) -> void:
	_list.clear()
	if doc == null or doc.is_empty():
		return
	var gs: Array = doc.ground_tilesets()
	for i in range(gs.size()):
		var tid: String = str(gs[i])
		_list.add_item("%d  %s" % [i, EditorI18n.tile_display_name(tiles, tid)])
	doc.ensure_brush_index_valid()
	if gs.size() > 0:
		_list.select(doc.brush_tile_index)


func _on_item_selected(index: int) -> void:
	tile_selected.emit(index)
