class_name MapEditor
extends Node

## 编辑器总管：Document、命令历史、菜单/面板、笔刷、MapRoot 重建。
## 场景位置：editor_main.tscn 的直接子节点；世界节点经 @export 注入。


const MapDocumentScript := preload("res://editor/scripts/map_document.gd")
const DataScript := preload("res://editor/scripts/ui/world_edit_data.gd")
const ToolPaletteScene := preload("res://editor/scripts/ui/tool_palette_window.tscn")
const ToolPaletteWindowScript := preload("res://editor/scripts/ui/tool_palette_window.gd")

@export var map_root: MapLoader
@export var camera_rig: Node3D
@export var brush: Node3D
@export var new_map_dialog: Window
@export var menu: Node
@export var toolbar: Node
@export var palette: Node
@export var status_label: Label
@export var hover_label: Label

var _doc
var _history: EditorCommandHistory = EditorCommandHistory.new()
var _rebuilding: bool = false
var _we_data
var _hover_tile: Vector2i = Vector2i(-1, -1)
var _status_key: String = "EDITOR_STATUS_IDLE"
var _status_args: Array = []
var _tool_palettes: Array = []
var _palettes_visible: bool = true
var _palette_spawn_index: int = 0
var _brush_size: int = 1
var _brush_shape: int = 0
var _apply_texture: bool = true
var _apply_cliff: bool = false ## 地面阶段默认关：避免崖 sync 干扰地表笔刷；面板可再打开
var _cliff_tool_id: String = "2"
var _cliff_type_index: int = 0


func _ready() -> void:
	_resolve_exports()
	if map_root == null:
		push_error("MapEditor: 未绑定 map_root")
		return
	_doc = MapDocumentScript.new()
	_history.bind_document(_doc)
	_history.command_applied.connect(_on_command_applied)
	_we_data = DataScript.load_default()

	map_root.auto_load_on_ready = false
	map_root.build_water = true
	map_root.build_cliffs = true
	map_root.place_doodads = false
	map_root.place_units = false
	map_root.show_pathing_debug_grid = false
	map_root.build_terrain_collision = true
	map_root.status_path = NodePath("")

	if menu != null and menu.has_signal("action_triggered"):
		menu.action_triggered.connect(_on_menu_action)
	if palette != null and palette.has_signal("tile_selected"):
		palette.tile_selected.connect(_on_tile_selected)
	if brush != null:
		if brush.has_signal("tile_hovered"):
			brush.tile_hovered.connect(_on_tile_hovered)
		if brush.has_signal("rebuild_requested"):
			brush.rebuild_requested.connect(_on_brush_rebuild)
		if brush.has_signal("ramp_feedback"):
			brush.ramp_feedback.connect(_on_ramp_feedback)
	EditorI18n.locale_changed.connect(_on_locale_changed)
	_apply_chrome_locale()

	await get_tree().process_frame
	if new_map_dialog != null:
		new_map_dialog.setup(map_root.get_tiles(), map_root.get_cliff_catalog(), null, _we_data)
		if not new_map_dialog.confirmed.is_connected(_on_new_map_confirmed):
			new_map_dialog.confirmed.connect(_on_new_map_confirmed)
	await _startup_new_map()
	_set_view_grid(EditorSettingsStore.load_view_grid_level())
	if menu != null and menu.has_method("set_ramp_debug_checked") and map_root != null:
		menu.set_ramp_debug_checked(map_root.get_show_ramp_debug())
	_spawn_tool_palette(ToolPaletteWindowScript.PaletteKind.TERRAIN)
	if not _history.changed.is_connected(_refresh_undo_redo_menu):
		_history.changed.connect(_refresh_undo_redo_menu)
	_refresh_undo_redo_menu()


func get_history() -> EditorCommandHistory:
	return _history


func get_document():
	return _doc


## 手写 tscn / 未拖引用时按兄弟节点回退。
func _resolve_exports() -> void:
	if map_root == null:
		map_root = get_node_or_null("../MapRoot") as MapLoader
	if camera_rig == null:
		camera_rig = get_node_or_null("../EditorCamera") as Node3D
	if brush == null:
		brush = get_node_or_null("../TerrainBrush") as Node3D
	if new_map_dialog == null:
		new_map_dialog = get_node_or_null("../NewMapDialog") as Window
	if menu == null:
		menu = get_node_or_null("../UI/MenuBarPanel/MenuBar")
	if toolbar == null:
		toolbar = get_node_or_null("../UI/ToolStrip/Toolbar")
	if palette == null:
		palette = get_node_or_null("../UI/SideBar/TilePalette")
	if status_label == null:
		status_label = get_node_or_null("../UI/StatusBar/Status") as Label
	if hover_label == null:
		hover_label = get_node_or_null("../UI/StatusBar/Hover") as Label


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.ctrl_pressed and k.keycode == KEY_Z and not k.shift_pressed:
			_undo()
			get_viewport().set_input_as_handled()
		elif (
			(k.ctrl_pressed and k.keycode == KEY_Y)
			or (k.ctrl_pressed and k.shift_pressed and k.keycode == KEY_Z)
		):
			_redo()
			get_viewport().set_input_as_handled()


