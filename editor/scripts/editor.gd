class_name MapEditor
extends Node

## 编辑器总管：Document、命令历史、菜单/面板、笔刷、MapRoot 重建。
## 场景位置：editor_main.tscn 的直接子节点；世界节点经 @export 注入。


const MapDocumentScript := preload("res://editor/scripts/map_document.gd")
const DataScript := preload("res://editor/ui/world_edit_data.gd")
const ToolPaletteScene := preload("res://editor/ui/tool_palette_window.tscn")
const ToolPaletteWindowScript := preload("res://editor/ui/tool_palette_window.gd")
const InspectWindowScene := preload("res://editor/ui/editor_inspect_window.tscn")
const UnitPropertiesScene := preload("res://editor/ui/unit_properties_dialog.tscn")
## 显式 preload，避免热重载时 class_name 尚未注册导致 Marquee* 解析失败
const _MarqueeSelectionScript := preload("res://scripts/shared/selection/marquee_selection.gd")
const _MarqueeOverlayScript := preload("res://scripts/shared/selection/marquee_overlay.gd")

@export var map_root: MapLoader
@export var camera_rig: Node3D
@export var brush: Node3D
@export var doodad_brush: Node3D
@export var unit_brush: Node3D
@export var input_router: Node
@export var new_map_dialog: Window
@export var open_map_dialog: Window
@export var menu: Node
@export var toolbar: Node
@export var palette: Node
@export var status_bar: Node
@export var status_label: Label
@export var hover_label: Label

var _doc
var _history: EditorCommandHistory = EditorCommandHistory.new()
var _rebuilding: bool = false
## 撤销/重做时若正赶上笔刷重建，延后补一次表现刷新
var _pending_history_rebuild: bool = false
var _pending_history_cliff: bool = false
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
var _special_texture: int = 0 ## ToolPaletteWindow.SpecialTexture
var _inspect_window: Window
var _unit_props_dialog: Window
var _marquee = null
var _marquee_overlay = null
var _brush_mode: String = "terrain" ## terrain | doodad | unit
var _brush_doodad_id: String = ""
var _brush_doodad_name: String = ""
var _brush_doodad_variation: int = 0
var _brush_doodad_num_var: int = 1
var _brush_doodad_angle: float = 270.0
var _brush_doodad_scale: float = 1.0
var _brush_doodad_random: bool = true
var _brush_doodad_rand_rotation: bool = true
var _brush_doodad_rand_scale_sym: bool = false
var _brush_doodad_rand_scale_z: bool = false
var _brush_doodad_rand_scale_xy: bool = false
var _brush_unit_id: String = ""
var _brush_unit_name: String = ""
var _brush_unit_owner: int = 0
var _brush_unit_angle: float = 270.0
var _brush_unit_random_rotation: bool = true
var _doodads_present_built: bool = false
var _units_present_built: bool = false
var _units_loading: bool = false
var _units_batch_wired: bool = false


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
		if brush.has_signal("brush_settings_changed"):
			brush.brush_settings_changed.connect(_on_brush_settings_changed)
	if doodad_brush != null:
		if doodad_brush.has_signal("rebuild_requested"):
			doodad_brush.rebuild_requested.connect(_on_doodad_brush_rebuild)
		if doodad_brush.has_signal("brush_settings_changed"):
			doodad_brush.brush_settings_changed.connect(_on_brush_settings_changed)
		if doodad_brush.has_signal("placed"):
			doodad_brush.placed.connect(_on_doodads_placed)
		if doodad_brush.has_signal("facing_changed"):
			doodad_brush.facing_changed.connect(_on_doodad_facing_changed)
		if doodad_brush.has_signal("selection_changed"):
			doodad_brush.selection_changed.connect(_on_doodad_map_selection_changed)
		if doodad_brush.has_signal("deleted"):
			doodad_brush.deleted.connect(_on_doodads_deleted)
		if doodad_brush.has_signal("palette_cleared"):
			doodad_brush.palette_cleared.connect(_on_doodad_palette_cleared)
	if unit_brush != null:
		if unit_brush.has_signal("rebuild_requested"):
			unit_brush.rebuild_requested.connect(_on_unit_brush_rebuild)
		if unit_brush.has_signal("placed"):
			unit_brush.placed.connect(_on_units_placed)
		if unit_brush.has_signal("facing_changed"):
			unit_brush.facing_changed.connect(_on_unit_facing_changed)
		if unit_brush.has_signal("selection_changed"):
			unit_brush.selection_changed.connect(_on_unit_map_selection_changed)
		if unit_brush.has_signal("deleted"):
			unit_brush.deleted.connect(_on_units_deleted)
		if unit_brush.has_signal("palette_cleared"):
			unit_brush.palette_cleared.connect(_on_unit_palette_cleared)
		if unit_brush.has_signal("properties_requested"):
			unit_brush.properties_requested.connect(_on_unit_properties_requested)
	EditorI18n.locale_changed.connect(_on_locale_changed)
	_apply_chrome_locale()

	await get_tree().process_frame
	if new_map_dialog != null:
		new_map_dialog.setup(map_root.get_tiles(), map_root.get_cliff_catalog(), null, _we_data)
		if not new_map_dialog.confirmed.is_connected(_on_new_map_confirmed):
			new_map_dialog.confirmed.connect(_on_new_map_confirmed)
	if open_map_dialog != null:
		open_map_dialog.setup()
		if not open_map_dialog.confirmed.is_connected(_on_open_map_confirmed):
			open_map_dialog.confirmed.connect(_on_open_map_confirmed)
	await _startup_new_map()
	_set_view_grid(EditorSettingsStore.load_view_grid_level())
	if menu != null and menu.has_method("set_ramp_debug_checked") and map_root != null:
		menu.set_ramp_debug_checked(map_root.get_show_ramp_debug())
	_spawn_tool_palette(ToolPaletteWindowScript.PaletteKind.TERRAIN)
	_ensure_inspect_window()
	if not _history.changed.is_connected(_refresh_undo_redo_menu):
		_history.changed.connect(_refresh_undo_redo_menu)
	_refresh_undo_redo_menu()
	_refresh_hud_brush()
	_refresh_hud_props()


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
	if doodad_brush == null:
		doodad_brush = get_node_or_null("../DoodadBrush") as Node3D
	if unit_brush == null:
		unit_brush = get_node_or_null("../UnitBrush") as Node3D
	if input_router == null:
		input_router = get_node_or_null("../EditorInputRouter")
	if new_map_dialog == null:
		new_map_dialog = get_node_or_null("../NewMapDialog") as Window
	if open_map_dialog == null:
		open_map_dialog = get_node_or_null("../OpenMapDialog") as Window
	if menu == null:
		menu = get_node_or_null("../UI/MenuBarPanel/MenuBar")
	if toolbar == null:
		toolbar = get_node_or_null("../UI/ToolStrip/Toolbar")
	if palette == null:
		palette = get_node_or_null("../UI/SideBar/TilePalette")
	if status_bar == null:
		status_bar = get_node_or_null("../UI/StatusBar")
	if status_label == null:
		status_label = get_node_or_null("../UI/StatusBar/Margin/Row/StatusChip/StatusValue") as Label
	if hover_label == null:
		hover_label = get_node_or_null("../UI/StatusBar/Margin/Row/CoordsChip/CoordsValue") as Label


