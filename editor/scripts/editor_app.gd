extends Node3D
## 地图编辑器根：文档 + MapRoot 预览 + 地表笔刷 + 原版顶栏菜单。


const MapDocumentScript := preload("res://editor/scripts/map_document.gd")
const TerrainBrushScript := preload("res://editor/scripts/tools/terrain_brush.gd")
const StringsScript := preload("res://editor/scripts/ui/world_edit_strings.gd")

@onready var _map: MapLoader = $MapRoot
@onready var _cam_rig = $EditorCamera
@onready var _menu = $UI/MenuBarPanel/MenuBar
@onready var _toolbar = $UI/ToolStrip/Toolbar
@onready var _palette = $UI/SideBar/TilePalette
@onready var _status: Label = $UI/StatusBar/Status
@onready var _hover: Label = $UI/StatusBar/Hover

var _doc
var _brush: Node
var _rebuilding: bool = false
var _strings


func _ready() -> void:
	_doc = MapDocumentScript.new()
	_strings = StringsScript.load_default()
	_brush = TerrainBrushScript.new()
	_brush.name = "TerrainBrush"
	add_child(_brush)

	_map.auto_load_on_ready = false
	_map.build_water = true
	_map.build_cliffs = true
	_map.place_doodads = false
	_map.place_units = false
	_map.show_pathing_debug_grid = false
	_map.build_terrain_collision = true
	_map.status_path = NodePath("")

	_menu.action_triggered.connect(_on_menu_action)
	_palette.tile_selected.connect(_on_tile_selected)
	_brush.tile_hovered.connect(_on_tile_hovered)
	_brush.rebuild_requested.connect(_on_brush_rebuild)
	_doc.dirty_changed.connect(_on_dirty_changed)

	await get_tree().process_frame
	await _on_open_lost_temple()


func _on_menu_action(action_id: StringName) -> void:
	match String(action_id):
		"file_new":
			await _on_new_blank()
		"file_open":
			await _on_open_lost_temple()
		"file_save":
			_on_save()
		"file_exit":
			get_tree().quit()
		"layer_terrain", "tools_sel_brush", "module_terrain":
			_set_status("当前：地形编辑器 / 地表笔刷（左键绘制）")
		"help_about":
			_set_status("%s — Godot 复刻竖切" % _strings.get_text("WESTRING_APPNAME", "魔兽争霸III地图编辑器"))
		_:
			_set_status("尚未实现：%s" % String(action_id))


func _on_new_blank() -> void:
	_doc.create_blank()
	await _apply_document(true)
	_set_status("已新建空白图 %dx%d 格" % [_doc.map_size().x, _doc.map_size().y])


func _on_open_lost_temple() -> void:
	var err: int = _doc.load_from_map_dir(MapDocumentScript.DEFAULT_MAP_DIR)
	if err != OK:
		_set_status("打开失败：缺少 map-parsed/losttemple")
		return
	await _apply_document(true)
	_set_status("已打开 Lost Temple（只编辑内存文档，不改磁盘）")


func _on_save() -> void:
	var err: int = _doc.save_json()
	if err != OK:
		_set_status("保存失败")
		return
	_set_status("已保存到 user://editor_maps/")


func _on_tile_selected(index: int) -> void:
	_doc.brush_tile_index = index
	_refresh_brush_label()


func _on_tile_hovered(tile: Vector2i) -> void:
	_hover.text = "格 (%d, %d)" % [tile.x, tile.y]


func _on_dirty_changed(dirty: bool) -> void:
	_toolbar.set_dirty(dirty)


func _on_brush_rebuild() -> void:
	if _rebuilding:
		return
	_rebuilding = true
	_map.rebuild_terrain_only(_doc.hf, _doc.info)
	_rebuilding = false


func _apply_document(full_reload: bool) -> void:
	_palette.rebuild(_doc, _map.get_tiles())
	_refresh_brush_label()
	_toolbar.set_dirty(_doc.is_dirty())
	_brush.setup(_doc, _cam_rig.get_camera(), get_world_3d())
	if full_reload:
		var dir: String = _doc.map_dir if not _doc.map_dir.is_empty() else "res://"
		await _map.reload_from_hf(_doc.hf, _doc.info, dir)
	else:
		_map.rebuild_terrain_only(_doc.hf, _doc.info)
	_cam_rig.focus_map_extent(_doc.map_size())


func _refresh_brush_label() -> void:
	var tid: String = str(_doc.brush_tile_id())
	var label: String = tid
	var tiles: Wc3TerrainTiles = _map.get_tiles()
	if tiles != null and not tid.is_empty():
		label = tiles.display_name_for_tile_id(tid)
	_toolbar.set_brush_text(label)


func _set_status(text: String) -> void:
	_status.text = text
	print("Editor: %s" % text)
