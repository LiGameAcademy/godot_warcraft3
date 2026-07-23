extends Node3D
## 地图编辑器根：文档 + MapRoot 预览 + 地表笔刷 + 原版顶栏菜单。


const MapDocumentScript := preload("res://editor/scripts/map_document.gd")
const DataScript := preload("res://editor/scripts/ui/world_edit_data.gd")
const ToolPaletteScene := preload("res://editor/scripts/ui/tool_palette_window.tscn")
const ToolPaletteWindowScript := preload("res://editor/scripts/ui/tool_palette_window.gd")

@onready var _map: MapLoader = $MapRoot
@onready var _cam_rig = $EditorCamera
@onready var _brush: Node = $TerrainBrush
@onready var _new_map_dialog: Window = $NewMapDialog
@onready var _menu = $UI/MenuBarPanel/MenuBar
@onready var _toolbar = $UI/ToolStrip/Toolbar
@onready var _palette = $UI/SideBar/TilePalette
@onready var _status: Label = $UI/StatusBar/Status
@onready var _hover: Label = $UI/StatusBar/Hover

var _doc
var _rebuilding: bool = false
var _we_data
var _hover_tile: Vector2i = Vector2i(-1, -1)
var _status_key: String = "EDITOR_STATUS_IDLE"
var _status_args: Array = []
var _tool_palettes: Array = [] ## ToolPaletteWindow instances
var _palettes_visible: bool = true
var _palette_spawn_index: int = 0
var _brush_size: int = 1
var _brush_shape: int = 0 ## 0 circle / 1 square
var _apply_texture: bool = true
var _apply_cliff: bool = true
var _cliff_tool_id: String = "2"
var _cliff_type_index: int = 0


func _ready() -> void:
	_doc = MapDocumentScript.new()
	_we_data = DataScript.load_default()

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
	_new_map_dialog.setup(_map.get_tiles(), null, _we_data)
	_new_map_dialog.confirmed.connect(_on_new_map_confirmed)
	EditorI18n.locale_changed.connect(_on_locale_changed)
	_apply_chrome_locale()

	await get_tree().process_frame
	await _startup_new_map()
	# 经典 WE：启动后默认有一个地形工具面板
	_spawn_tool_palette(ToolPaletteWindowScript.PaletteKind.TERRAIN)


## 启动时按 WorldEditData 默认值建空白图（不再自动打开 Lost Temple）。
func _startup_new_map() -> void:
	var options := _default_new_map_options()
	_doc.create_from_options(options)
	_doc.clear_dirty()
	await _apply_document(true)
	_set_status_key(
		"EDITOR_STATUS_MAP_CREATED",
		[
			int(options.get("width", 0)),
			int(options.get("height", 0)),
			str(options.get("main_tileset_name", "")),
		]
	)


func _default_new_map_options() -> Dictionary:
	var letter: String = str(_we_data.default_tileset)
	var w: int = int(_we_data.default_map_size.x)
	var h: int = int(_we_data.default_map_size.y)
	var ts_name := letter
	for ts in _we_data.tilesets:
		if str(ts.get("id", "")) == letter:
			var name_key := str(ts.get("name_key", ""))
			ts_name = EditorI18n.t(name_key)
			if ts_name == name_key:
				ts_name = letter
			break
	var tiles: Wc3TerrainTiles = _map.get_tiles()
	var ground: Array = []
	var cliffs: Array = []
	if tiles != null:
		for tid in tiles.tile_ids_for_tileset(letter):
			ground.append(tid)
		for cid in tiles.cliff_ids_for_tileset(letter):
			cliffs.append(cid)
	if ground.is_empty():
		ground = MapDocumentScript.DEFAULT_GROUND.duplicate()
	if cliffs.is_empty():
		cliffs = MapDocumentScript.DEFAULT_CLIFF.duplicate()
	return {
		"width": w if w > 0 else 64,
		"height": h if h > 0 else 64,
		"main_tileset": letter,
		"main_tileset_name": ts_name,
		"ground_tilesets": ground,
		"cliff_tilesets": cliffs,
		"default_tile_index": 0,
		"cliff_level": 2,
		"water_mode": 0,
		"random_height": false,
	}

func _on_locale_changed(_loc: String) -> void:
	_apply_chrome_locale()
	_refresh_brush_label()
	_set_status_key(_status_key, _status_args)


func _apply_chrome_locale() -> void:
	if _hover_tile.x < 0:
		_hover.text = EditorI18n.t("EDITOR_HOVER_CELL_EMPTY")
	else:
		_hover.text = EditorI18n.t("EDITOR_HOVER_CELL", [_hover_tile.x, _hover_tile.y])