func _unhandled_input(_event: InputEvent) -> void:
	# 撤销/重做与鼠标键盘路由改由 EditorInputRouter 处理
	pass


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
	_refresh_hud_brush()
	_refresh_hud_props()
	_set_status_key(_status_key, _status_args)


func _apply_chrome_locale() -> void:
	var coords := EditorI18n.t("EDITOR_HOVER_CELL_EMPTY")
	if _hover_tile.x >= 0:
		coords = EditorI18n.t("EDITOR_HOVER_CELL", [_hover_tile.x, _hover_tile.y])
	if status_bar != null and status_bar.has_method("set_coords_text"):
		status_bar.set_coords_text(coords)
	elif hover_label != null:
		hover_label.text = coords


func _process(_delta: float) -> void:
	if _inspect_window != null and is_instance_valid(_inspect_window) and _inspect_window.visible:
		_update_inspect_viewport_rect()


func _on_menu_action(action_id: StringName) -> void:
	match String(action_id):
		"file_new":
			_show_new_map_dialog()
		"file_open":
			_show_open_map_dialog()
		"file_save":
			_on_save()
		"file_export_minimap":
			_on_export_minimap()
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
				var on: bool = not map_root.get_show_ramp_debug()
				map_root.set_show_ramp_debug(on)
				if menu != null and menu.has_method("set_ramp_debug_checked"):
					menu.set_ramp_debug_checked(on)
				_set_status("斜坡标记：开" if on else "斜坡标记：关")
		"view_pathing":
			_toggle_pathing_ground()
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
		"window_minimap", "window_previewer":
			_ensure_inspect_window(true, true)
		"lang_zh_CN":
			EditorI18n.set_locale("zh_CN")
			_set_status_key("EDITOR_STATUS_IDLE")
		"lang_en":
			EditorI18n.set_locale("en")
			_set_status_key("EDITOR_STATUS_IDLE")
		"layer_terrain", "tools_sel_brush", "module_terrain":
			_brush_mode = "terrain"
			_sync_active_brush()
			_refresh_hud_brush()
			_set_status_key("EDITOR_STATUS_TERRAIN_BRUSH")
		"layer_doodads", "module_doodads":
			_brush_mode = "doodad"
			_sync_active_brush()
			_spawn_tool_palette(ToolPaletteWindowScript.PaletteKind.DOODADS)
			_ensure_inspect_window(true, false)
			_restore_inspect_preview_for_brush()
			_refresh_hud_brush()
			_set_status_key("EDITOR_STATUS_DOODAD_BRUSH")
		"layer_units", "module_units":
			_brush_mode = "unit"
			_sync_active_brush()
			_spawn_tool_palette(ToolPaletteWindowScript.PaletteKind.UNITS)
			_ensure_inspect_window(true, false)
			_restore_inspect_preview_for_brush()
			_refresh_hud_brush()
			_set_status_key("EDITOR_STATUS_UNIT_BRUSH")
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
	AppLog.info(
		AppLog.Layer.EDITOR,
		"History",
		"%s rebuild=%s cliff=%s doodad=%s unit=%s — %s"
		% [
			"undo" if is_undo else "apply",
			should_rebuild,
			cmd.affects_cliffs_water() if cmd else false,
			cmd.affects_doodads() if cmd else false,
			cmd.affects_units() if cmd else false,
			cmd.get_label() if cmd else "?",
		]
	)
	if cmd != null and cmd.affects_doodads():
		# record() 已落地、should_rebuild=false：勿清选中（旋转/拖动会立刻丢选）
		if should_rebuild:
			if doodad_brush != null and doodad_brush.has_method("clear_selection"):
				doodad_brush.clear_selection()
			_rebuild_doodads_present()
		_refresh_hud_props()
		return
	if cmd != null and cmd.affects_units():
		if should_rebuild:
			if unit_brush != null and unit_brush.has_method("clear_selection"):
				unit_brush.clear_selection()
			_rebuild_units_present()
		_refresh_hud_props()
		return
	if not should_rebuild or map_root == null or _doc == null:
		return
	var cliff: bool = cmd.affects_cliffs_water() if cmd else false
	if _rebuilding:
		_pending_history_rebuild = true
		_pending_history_cliff = _pending_history_cliff or cliff
		AppLog.debug(AppLog.Layer.EDITOR, "History", "rebuild deferred (busy)")
		return
	_run_history_rebuild(cliff)


func _run_history_rebuild(cliff: bool) -> void:
	if map_root == null or _doc == null:
		return
	_rebuilding = true
	if cliff:
		map_root.rebuild_terrain_cliffs_water(_doc.as_build_dict(), _doc.info)
	else:
		map_root.rebuild_terrain_only(_doc.as_build_dict(), _doc.info)
	_rebuilding = false
	_refresh_inspect_minimap_live()
	if _pending_history_rebuild:
		var again_cliff: bool = _pending_history_cliff
		_pending_history_rebuild = false
		_pending_history_cliff = false
		call_deferred("_run_history_rebuild", again_cliff)