func _startup_new_map() -> void:
	var options := _default_new_map_options()
	_doc.create_from_options(options)
	_doc.clear_dirty()
	_history.clear()
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
	var tiles: Wc3TerrainTileCatalog = map_root.get_tiles()
	var cliffs_cat: Wc3CliffCatalog = map_root.get_cliff_catalog()
	var ground: Array = []
	var cliffs: Array = []
	if tiles != null:
		for tid in tiles.tile_ids_for_tileset(letter):
			ground.append(tid)
	if cliffs_cat != null:
		for cid in cliffs_cat.cliff_ids_for_tileset(letter):
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
	if hover_label == null:
		return
	if _hover_tile.x < 0:
		hover_label.text = EditorI18n.t("EDITOR_HOVER_CELL_EMPTY")
	else:
		hover_label.text = EditorI18n.t("EDITOR_HOVER_CELL", [_hover_tile.x, _hover_tile.y])


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
		"edit_undo":
			_undo()
		"edit_redo":
			_redo()
		"view_grid_none":
			_set_view_grid(MapLoader.ViewGridLevel.NONE)
		"view_grid_large":
			_set_view_grid(MapLoader.ViewGridLevel.LARGE)
		"view_grid_medium":
			_set_view_grid(MapLoader.ViewGridLevel.MEDIUM)
		"view_grid_small":
			_set_view_grid(MapLoader.ViewGridLevel.SMALL)
		"view_ramp_debug":
			if map_root != null:
				var on := not map_root.get_show_ramp_debug()
				map_root.set_show_ramp_debug(on)
				if menu != null and menu.has_method("set_ramp_debug_checked"):
					menu.set_ramp_debug_checked(on)
				_set_status("斜坡标记：开" if on else "斜坡标记：关")
		"view_grid", "window_new_palette":
			pass
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


func _undo() -> void:
	var cmd: EditorCommand = _history.undo()
	if cmd == null:
		return
	_set_status("Undo: %s" % cmd.get_label())


func _redo() -> void:
	var cmd: EditorCommand = _history.redo()
	if cmd == null:
		return
	_set_status("Redo: %s" % cmd.get_label())


func _refresh_undo_redo_menu() -> void:
	if menu != null and menu.has_method("set_undo_redo_enabled"):
		menu.set_undo_redo_enabled(_history.can_undo(), _history.can_redo())


func _on_command_applied(cmd: EditorCommand, is_undo: bool, should_rebuild: bool) -> void:
	MapLog.info(
		MapLog.Layer.EDITOR,
		"History",
		"%s rebuild=%s cliff=%s — %s"
		% [
			"undo" if is_undo else "apply",
			should_rebuild,
			cmd.affects_cliffs_water() if cmd else false,
			cmd.get_label() if cmd else "?",
		]
	)
	if not should_rebuild or _rebuilding or map_root == null or _doc == null:
		return
	_rebuilding = true
	if cmd.affects_cliffs_water():
		map_root.rebuild_terrain_cliffs_water(_doc.as_build_dict(), _doc.info)
	else:
		map_root.rebuild_terrain_only(_doc.as_build_dict(), _doc.info)
	_rebuilding = false


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
	if win.has_signal("edit_undo_requested"):
		win.edit_undo_requested.connect(_undo)
	if win.has_signal("edit_redo_requested"):
		win.edit_redo_requested.connect(_redo)
	_tool_palettes.append(win)
	win.rebuild_terrain(_doc, map_root.get_tiles(), map_root.get_cliff_catalog())
	_palettes_visible = true
	if menu != null and menu.has_method("set_show_palettes_checked"):
		menu.set_show_palettes_checked(true)
	var offset := _palette_spawn_index * 28
	_palette_spawn_index += 1
	# 相对主编辑窗口定位；transient=true 时引擎沿父节点 viewport 自动绑定主窗
	var main_win := get_viewport().get_window()
	win.transient = true
	if main_win != null:
		win.position = main_win.position + Vector2i(24 + offset, 72 + offset)
	else:
		win.position = Vector2i(24 + offset, 72 + offset)
	win.transparent = false
	win.unfocusable = false
	win.always_on_top = true
	win.visible = true
	win.show()


func _on_brush_settings_changed(size: int, shape: int) -> void:
	_brush_size = size
	_brush_shape = 0 if shape == 0 else 1
	if brush != null and brush.has_method("set_brush_settings"):
		brush.set_brush_settings(_brush_size, _brush_shape)
		_brush_size = int(brush.brush_size)
	for win in _tool_palettes:
		if is_instance_valid(win):
			win.set_brush_settings(_brush_size, _brush_shape)


func _on_apply_texture_changed(enabled: bool) -> void:
	_apply_texture = enabled
	if brush != null:
		brush.apply_texture = enabled
	for win in _tool_palettes:
		if is_instance_valid(win):
			win.set_apply_texture(enabled)