func _on_menu_action(action_id: StringName) -> void:
	match String(action_id):
		"file_new":
			_show_new_map_dialog()
		"file_open":
			await _on_open_lost_temple()
		"file_save":
			_on_save()
		"file_exit":
			get_tree().quit()
		"view_grid_none":
			_set_view_grid(MapLoader.ViewGridLevel.NONE)
		"view_grid_large":
			_set_view_grid(MapLoader.ViewGridLevel.LARGE)
		"view_grid_medium":
			_set_view_grid(MapLoader.ViewGridLevel.MEDIUM)
		"view_grid_small":
			_set_view_grid(MapLoader.ViewGridLevel.SMALL)
		"view_grid", "window_new_palette":
			pass # 父项仅展开子菜单
		"window_new_palette_terrain":
			_spawn_tool_palette(ToolPaletteWindowScript.PaletteKind.TERRAIN)
		"window_new_palette_units":
			_spawn_tool_palette(ToolPaletteWindowScript.PaletteKind.UNITS)
		"window_new_palette_doodads":
			_spawn_tool_palette(ToolPaletteWindowScript.PaletteKind.DOODADS)
		"window_new_palette_regions":
			_spawn_tool_palette(ToolPaletteWindowScript.PaletteKind.REGIONS)
		"window_new_palette_cameras":
			_spawn_tool_palette(ToolPaletteWindowScript.PaletteKind.CAMERAS)
		"window_show_palettes":
			_toggle_tool_palettes_visible()
		"lang_zh_CN":
			EditorI18n.set_locale("zh_CN")
			_set_status_key("EDITOR_STATUS_IDLE")
		"lang_en":
			EditorI18n.set_locale("en")
			_set_status_key("EDITOR_STATUS_IDLE")
		"layer_terrain", "tools_sel_brush", "module_terrain":
			_set_status_key("EDITOR_STATUS_TERRAIN_BRUSH")
		"help_about":
			_set_status_key("EDITOR_STATUS_ABOUT", [EditorI18n.t("WESTRING_APPNAME")])
		_:
			_set_status_key("EDITOR_STATUS_NOT_IMPLEMENTED", [String(action_id)])


func _spawn_tool_palette(kind: int) -> void:
	var win = ToolPaletteScene.instantiate()
	win.setup_we_data(_we_data)
	add_child(win)
	win.set_palette_kind(kind)
	win.set_brush_settings(_brush_size, _brush_shape)
	win.set_apply_texture(_apply_texture)
	win.set_cliff_settings(_apply_cliff, _cliff_tool_id, _cliff_type_index)
	win.tile_selected.connect(_on_tile_selected)
	win.brush_settings_changed.connect(_on_brush_settings_changed)
	win.apply_texture_changed.connect(_on_apply_texture_changed)
	win.cliff_settings_changed.connect(_on_cliff_settings_changed)
	win.closed_by_user.connect(_on_tool_palette_closed.bind(win))
	win.tree_exiting.connect(_on_tool_palette_exiting.bind(win))
	_tool_palettes.append(win)
	win.rebuild_terrain(_doc, _map.get_tiles())
	_palettes_visible = true
	_menu.set_show_palettes_checked(true)
	var offset := _palette_spawn_index * 28
	_palette_spawn_index += 1
	win.position = Vector2i(24 + offset, 72 + offset)
	win.always_on_top = true
	win.unfocusable = true
	win.transient = false
	win.visible = true
	win.show()


func _on_brush_settings_changed(size: int, shape: int) -> void:
	_brush_size = size
	_brush_shape = 0 if shape == 0 else 1
	_brush.set_brush_settings(_brush_size, _brush_shape)
	_brush_size = int(_brush.brush_size)
	for win in _tool_palettes:
		if is_instance_valid(win):
			win.set_brush_settings(_brush_size, _brush_shape)


func _on_apply_texture_changed(enabled: bool) -> void:
	_apply_texture = enabled
	_brush.apply_texture = enabled
	for win in _tool_palettes:
		if is_instance_valid(win):
			win.set_apply_texture(enabled)


func _on_cliff_settings_changed(p_apply: bool, tool_id: String, type_idx: int) -> void:
	_apply_cliff = p_apply
	_cliff_tool_id = tool_id if not tool_id.is_empty() else "2"
	_cliff_type_index = maxi(type_idx, 0)
	_doc.brush_cliff_type = _cliff_type_index
	_brush.set_cliff_settings(_apply_cliff, _cliff_tool_id, _cliff_type_index)
	for win in _tool_palettes:
		if is_instance_valid(win):
			win.set_cliff_settings(_apply_cliff, _cliff_tool_id, _cliff_type_index)


func _toggle_tool_palettes_visible() -> void:
	_palettes_visible = not _palettes_visible
	for win in _tool_palettes:
		if is_instance_valid(win):
			win.visible = _palettes_visible
	_menu.set_show_palettes_checked(_palettes_visible)