func _spawn_tool_palette(kind: int) -> void:
	var win = ToolPaletteScene.instantiate()
	win.setup_we_data(_we_data)
	add_child(win)
	win.set_palette_kind(kind)
	win.set_brush_settings(_brush_size, _brush_shape)
	win.set_apply_texture(_apply_texture)
	win.set_cliff_settings(_apply_cliff, _cliff_tool_id, _cliff_type_index)
	if win.has_method("set_special_texture"):
		win.set_special_texture(_special_texture)
	win.tile_selected.connect(_on_tile_selected)
	win.brush_settings_changed.connect(_on_brush_settings_changed)
	win.apply_texture_changed.connect(_on_apply_texture_changed)
	win.cliff_settings_changed.connect(_on_cliff_settings_changed)
	if win.has_signal("special_texture_changed"):
		win.special_texture_changed.connect(_on_special_texture_changed)
	if win.has_signal("doodad_selected"):
		win.doodad_selected.connect(_on_doodad_selected)
	if win.has_signal("unit_selected"):
		win.unit_selected.connect(_on_unit_selected)
	if win.has_signal("unit_owner_changed"):
		win.unit_owner_changed.connect(_on_unit_owner_changed)
	if win.has_signal("unit_icons_ready"):
		win.unit_icons_ready.connect(_on_unit_icons_ready)
	if win.has_signal("doodad_place_random_changed"):
		win.doodad_place_random_changed.connect(_on_doodad_place_random_changed)
		if win.has_method("set_doodad_place_random"):
			win.set_doodad_place_random(
				_brush_doodad_rand_rotation,
				_brush_doodad_rand_scale_sym,
				_brush_doodad_rand_scale_z,
				_brush_doodad_rand_scale_xy,
			)
	if win.has_signal("palette_kind_changed"):
		win.palette_kind_changed.connect(_on_palette_kind_changed)
	win.closed_by_user.connect(_on_tool_palette_closed.bind(win))
	win.tree_exiting.connect(_on_tool_palette_exiting.bind(win))
	if win.has_signal("edit_undo_requested"):
		win.edit_undo_requested.connect(_undo)
	if win.has_signal("edit_redo_requested"):
		win.edit_redo_requested.connect(_redo)
	if win.has_signal("escape_pressed"):
		win.escape_pressed.connect(_on_palette_escape)
	_tool_palettes.append(win)
	win.set_id_catalog(map_root.get_id_catalog())
	if win.has_method("set_map_tileset"):
		win.set_map_tileset(_current_map_tileset())
	win.rebuild_terrain(_doc, map_root.get_tiles(), map_root.get_cliff_catalog())
	_palettes_visible = true
	if menu != null and menu.has_method("set_show_palettes_checked"):
		menu.set_show_palettes_checked(true)
	var offset := _palette_spawn_index * 28
	_palette_spawn_index += 1
	# Windows：always_on_top 与 transient 互斥。工具面板要压在主编辑窗上 → 只用置顶。
	var main_win := get_viewport().get_window()
	win.transient = false
	win.always_on_top = true
	if main_win != null:
		win.position = main_win.position + Vector2i(24 + offset, 72 + offset)
	else:
		win.position = Vector2i(24 + offset, 72 + offset)
	win.transparent = false
	win.unfocusable = false
	win.visible = true
	win.show()
	win.grab_focus()
	if kind == ToolPaletteWindowScript.PaletteKind.DOODADS:
		_brush_mode = "doodad"
		_sync_active_brush()
		_ensure_inspect_window(true, false)
		_restore_inspect_preview_for_brush()
		_refresh_hud_brush()
	elif kind == ToolPaletteWindowScript.PaletteKind.UNITS:
		_brush_mode = "unit"
		_sync_active_brush()
		_ensure_inspect_window(true, false)
		_restore_inspect_preview_for_brush()
		_refresh_hud_brush()


func _on_palette_kind_changed(kind: int) -> void:
	# 工具面板顶部下拉切换类型 → 同步笔刷层（否则仍显示地形绿格）
	match kind:
		ToolPaletteWindowScript.PaletteKind.DOODADS:
			_brush_mode = "doodad"
		ToolPaletteWindowScript.PaletteKind.UNITS:
			_brush_mode = "unit"
		_:
			_brush_mode = "terrain"
	_sync_active_brush()
	_ensure_inspect_window(true, false)
	_restore_inspect_preview_for_brush()
	_refresh_hud_brush()
	_refresh_hud_props()
	match _brush_mode:
		"doodad":
			_set_status_key("EDITOR_STATUS_DOODAD_BRUSH")
		"unit":
			_set_status_key("EDITOR_STATUS_UNIT_BRUSH")
		_:
			_set_status_key("EDITOR_STATUS_TERRAIN_BRUSH")


func _on_brush_settings_changed(size: int, shape: int) -> void:
	_brush_size = size
	_brush_shape = 0 if shape == 0 else 1
	if brush != null and brush.has_method("set_brush_settings"):
		brush.set_brush_settings(_brush_size, _brush_shape)
		_brush_size = int(brush.brush_size)
	if doodad_brush != null and doodad_brush.has_method("set_brush_settings"):
		doodad_brush.set_brush_settings(_brush_size, _brush_shape)
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


func _on_special_texture_changed(kind: int) -> void:
	_special_texture = clampi(kind, 0, 3)
	if brush != null and brush.has_method("set_special_texture"):
		brush.set_special_texture(_special_texture)
	for win in _tool_palettes:
		if is_instance_valid(win) and win.has_method("set_special_texture"):
			win.set_special_texture(_special_texture)


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
	var ids: Wc3IdCatalog = map_root.get_id_catalog()
	var ts := _current_map_tileset()
	for win in _tool_palettes:
		if is_instance_valid(win):
			if win.has_method("set_id_catalog"):
				win.set_id_catalog(ids)
			if win.has_method("set_map_tileset"):
				win.set_map_tileset(ts)
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


func _show_open_map_dialog() -> void:
	if open_map_dialog == null:
		return
	open_map_dialog.setup()
	open_map_dialog.transient = false
	open_map_dialog.exclusive = true
	open_map_dialog.popup_centered()
	open_map_dialog.grab_focus()


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


func _on_open_map_confirmed(entry: Dictionary) -> void:
	var map_dir: String = str(entry.get("dir", ""))
	var display_name: String = str(entry.get("name", map_dir.get_file()))
	var err: int = _doc.load_from_map_dir(map_dir)
	if err != OK:
		_set_status_key("EDITOR_STATUS_OPEN_FAILED", [display_name])
		return
	_history.clear()
	await _apply_document(true)
	_set_status_key("EDITOR_STATUS_OPENED_MAP", [display_name])


func _on_save() -> void:
	var err: int = _doc.save_json()
	if err != OK:
		_set_status_key("EDITOR_STATUS_SAVE_FAILED")
		return
	# 始终强制实时光栅后再 bake，避免「游戏预览」模式下把旧 PNG 写回盘
	var bake_err: Error = _bake_war3map_map(true)
	if bake_err != OK:
		_set_status("地形已保存，但 war3mapMap.png 导出失败")
		return
	_set_status_key("EDITOR_STATUS_SAVED")


func _on_export_minimap() -> void:
	if _doc == null or _doc.heightfield == null:
		_set_status_key("EDITOR_STATUS_SAVE_FAILED")
		return
	var err: Error = _bake_war3map_map(true)
	if err != OK:
		_set_status_key("EDITOR_STATUS_SAVE_FAILED")
		return
	_set_status("已导出 war3mapMap.png")


## 将当前实时光栅 bake 为 map_dir/war3mapMap.png（256 Nearest）。
func _bake_war3map_map(force_live: bool = false) -> Error:
	if _doc == null or _doc.map_dir.is_empty():
		return ERR_INVALID_PARAMETER
	var img: Image = null
	if not force_live and _inspect_window != null and _inspect_window.has_method("get_minimap_image"):
		img = _inspect_window.get_minimap_image()
	if img == null:
		var tiles: Wc3TerrainTileCatalog = map_root.get_tiles() if map_root != null else null
		var cliffs: Wc3CliffCatalog = map_root.get_cliff_catalog() if map_root != null else null
		img = MapMinimapRaster.rasterize_from(_doc.heightfield, tiles, cliffs)
	if img == null:
		return ERR_INVALID_DATA
	var path: String = _doc.map_dir.path_join("war3mapMap.png")
	return MapMinimapRaster.bake_war3map_png(img, path)


