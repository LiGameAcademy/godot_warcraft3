extends VBoxContainer
## 侧栏：当前地图 groundTilesets 列表。


signal tile_selected(index: int)

@onready var _list: ItemList = $ItemList


func _ready() -> void:
	_list.item_selected.connect(_on_item_selected)


func rebuild(doc, tiles: Wc3TerrainTiles) -> void:
	_list.clear()
	if doc == null or doc.is_empty():
		return
	var gs: Array = doc.ground_tilesets()
	for i in range(gs.size()):
		var tid: String = str(gs[i])
		var label: String = tid
		if tiles != null:
			label = tiles.display_name_for_tile_id(tid)
		_list.add_item("%d  %s" % [i, label])
	doc.ensure_brush_index_valid()
	if gs.size() > 0:
		_list.select(doc.brush_tile_index)


func _on_item_selected(index: int) -> void:
	tile_selected.emit(index)