func _on_tool_palette_closed(win) -> void:
	_tool_palettes.erase(win)


func _on_tool_palette_exiting(win) -> void:
	_tool_palettes.erase(win)


func _refresh_all_tool_palettes() -> void:
	var tiles: Wc3TerrainTiles = _map.get_tiles()
	for win in _tool_palettes:
		if is_instance_valid(win):
			win.rebuild_terrain(_doc, tiles)


func _set_view_grid(level: int) -> void:
	_map.set_view_grid_level(level)
	_menu.set_grid_level_checked(level)
	var key := "WESTRING_MENU_GRID_NONE"
	match level:
		MapLoader.ViewGridLevel.LARGE:
			key = "WESTRING_MENU_GRID_LARGE"
		MapLoader.ViewGridLevel.MEDIUM:
			key = "WESTRING_MENU_GRID_MEDIUM"
		MapLoader.ViewGridLevel.SMALL:
			key = "WESTRING_MENU_GRID_SMALL"
	_set_status_key("EDITOR_STATUS_GRID", [EditorI18n.t(key)])


func _show_new_map_dialog() -> void:
	# embed_subwindows=false 时为原生窗口；勿挂 transient 到 Node3D
	_new_map_dialog.transient = false
	_new_map_dialog.exclusive = true
	_new_map_dialog.popup_centered()
	_new_map_dialog.grab_focus()


func _on_new_map_confirmed(options: Dictionary) -> void:
	_doc.create_from_options(options)
	await _apply_document(true)
	_set_status_key(
		"EDITOR_STATUS_MAP_CREATED",
		[
			int(options.get("width", 0)),
			int(options.get("height", 0)),
			str(options.get("main_tileset_name", "")),
		]
	)


func _on_open_lost_temple() -> void:
	var err: int = _doc.load_from_map_dir(MapDocumentScript.DEFAULT_MAP_DIR)
	if err != OK:
		_set_status_key("EDITOR_STATUS_OPEN_FAILED")
		return
	await _apply_document(true)
	_set_status_key("EDITOR_STATUS_OPENED_LOST_TEMPLE")


func _on_save() -> void:
	var err: int = _doc.save_json()
	if err != OK:
		_set_status_key("EDITOR_STATUS_SAVE_FAILED")
		return
	_set_status_key("EDITOR_STATUS_SAVED")


func _on_tile_selected(index: int) -> void:
	_doc.brush_tile_index = index
	_refresh_brush_label()
	_palette.rebuild(_doc, _map.get_tiles())
	_refresh_all_tool_palettes()


func _on_tile_hovered(tile: Vector2i) -> void:
	_hover_tile = tile
	_hover.text = EditorI18n.t("EDITOR_HOVER_CELL", [tile.x, tile.y])


func _on_dirty_changed(dirty: bool) -> void:
	_toolbar.set_dirty(dirty)


func _on_brush_rebuild() -> void:
	if _rebuilding:
		return
	_rebuilding = true
	if bool(_brush.cliff_dirty):
		_brush.cliff_dirty = false
		_map.rebuild_terrain_cliffs_water(_doc.hf, _doc.info)
	else:
		_map.rebuild_terrain_only(_doc.hf, _doc.info)
	_rebuilding = false


func _apply_document(full_reload: bool) -> void:
	_palette.rebuild(_doc, _map.get_tiles())
	_refresh_all_tool_palettes()
	_refresh_brush_label()
	_toolbar.set_dirty(_doc.is_dirty())
	_brush.setup(_doc, _cam_rig.get_camera(), get_world_3d())
	_brush.set_brush_settings(_brush_size, _brush_shape)
	_brush.apply_texture = _apply_texture
	_brush.set_cliff_settings(_apply_cliff, _cliff_tool_id, _cliff_type_index)
	if full_reload:
		var dir: String = _doc.map_dir if not _doc.map_dir.is_empty() else "res://"
		await _map.reload_from_hf(_doc.hf, _doc.info, dir)
	else:
		_map.rebuild_terrain_cliffs_water(_doc.hf, _doc.info)
	_cam_rig.focus_map_extent(_doc.map_size())


func _refresh_brush_label() -> void:
	var tid: String = str(_doc.brush_tile_id())
	var label: String = EditorI18n.tile_display_name(_map.get_tiles(), tid)
	if label.is_empty():
		label = tid
	_toolbar.set_brush_text(label)


func _set_status_key(key: String, args: Array = []) -> void:
	_status_key = key
	_status_args = args
	_set_status(EditorI18n.t(key, args))


func _set_status(text: String) -> void:
	_status.text = text
	print("Editor: %s" % text)