func _on_tile_selected(index: int) -> void:
	_brush_mode = "terrain"
	_sync_active_brush()
	_doc.brush_tile_index = index
	_refresh_brush_label()
	_refresh_hud_brush()
	_refresh_hud_props()
	if palette != null and palette.has_method("rebuild"):
		palette.rebuild(_doc, map_root.get_tiles())
	_refresh_all_tool_palettes()


func _on_doodad_selected(type_id: String, info: Dictionary) -> void:
	_brush_mode = "doodad"
	_brush_doodad_id = type_id
	_brush_doodad_name = str(info.get("name", type_id))
	_brush_doodad_variation = 0
	_brush_doodad_num_var = maxi(int(info.get("num_var", 1)), 1)
	# 面板点选：朝向/缩放跟类型配置（fixedRot / defScale）
	_brush_doodad_angle = Wc3IdCatalog.default_facing_deg(info)
	_brush_doodad_scale = maxf(float(info.get("def_scale", 1.0)), 0.01)
	_sync_active_brush()
	_ensure_inspect_window(true, false)
	if _inspect_window != null and _inspect_window.has_method("show_doodad"):
		_inspect_window.show_doodad(type_id, _brush_doodad_variation, true)
	_push_doodad_palette_to_brush()
	_refresh_hud_brush()
	_refresh_hud_props()
	_set_status_key("EDITOR_STATUS_DOODAD_SELECTED", [_brush_doodad_name, type_id])


func _on_unit_selected(type_id: String, info: Dictionary, owner_id: int) -> void:
	_brush_mode = "unit"
	_brush_unit_id = type_id
	_brush_unit_name = str(info.get("name", type_id))
	_brush_unit_owner = clampi(owner_id, 0, 15)
	_brush_unit_angle = Wc3IdCatalog.default_facing_deg(info)
	_sync_active_brush()
	_ensure_inspect_window(true, false)
	if _inspect_window != null:
		if _inspect_window.has_method("show_unit"):
			_inspect_window.show_unit(type_id, _brush_unit_owner, true)
		elif _inspect_window.has_method("show_doodad"):
			_inspect_window.show_doodad(type_id, 0, true)
	_push_unit_palette_to_brush()
	_refresh_hud_brush()
	_refresh_hud_props()
	_set_status_key(
		"EDITOR_STATUS_UNIT_SELECTED",
		[_brush_unit_name, type_id, _brush_unit_owner + 1]
	)


func _on_unit_owner_changed(owner_id: int) -> void:
	_brush_unit_owner = clampi(owner_id, 0, 15)
	if _brush_mode == "unit" and not _brush_unit_id.is_empty():
		if _inspect_window != null and _inspect_window.has_method("set_preview_team_color"):
			_inspect_window.set_preview_team_color(_brush_unit_owner)
		_push_unit_palette_to_brush()
		_refresh_hud_brush()
		_refresh_hud_props()
		_set_status_key(
			"EDITOR_STATUS_UNIT_SELECTED",
			[_brush_unit_name, _brush_unit_id, _brush_unit_owner + 1]
		)


## 单位图标网格就绪：后台预读 GLB 字节（不解析），减轻首次点选 IO。
func _on_unit_icons_ready(type_ids: PackedStringArray) -> void:
	_ensure_inspect_window(false, false)
	if _inspect_window != null and _inspect_window.has_method("prewarm_unit_type_ids"):
		_inspect_window.prewarm_unit_type_ids(type_ids)


func _on_preview_params_changed(variation: int, angle_deg: float, scale: float, random_var: bool) -> void:
	_brush_doodad_variation = variation
	_brush_doodad_angle = angle_deg
	_brush_doodad_scale = scale
	_brush_doodad_random = random_var
	_brush_unit_angle = angle_deg
	_push_doodad_palette_to_brush()
	_push_unit_palette_to_brush()
	# Inspect 朝向变更时：若地图上有选中，一并旋转该实例（与快捷键一致）
	if _brush_mode == "doodad" and doodad_brush != null and doodad_brush.has_method("get_selected_creation_number"):
		var cn: int = int(doodad_brush.get_selected_creation_number())
		if cn >= 0 and doodad_brush.has_method("apply_facing_to_selection"):
			doodad_brush.apply_facing_to_selection(angle_deg)
	elif _brush_mode == "unit" and unit_brush != null and unit_brush.has_method("get_selected_creation_number"):
		var ucn: int = int(unit_brush.get_selected_creation_number())
		if ucn >= 0 and unit_brush.has_method("apply_facing_to_selection"):
			unit_brush.apply_facing_to_selection(angle_deg)
	_refresh_hud_props()


func _on_doodad_place_random_changed(
	random_rotation: bool,
	random_scale_sym: bool,
	random_scale_z: bool,
	random_scale_xy: bool,
) -> void:
	_brush_doodad_rand_rotation = random_rotation
	_brush_doodad_rand_scale_sym = random_scale_sym
	_brush_doodad_rand_scale_z = random_scale_z
	_brush_doodad_rand_scale_xy = random_scale_xy
	_push_doodad_palette_to_brush()
	# 多开面板同步开关状态
	for win in _tool_palettes:
		if is_instance_valid(win) and win.has_method("set_doodad_place_random"):
			win.set_doodad_place_random(
				random_rotation, random_scale_sym, random_scale_z, random_scale_xy
			)


func _current_map_tileset() -> String:
	if _doc != null and _doc.heightfield != null:
		var letter := str(_doc.heightfield.main_tileset).strip_edges().to_upper()
		if not letter.is_empty():
			return letter
	if _we_data != null and not str(_we_data.default_tileset).is_empty():
		return str(_we_data.default_tileset).to_upper()
	return "L"


func _on_tile_hovered(tile: Vector2i) -> void:
	_hover_tile = tile
	var coords := EditorI18n.t("EDITOR_HOVER_CELL", [tile.x, tile.y])
	if status_bar != null and status_bar.has_method("set_coords_text"):
		status_bar.set_coords_text(coords)
	elif hover_label != null:
		hover_label.text = coords


func _on_ramp_feedback(message: String) -> void:
	if message.is_empty():
		return
	_set_status(message)


func _on_dirty_changed(dirty: bool) -> void:
	if toolbar != null and toolbar.has_method("set_dirty"):
		toolbar.set_dirty(dirty)


func _ensure_inspect_window(focus: bool = false, refresh_minimap: bool = false) -> void:
	var created := _inspect_window == null or not is_instance_valid(_inspect_window)
	if created:
		_inspect_window = InspectWindowScene.instantiate()
		add_child(_inspect_window)
		_inspect_window.setup(map_root.get_id_catalog(), map_root.get_model_cache())
		_inspect_window.minimap_clicked.connect(_on_minimap_clicked)
		_inspect_window.preview_params_changed.connect(_on_preview_params_changed)
		if _inspect_window.has_signal("preview_clear_requested"):
			_inspect_window.preview_clear_requested.connect(_on_inspect_preview_clear_requested)
		_inspect_window.closed_by_user.connect(func() -> void: pass)
		var main_win := get_viewport().get_window()
		_inspect_window.transient = false
		_inspect_window.always_on_top = true
		if main_win != null:
			# 默认靠主窗右侧，与左侧工具面板对置
			_inspect_window.position = main_win.position + Vector2i(maxi(main_win.size.x - 320, 40), 72)
		else:
			_inspect_window.position = Vector2i(960, 72)
	# 点选预览不刷小地图；仅首次创建或显式要求时刷新
	if refresh_minimap or created:
		_refresh_inspect_minimap()
	_inspect_window.visible = true
	_inspect_window.show()
	if focus:
		_inspect_window.move_to_foreground()


