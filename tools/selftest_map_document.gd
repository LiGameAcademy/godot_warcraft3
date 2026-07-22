extends SceneTree
## 自测：MapDocument 空白图 / 笔刷 / JSON 保存。

const MapDocumentScript := preload("res://editor/scripts/map_document.gd")
const LOST_TEMPLE := "res://assets/map-parsed/losttemple"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var doc = MapDocumentScript.new()
	doc.create_blank(5) # 4x4 tiles
	if doc.map_size() != Vector2i(4, 4):
		push_error("bad blank size %s" % doc.map_size())
		quit(1)
		return
	doc.brush_tile_index = 1
	if not doc.paint_tile(1, 1):
		push_error("paint failed")
		quit(1)
		return
	var ground: Array = doc.hf["groundTextures"]
	var tp_w := 5
	var corners := [1 * tp_w + 1, 1 * tp_w + 2, 2 * tp_w + 1, 2 * tp_w + 2]
	for i in corners:
		if int(ground[i]) != 1:
			push_error("corner %d not painted" % i)
			quit(1)
			return
	if not doc.is_dirty():
		push_error("expected dirty")
		quit(1)
		return
	var err: int = doc.save_json("user://editor_maps/selftest_blank.json")
	if err != OK:
		push_error("save failed %s" % err)
		quit(1)
		return
	if FileAccess.file_exists(LOST_TEMPLE.path_join("terrain-heightfield.json")):
		err = doc.load_from_map_dir(LOST_TEMPLE)
		if err != OK or doc.is_empty():
			push_error("load losttemple failed")
			quit(1)
			return
		if doc.is_dirty():
			push_error("fresh load should not be dirty")
			quit(1)
			return
	print("selftest_map_document OK")
	quit(0)