func _on_cliff_settings_changed(p_apply: bool, tool_id: String, type_idx: int) -> void:
	_apply_cliff = p_apply
	_cliff_tool_id = tool_id if not tool_id.is_empty() else "2"
	_cliff_type_index = maxi(type_idx, 0)
	_doc.brush_cliff_type = _cliff_type_index
	if brush != null and brush.has_method("set_cliff_settings"):
		brush.set_cliff_settings(_apply_cliff, _cliff_tool_id, _cliff_type_index)
	for win in _tool_palettes:
		if is_instance_valid(win):
			win.set_cliff_settings(_apply_cliff, _cliff_tool_id, _cliff_type_index)


func _toggle_tool_palettes_visible() -> void:
	_palettes_visible = not _palettes_visible
	for win in _tool_palettes:
		if is_instance_valid(win):
			win.visible = _palettes_visible
	if menu != null and menu.has_method("set_show_palettes_checked"):
		menu.set_show_palettes_checked(_palettes_visible)


func _on_tool_palette_closed(win) -> void:
	_tool_palettes.erase(win)


func _on_tool_palette_exiting(win) -> void:
	_tool_palettes.erase(win)


func _refresh_all_tool_palettes() -> void:
	var tiles: Wc3TerrainTileCatalog = map_root.get_tiles()
	var cliffs_cat: Wc3CliffCatalog = map_root.get_cliff_catalog()
	for win in _tool_palettes:
		if is_instance_valid(win):
			win.rebuild_terrain(_doc, tiles, cliffs_cat)


func _set_view_grid(level: int) -> void:
	map_root.set_view_grid_level(level)
	if menu != null and menu.has_method("set_grid_level_checked"):
		menu.set_grid_level_checked(level)
	EditorSettingsStore.save_view_grid_level(level)
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
	if new_map_dialog == null:
		return
	new_map_dialog.transient = false
	new_map_dialog.exclusive = true
	new_map_dialog.popup_centered()
	new_map_dialog.grab_focus()


func _on_new_map_confirmed(options: Dictionary) -> void:
	_doc.create_from_options(options)
	_history.clear()
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
	_history.clear()
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
	if palette != null and palette.has_method("rebuild"):
		palette.rebuild(_doc, map_root.get_tiles())
	_refresh_all_tool_palettes()


func _on_tile_hovered(tile: Vector2i) -> void:
	_hover_tile = tile
	if hover_label != null:
		hover_label.text = EditorI18n.t("EDITOR_HOVER_CELL", [tile.x, tile.y])


func _on_ramp_feedback(message: String) -> void:
	if message.is_empty():
		return
	_set_status(message)


func _on_dirty_changed(dirty: bool) -> void:
	if toolbar != null and toolbar.has_method("set_dirty"):
		toolbar.set_dirty(dirty)


func _on_brush_rebuild() -> void:
	if _rebuilding:
		MapLog.debug(MapLog.Layer.EDITOR, "Brush", "rebuild skipped (busy)")
		return
	_rebuilding = true
	var cliff := brush != null and bool(brush.get("cliff_dirty"))
	MapLog.info(
		MapLog.Layer.EDITOR,
		"Brush",
		"rebuild cliff_path=%s" % cliff
	)
	if cliff:
		brush.cliff_dirty = false
		map_root.rebuild_terrain_cliffs_water(_doc.as_build_dict(), _doc.info)
	else:
		map_root.rebuild_terrain_only(_doc.as_build_dict(), _doc.info)
	_rebuilding = false


func _apply_document(full_reload: bool) -> void:
	if palette != null and palette.has_method("rebuild"):
		palette.rebuild(_doc, map_root.get_tiles())
	_refresh_all_tool_palettes()
	_refresh_brush_label()
	if toolbar != null and toolbar.has_method("set_dirty"):
		toolbar.set_dirty(_doc.is_dirty())
	if brush != null and brush.has_method("setup"):
		var cam: Camera3D = null
		if camera_rig != null and camera_rig.has_method("get_camera"):
			cam = camera_rig.get_camera()
		brush.setup(_doc, cam, map_root.get_world_3d(), _history)
		brush.set_brush_settings(_brush_size, _brush_shape)
		brush.apply_texture = _apply_texture
		brush.set_cliff_settings(_apply_cliff, _cliff_tool_id, _cliff_type_index)
	if full_reload:
		var dir: String = _doc.map_dir if not _doc.map_dir.is_empty() else "res://"
		await map_root.reload_from_hf(_doc.as_build_dict(), _doc.info, dir)
	else:
		map_root.rebuild_terrain_cliffs_water(_doc.as_build_dict(), _doc.info)
	if camera_rig != null and camera_rig.has_method("focus_map_extent"):
		camera_rig.focus_map_extent(_doc.map_size())


func _refresh_brush_label() -> void:
	if toolbar == null or not toolbar.has_method("set_brush_text"):
		return
	var tid: String = str(_doc.brush_tile_id())
	var label: String = EditorI18n.tile_display_name(map_root.get_tiles(), tid)
	if label.is_empty():
		label = tid
	toolbar.set_brush_text(label)


func _set_status_key(key: String, args: Array = []) -> void:
	_status_key = key
	_status_args = args
	_set_status(EditorI18n.t(key, args))


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text
	print("Editor: %s" % text)