## 按当前笔刷模式恢复 Inspect 预览（切层 / 开面板用；不在 ensure 里自动 show_doodad）。
func _restore_inspect_preview_for_brush() -> void:
	if _inspect_window == null or not is_instance_valid(_inspect_window):
		return
	if _brush_mode == "unit":
		if _brush_unit_id.is_empty():
			if _inspect_window.has_method("clear_preview"):
				_inspect_window.clear_preview()
		elif _inspect_window.has_method("show_unit"):
			_inspect_window.show_unit(_brush_unit_id, _brush_unit_owner, true)
	elif _brush_mode == "doodad":
		if _brush_doodad_id.is_empty():
			if _inspect_window.has_method("clear_preview"):
				_inspect_window.clear_preview()
		elif _inspect_window.has_method("show_doodad"):
			_inspect_window.show_doodad(_brush_doodad_id, _brush_doodad_variation, true)


func _refresh_inspect_minimap() -> void:
	if _inspect_window == null or not is_instance_valid(_inspect_window):
		return
	if _doc != null and _doc.heightfield != null and _inspect_window.has_method("refresh_minimap"):
		var map_dir: String = _doc.map_dir if _doc != null else ""
		var tiles: Wc3TerrainTileCatalog = map_root.get_tiles() if map_root != null else null
		var cliffs: Wc3CliffCatalog = map_root.get_cliff_catalog() if map_root != null else null
		_inspect_window.refresh_minimap(_doc.heightfield, map_dir, tiles, cliffs)
	_update_inspect_viewport_rect()


## 地形 Mesh rebuild 后刷新实时小地图（与 brush/history 同拍）。
func _refresh_inspect_minimap_live() -> void:
	if _inspect_window == null or not is_instance_valid(_inspect_window):
		return
	if _doc == null or _doc.heightfield == null:
		return
	if not _inspect_window.has_method("refresh_minimap_live"):
		_refresh_inspect_minimap()
		return
	var tiles: Wc3TerrainTileCatalog = map_root.get_tiles() if map_root != null else null
	var cliffs: Wc3CliffCatalog = map_root.get_cliff_catalog() if map_root != null else null
	_inspect_window.refresh_minimap_live(_doc.heightfield, tiles, cliffs)
	_update_inspect_viewport_rect()


func _update_inspect_viewport_rect() -> void:
	if _inspect_window == null or not is_instance_valid(_inspect_window):
		return
	if _doc == null or _doc.heightfield == null or camera_rig == null:
		return
	var quad: PackedVector2Array = _compute_camera_minimap_uv_quad()
	if _inspect_window.has_method("set_viewport_uv_quad"):
		_inspect_window.set_viewport_uv_quad(quad)
	elif _inspect_window.has_method("set_viewport_uv"):
		_inspect_window.set_viewport_uv(_compute_camera_minimap_uv_rect())


## 世界坐标 → 小地图 UV（委托给 MapMinimapUtils）。
func _world_to_minimap_uv(world: Vector3) -> Vector2:
	if _doc == null or _doc.heightfield == null:
		return Vector2.ZERO
	return MapMinimapUtils.world_to_minimap_uv(world, _doc.heightfield)


## 小地图 UV → 轨道观察点世界坐标（委托给 MapMinimapUtils）。
func _minimap_uv_to_world(uv: Vector2) -> Vector3:
	if _doc == null or _doc.heightfield == null:
		return Vector3.ZERO
	var world_y: float = camera_rig.global_position.y if camera_rig != null else 0.0
	return MapMinimapUtils.minimap_uv_to_world(uv, _doc.heightfield, world_y)


## 将主相机视锥投影到地面，得到与真实视野一致的小地图框。
func _compute_camera_minimap_uv_rect() -> Rect2:
	if camera_rig == null or _doc == null or _doc.heightfield == null:
		return Rect2()
	var cam: Camera3D = _get_editor_camera()
	if cam == null:
		return Rect2()
	return MapMinimapUtils.compute_camera_minimap_uv_rect(cam, camera_rig, _doc.heightfield)


## 视锥四角 → 小地图 UV 梯形（可出图外）。
func _compute_camera_minimap_uv_quad() -> PackedVector2Array:
	if camera_rig == null or _doc == null or _doc.heightfield == null:
		return PackedVector2Array()
	var cam: Camera3D = _get_editor_camera()
	if cam == null:
		return PackedVector2Array()
	return MapMinimapUtils.compute_camera_minimap_uv_quad(cam, camera_rig, _doc.heightfield)


func _get_editor_camera() -> Camera3D:
	if camera_rig != null and camera_rig.has_method("get_camera"):
		return camera_rig.get_camera()
	return null


func _on_minimap_clicked(norm_uv: Vector2) -> void:
	if camera_rig == null or _doc == null or _doc.heightfield == null:
		return
	camera_rig.global_position = _minimap_uv_to_world(norm_uv)
	_update_inspect_viewport_rect()


func _refresh_hud_brush() -> void:
	var text := ""
	if _brush_mode == "doodad" and not _brush_doodad_id.is_empty():
		text = EditorI18n.t("EDITOR_HUD_BRUSH_DOODAD", [_brush_doodad_name, _brush_doodad_id])
	elif _brush_mode == "unit" and not _brush_unit_id.is_empty():
		text = EditorI18n.t(
			"EDITOR_HUD_BRUSH_UNIT",
			[_brush_unit_name, _brush_unit_id, _brush_unit_owner + 1]
		)
	else:
		var tid: String = str(_doc.brush_tile_id()) if _doc != null else ""
		var label: String = EditorI18n.tile_display_name(map_root.get_tiles(), tid) if map_root != null else tid
		if label.is_empty():
			label = tid if not tid.is_empty() else "—"
		text = EditorI18n.t("EDITOR_HUD_BRUSH_TERRAIN", [label])
	if status_bar != null and status_bar.has_method("set_brush_text"):
		status_bar.set_brush_text(text)
	if toolbar != null and toolbar.has_method("set_brush_text"):
		if _brush_mode == "doodad":
			toolbar.set_brush_text(_brush_doodad_name)
		elif _brush_mode == "unit":
			toolbar.set_brush_text(_brush_unit_name)
		else:
			toolbar.set_brush_text(text)


func _refresh_hud_props() -> void:
	var text := "—"
	if _brush_mode == "doodad" and not _brush_doodad_id.is_empty():
		text = EditorI18n.t(
			"EDITOR_HUD_PROPS_DOODAD",
			[_brush_doodad_variation, int(_brush_doodad_angle), _brush_doodad_scale]
		)
	elif _brush_mode == "unit" and not _brush_unit_id.is_empty():
		text = EditorI18n.t("EDITOR_HUD_PROPS_UNIT", [_brush_unit_owner + 1])
	if status_bar != null and status_bar.has_method("set_props_text"):
		status_bar.set_props_text(text)


func _on_brush_rebuild() -> void:
	if _rebuilding:
		AppLog.debug(AppLog.Layer.EDITOR, "Brush", "rebuild skipped (busy)")
		_pending_history_rebuild = true
		_pending_history_cliff = (
			_pending_history_cliff
			or (brush != null and bool(brush.get("cliff_dirty")))
		)
		return
	_rebuilding = true
	var cliff := brush != null and bool(brush.get("cliff_dirty"))
	AppLog.info(
		AppLog.Layer.EDITOR,
		"Brush",
		"rebuild cliff_path=%s" % cliff
	)
	if cliff:
		brush.cliff_dirty = false
		map_root.rebuild_terrain_cliffs_water(_doc.as_build_dict(), _doc.info)
	else:
		map_root.rebuild_terrain_only(_doc.as_build_dict(), _doc.info)
	_rebuilding = false
	_refresh_inspect_minimap_live()
	if _pending_history_rebuild:
		var again_cliff: bool = _pending_history_cliff
		_pending_history_rebuild = false
		_pending_history_cliff = false
		call_deferred("_run_history_rebuild", again_cliff)


func _apply_document(full_reload: bool) -> void:
	if palette != null and palette.has_method("rebuild"):
		palette.rebuild(_doc, map_root.get_tiles())
	_refresh_all_tool_palettes()
	_refresh_brush_label()
	if toolbar != null and toolbar.has_method("set_dirty"):
		toolbar.set_dirty(_doc.is_dirty())
	var cam: Camera3D = null
	if camera_rig != null and camera_rig.has_method("get_camera"):
		cam = camera_rig.get_camera()
	if brush != null and brush.has_method("setup"):
		brush.setup(_doc, cam, map_root.get_world_3d(), _history)
		brush.set_brush_settings(_brush_size, _brush_shape)
		brush.apply_texture = _apply_texture
		brush.set_cliff_settings(_apply_cliff, _cliff_tool_id, _cliff_type_index)
		if brush.has_method("set_special_texture"):
			brush.set_special_texture(_special_texture)
	if doodad_brush != null and doodad_brush.has_method("setup"):
		doodad_brush.setup(_doc, cam, map_root.get_world_3d(), _history, map_root)
		doodad_brush.set_brush_settings(_brush_size, _brush_shape)
		_push_doodad_palette_to_brush()
	if unit_brush != null and unit_brush.has_method("setup"):
		unit_brush.setup(_doc, cam, map_root.get_world_3d(), _history, map_root)
		_ensure_marquee()
		if unit_brush.has_method("set_marquee"):
			unit_brush.set_marquee(_marquee)
		_push_unit_palette_to_brush()
	if doodad_brush != null and doodad_brush.has_method("set_marquee"):
		_ensure_marquee()
		doodad_brush.set_marquee(_marquee)
	_doodads_present_built = false
	_units_present_built = false
	_sync_active_brush()
	if full_reload:
		var dir: String = _doc.map_dir if not _doc.map_dir.is_empty() else "res://"
		await map_root.reload_from_hf(_doc.as_build_dict(), _doc.info, dir)
	else:
		map_root.rebuild_terrain_cliffs_water(_doc.as_build_dict(), _doc.info)
	# Document 已读 doodads/units.json；装饰物随开图呈现，单位分帧加载
	_rebuild_doodads_present()
	_units_present_built = false
	_start_units_present_batched()
	_sync_pathing_to_map_root()
	if camera_rig != null and camera_rig.has_method("focus_map_extent"):
		camera_rig.focus_map_extent(_doc.map_size())
	_refresh_inspect_minimap()
	_refresh_hud_brush()
	_refresh_hud_props()


func _sync_active_brush() -> void:
	var use_doodad := _brush_mode == "doodad"
	var use_unit := _brush_mode == "unit"
	if brush != null:
		brush.set("enabled", not use_doodad and not use_unit)
	if doodad_brush != null:
		doodad_brush.set("enabled", use_doodad)
		if use_doodad:
			_push_doodad_palette_to_brush()
			_ensure_doodads_present()
	if unit_brush != null:
		unit_brush.set("enabled", use_unit)
		if use_unit:
			_push_unit_palette_to_brush()
			_ensure_units_present()
	if input_router != null:
		if use_doodad:
			input_router.set("brush", doodad_brush)
		elif use_unit:
			input_router.set("brush", unit_brush)
		else:
			input_router.set("brush", brush)


func _push_doodad_palette_to_brush() -> void:
	if doodad_brush == null or not doodad_brush.has_method("set_palette"):
		return
	doodad_brush.set_palette(
		_brush_doodad_id,
		_brush_doodad_variation,
		_brush_doodad_angle,
		_brush_doodad_scale,
		_brush_doodad_random,
		_brush_doodad_num_var,
		_brush_doodad_rand_rotation,
		_brush_doodad_rand_scale_sym,
		_brush_doodad_rand_scale_z,
		_brush_doodad_rand_scale_xy,
	)


func _push_unit_palette_to_brush() -> void:
	if unit_brush == null or not unit_brush.has_method("set_palette"):
		return
	unit_brush.set_palette(_brush_unit_id, _brush_unit_owner, _brush_unit_angle)
	if unit_brush.has_method("set_random_rotation"):
		unit_brush.set_random_rotation(_brush_unit_random_rotation)


func _ensure_doodads_present() -> void:
	if _doodads_present_built or map_root == null or _doc == null:
		return
	_rebuild_doodads_present()
	_doodads_present_built = true


func _rebuild_doodads_present() -> void:
	if map_root == null or _doc == null:
		return
	map_root.rebuild_doodads_from_list(_doc.as_build_dict(), _doc.doodad_entries())
	_doodads_present_built = true


func _ensure_units_present() -> void:
	if _units_present_built or map_root == null or _doc == null:
		return
	if _units_loading:
		return
	_start_units_present_batched()


func _start_units_present_batched() -> void:
	if map_root == null or _doc == null:
		return
	if _units_present_built:
		return
	_wire_units_batch_signals()
	_units_loading = true
	_units_present_built = false
	_set_status_key("EDITOR_STATUS_LOADING_UNITS_PROGRESS", [0, _doc.unit_entries().size()])
	if map_root.has_method("rebuild_units_from_list"):
		map_root.rebuild_units_from_list(_doc.as_build_dict(), _doc.unit_entries(), true)
	else:
		_rebuild_units_present()


func _wire_units_batch_signals() -> void:
	if _units_batch_wired or map_root == null:
		return
	var layer: MapUnitLayer = null
	if map_root.has_method("get_unit_layer"):
		layer = map_root.get_unit_layer()
	if layer == null:
		return
	if layer.has_signal("batch_progress") and not layer.batch_progress.is_connected(_on_units_batch_progress):
		layer.batch_progress.connect(_on_units_batch_progress)
	if layer.has_signal("batch_finished") and not layer.batch_finished.is_connected(_on_units_batch_finished):
		layer.batch_finished.connect(_on_units_batch_finished)
	_units_batch_wired = true


func _on_units_batch_progress(done: int, total: int) -> void:
	_set_status_key("EDITOR_STATUS_LOADING_UNITS_PROGRESS", [done, total])


func _on_units_batch_finished(_placed: int, _placeholders: int) -> void:
	_units_loading = false
	_units_present_built = true
	_set_status_key("EDITOR_STATUS_IDLE")
	_refresh_hud_props()


func _rebuild_units_present() -> void:
	if map_root == null or _doc == null:
		return
	# 同步路径（撤销等需要立刻一致时仍可用）；开图走 batched
	map_root.rebuild_units_from_list(_doc.as_build_dict(), _doc.unit_entries(), false)
	_units_present_built = true
	_units_loading = false


func _on_doodad_brush_rebuild() -> void:
	# 增量 Present 已在笔刷内完成；仅刷新脏标记 HUD
	if toolbar != null and toolbar.has_method("set_dirty") and _doc != null:
		toolbar.set_dirty(_doc.is_dirty())


func _on_unit_brush_rebuild() -> void:
	if toolbar != null and toolbar.has_method("set_dirty") and _doc != null:
		toolbar.set_dirty(_doc.is_dirty())


func _on_doodads_placed(count: int) -> void:
	if count <= 0:
		return
	_set_status_key("EDITOR_STATUS_DOODAD_PLACED", [count, _brush_doodad_name])
	_refresh_hud_props()
	if toolbar != null and toolbar.has_method("set_dirty") and _doc != null:
		toolbar.set_dirty(_doc.is_dirty())


func _on_doodad_facing_changed(angle_deg: float) -> void:
	_brush_doodad_angle = angle_deg
	# 只同步朝向，不要 show_doodad（会重载模型，旋转时看起来像没转）
	if _inspect_window != null and is_instance_valid(_inspect_window):
		if _inspect_window.has_method("set_place_facing"):
			_inspect_window.set_place_facing(angle_deg, true, false)
	_push_doodad_palette_to_brush()
	_refresh_hud_props()


func _on_doodad_map_selection_changed(creation_number: int) -> void:
	if creation_number < 0:
		return
	_set_status_key("EDITOR_STATUS_DOODAD_PICKED", [creation_number])
	if doodad_brush == null or _doc == null:
		return
	var idx: int = _doc.find_doodad_index_by_creation_number(creation_number)
	var entry: Dictionary = _doc.get_doodad(idx) if idx >= 0 else {}
	if entry.is_empty():
		return
	# 预览面板显示该实例（距离按类型配置，朝向/样式按实例）
	_ensure_inspect_window(true, false)
	if _inspect_window != null and _inspect_window.has_method("show_map_doodad"):
		_inspect_window.show_map_doodad(entry)
	elif _inspect_window != null and _inspect_window.has_method("show_doodad"):
		_inspect_window.show_doodad(str(entry.get("id", "")), int(entry.get("variation", 0)), true)
		var deg_fallback: float = float(
			entry.get("angleDegrees", rad_to_deg(float(entry.get("angle", 0.0))))
		)
		if _inspect_window.has_method("set_place_facing"):
			_inspect_window.set_place_facing(deg_fallback, true, false)
	var deg: float = float(entry.get("angleDegrees", rad_to_deg(float(entry.get("angle", 0.0)))))
	_brush_doodad_angle = deg
	_on_doodad_facing_changed(deg)


func _on_doodads_deleted(count: int) -> void:
	if count <= 0:
		return
	_set_status_key("EDITOR_STATUS_DOODAD_DELETED", [count])
	_refresh_hud_props()
	if toolbar != null and toolbar.has_method("set_dirty") and _doc != null:
		toolbar.set_dirty(_doc.is_dirty())


func _on_doodad_palette_cleared() -> void:
	_brush_doodad_id = ""
	_brush_doodad_name = ""
	_brush_doodad_variation = 0
	_brush_doodad_num_var = 1
	if _inspect_window != null and is_instance_valid(_inspect_window):
		if _inspect_window.has_method("clear_preview"):
			_inspect_window.clear_preview()
	for win in _tool_palettes:
		if win != null and is_instance_valid(win) and win.has_method("clear_doodad_selection"):
			win.clear_doodad_selection()
	_push_doodad_palette_to_brush()
	_refresh_hud_brush()
	_refresh_hud_props()
	_set_status_key("EDITOR_STATUS_DOODAD_BRUSH")


func _on_units_placed(count: int) -> void:
	if count <= 0:
		return
	_set_status_key("EDITOR_STATUS_UNIT_PLACED", [count, _brush_unit_name])
	_refresh_hud_props()
	if toolbar != null and toolbar.has_method("set_dirty") and _doc != null:
		toolbar.set_dirty(_doc.is_dirty())


func _on_unit_facing_changed(angle_deg: float) -> void:
	_brush_unit_angle = angle_deg
	if _inspect_window != null and is_instance_valid(_inspect_window):
		if _inspect_window.has_method("set_place_facing"):
			_inspect_window.set_place_facing(angle_deg, true, false)
	_push_unit_palette_to_brush()
	_refresh_hud_props()


func _on_unit_map_selection_changed(creation_number: int) -> void:
	if creation_number < 0:
		return
	_set_status_key("EDITOR_STATUS_UNIT_PICKED", [creation_number])
	if unit_brush == null or _doc == null:
		return
	var idx: int = _doc.find_unit_index_by_creation_number(creation_number)
	var entry: Dictionary = _doc.get_unit(idx) if idx >= 0 else {}
	if entry.is_empty():
		return
	_ensure_inspect_window(true, false)
	if _inspect_window != null and _inspect_window.has_method("show_map_unit"):
		_inspect_window.show_map_unit(entry)
	elif _inspect_window != null and _inspect_window.has_method("show_unit"):
		_inspect_window.show_unit(
			str(entry.get("typeId", "")), int(entry.get("owner", 0)), true
		)
	var deg: float = float(entry.get("angleDegrees", rad_to_deg(float(entry.get("angle", 0.0)))))
	_brush_unit_angle = deg
	_brush_unit_owner = clampi(int(entry.get("owner", _brush_unit_owner)), 0, 15)
	# 地图点选 ≠ 放置：勿写入 _brush_unit_id，否则会进幽灵模式（对齐装饰物选中）
	_brush_unit_id = ""
	_brush_unit_name = ""
	if unit_brush.has_method("set_palette"):
		unit_brush.set_palette("", _brush_unit_owner, deg)
	for win in _tool_palettes:
		if win != null and is_instance_valid(win) and win.has_method("clear_unit_selection"):
			win.clear_unit_selection()
	# 只同步 Inspect 朝向，不走 _on_unit_facing_changed（会 push 放置笔刷）
	if _inspect_window != null and is_instance_valid(_inspect_window):
		if _inspect_window.has_method("set_place_facing"):
			_inspect_window.set_place_facing(deg, true, false)
	_refresh_hud_brush()
	_refresh_hud_props()


func _on_units_deleted(count: int) -> void:
	if count <= 0:
		return
	_set_status_key("EDITOR_STATUS_UNIT_DELETED", [count])
	_refresh_hud_props()
	if toolbar != null and toolbar.has_method("set_dirty") and _doc != null:
		toolbar.set_dirty(_doc.is_dirty())


func _on_unit_palette_cleared() -> void:
	_brush_unit_id = ""
	_brush_unit_name = ""
	if _inspect_window != null and is_instance_valid(_inspect_window):
		if _inspect_window.has_method("clear_preview"):
			_inspect_window.clear_preview()
	for win in _tool_palettes:
		if win != null and is_instance_valid(win) and win.has_method("clear_unit_selection"):
			win.clear_unit_selection()
	_push_unit_palette_to_brush()
	_refresh_hud_brush()
	_refresh_hud_props()
	_set_status_key("EDITOR_STATUS_UNIT_BRUSH")


func _on_unit_properties_requested(creation_number: int) -> void:
	if _doc == null or creation_number < 0:
		return
	var idx: int = _doc.find_unit_index_by_creation_number(creation_number)
	var entry: Dictionary = _doc.get_unit(idx) if idx >= 0 else {}
	if entry.is_empty():
		return
	_ensure_unit_props_dialog()
	if _unit_props_dialog != null and _unit_props_dialog.has_method("open_for_entry"):
		_unit_props_dialog.open_for_entry(entry)


func _ensure_unit_props_dialog() -> void:
	if _unit_props_dialog != null and is_instance_valid(_unit_props_dialog):
		return
	_unit_props_dialog = UnitPropertiesScene.instantiate() as Window
	add_child(_unit_props_dialog)
	if _unit_props_dialog.has_method("setup"):
		var catalog: Wc3IdCatalog = map_root.get_id_catalog() if map_root != null else null
		_unit_props_dialog.setup(catalog, _doc, _history)
	if _unit_props_dialog.has_signal("confirmed"):
		_unit_props_dialog.confirmed.connect(_on_unit_props_confirmed)


func _on_unit_props_confirmed(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	# Document 已在对话框 OK 时写入；刷新 Present + 预览
	var cn := int(entry.get("creationNumber", -1))
	if map_root != null and map_root.has_method("update_unit_instance"):
		if not map_root.update_unit_instance(entry, _doc.as_build_dict()):
			_rebuild_units_present()
	else:
		_rebuild_units_present()
	if unit_brush != null and unit_brush.has_method("select_creation_number") and cn >= 0:
		unit_brush.select_creation_number(cn)
	_brush_unit_owner = clampi(int(entry.get("owner", _brush_unit_owner)), 0, 15)
	_brush_unit_angle = float(entry.get("angleDegrees", _brush_unit_angle))
	if _inspect_window != null and _inspect_window.has_method("show_map_unit"):
		_inspect_window.show_map_unit(entry)
	_refresh_hud_props()
	if toolbar != null and toolbar.has_method("set_dirty") and _doc != null:
		toolbar.set_dirty(_doc.is_dirty())


## 浮窗 Esc：与主视口笔刷 Esc 同序（先地图选中，再放置预览）。
func _cancel_doodad_preview_like_we() -> void:
	if doodad_brush == null:
		return
	if doodad_brush.has_method("get_selected_creation_number"):
		if int(doodad_brush.get_selected_creation_number()) >= 0:
			if doodad_brush.has_method("clear_selection"):
				doodad_brush.clear_selection()
			return
	if not _brush_doodad_id.is_empty() and doodad_brush.has_method("clear_palette"):
		doodad_brush.clear_palette()


func _cancel_unit_preview_like_we() -> void:
	if unit_brush == null:
		return
	if unit_brush.has_method("get_selected_creation_number"):
		if int(unit_brush.get_selected_creation_number()) >= 0:
			if unit_brush.has_method("clear_selection"):
				unit_brush.clear_selection()
			return
	if not _brush_unit_id.is_empty() and unit_brush.has_method("clear_palette"):
		unit_brush.clear_palette()


func _toggle_pathing_ground() -> void:
	if map_root == null:
		return
	_sync_pathing_to_map_root()
	var on: bool = not map_root.get_show_pathing_ground()
	map_root.set_show_pathing_ground(on)
	if menu != null and menu.has_method("set_pathing_checked"):
		menu.set_pathing_checked(on)
	var n := 0
	if map_root.has_method("get_pathing_overlay_cell_count"):
		n = int(map_root.get_pathing_overlay_cell_count())
	if on:
		_set_status_key("EDITOR_STATUS_PATHING_GROUND_ON", [n])
	else:
		_set_status_key("EDITOR_STATUS_PATHING_GROUND", ["关"])


func _sync_pathing_to_map_root() -> void:
	if map_root == null or _doc == null:
		return
	var tiles: Wc3TerrainTileCatalog = map_root.get_tiles() if map_root.has_method("get_tiles") else null
	if _doc.has_method("ensure_pathing"):
		_doc.ensure_pathing(tiles)
	if map_root.has_method("set_pathing_map"):
		map_root.set_pathing_map(_doc.pathing)


func _ensure_marquee() -> void:
	if _marquee != null and is_instance_valid(_marquee_overlay):
		return
	_marquee = _MarqueeSelectionScript.new()
	_marquee_overlay = _MarqueeOverlayScript.new()
	_marquee_overlay.name = "MarqueeOverlay"
	var ui := get_node_or_null("../UI") as CanvasLayer
	if ui != null:
		ui.add_child(_marquee_overlay)
	else:
		add_child(_marquee_overlay)
	_marquee_overlay.bind(_marquee)


func _on_palette_escape() -> void:
	if _brush_mode == "unit":
		_cancel_unit_preview_like_we()
	else:
		_cancel_doodad_preview_like_we()


func _on_inspect_preview_clear_requested() -> void:
	if _brush_mode == "unit":
		_cancel_unit_preview_like_we()
	else:
		_cancel_doodad_preview_like_we()


func _refresh_brush_label() -> void:
	_refresh_hud_brush()


func _set_status_key(key: String, args: Array = []) -> void:
	_status_key = key
	_status_args = args
	_set_status(EditorI18n.t(key, args))


func _set_status(text: String) -> void:
	if status_bar != null and status_bar.has_method("set_status_text"):
		status_bar.set_status_text(text)
	elif status_label != null:
		status_label.text = text
	print("Editor: %s" % text)
