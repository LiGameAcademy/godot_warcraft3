extends MenuBar
## 经典世界编辑器顶栏。布局见 `menu_bar.tscn`。
## item text = 翻译 key；点击动作用 item id → action（不依赖 metadata 反序列化）。


signal action_triggered(action_id: StringName)

## PopupMenu item id → action（与 menu_bar.tscn 中 item_*/id 对齐）
const ID_TO_ACTION := {
	1: &"file_new",
	2: &"file_open",
	3: &"file_close",
	5: &"file_save",
	6: &"file_save_as",
	7: &"file_calc_shadows",
	9: &"file_export_script",
	10: &"file_export_minimap",
	11: &"file_export_strings",
	12: &"file_import_strings",
	14: &"file_prefs",
	15: &"file_config_controls",
	17: &"file_test_map",
	19: &"file_exit",
	20: &"edit_undo",
	21: &"edit_redo",
	23: &"edit_cut",
	24: &"edit_copy",
	25: &"edit_paste",
	26: &"edit_clear",
	28: &"edit_select_all",
	29: &"edit_props",
	30: &"view_textured",
	31: &"view_wireframe",
	33: &"view_terrain",
	34: &"view_doodads",
	35: &"view_units",
	36: &"view_water",
	37: &"view_blight",
	38: &"view_pathing",
	39: &"view_shadows",
	40: &"view_lighting",
	41: &"view_weather",
	43: &"view_grid",
	44: &"view_camera_bounds",
	45: &"view_regions",
	46: &"view_cameras",
	48: &"view_sky",
	49: &"view_fog",
	50: &"view_letterbox",
	52: &"view_camera_snap",
	430: &"view_grid_none",
	431: &"view_grid_large",
	432: &"view_grid_medium",
	433: &"view_grid_small",
	434: &"view_ramp_debug",
	53: &"layer_terrain",
	54: &"layer_doodads",
	55: &"layer_units",
	56: &"layer_regions",
	57: &"layer_cameras",
	58: &"scenario_desc",
	59: &"scenario_options",
	60: &"scenario_size",
	61: &"scenario_loadscreen",
	62: &"scenario_prologue",
	64: &"scenario_players",
	65: &"scenario_forces",
	66: &"scenario_ally",
	67: &"scenario_tech",
	68: &"scenario_abilities",
	69: &"scenario_upgrades",
	70: &"tools_sel_brush",
	72: &"tools_height",
	73: &"tools_plateau",
	74: &"tools_noise",
	75: &"tools_smooth",
	77: &"tools_brush_size",
	78: &"tools_brush_shape",
	79: &"adv_tileset",
	80: &"adv_random_groups",
	81: &"adv_item_tables",
	83: &"adv_reset_height",
	84: &"adv_cliff_levels",
	85: &"adv_replace_tiles",
	86: &"adv_replace_cliff",
	87: &"adv_replace_doodads",
	88: &"adv_replace_units",
	90: &"adv_game_constants",
	91: &"adv_game_interface",
	93: &"adv_view_entire",
	94: &"module_terrain",
	95: &"module_triggers",
	96: &"module_sound",
	97: &"module_object",
	98: &"module_campaign",
	99: &"module_objman",
	100: &"module_import",
	101: &"module_ai",
	102: &"window_new_palette",
	1020: &"window_new_palette_terrain",
	1021: &"window_new_palette_units",
	1022: &"window_new_palette_doodads",
	1023: &"window_new_palette_regions",
	1024: &"window_new_palette_cameras",
	103: &"window_show_palettes",
	105: &"window_toolbar",
	106: &"window_minimap",
	107: &"window_previewer",
	108: &"window_brush_list",
	109: &"help_manual",
	110: &"help_license",
	112: &"help_about",
	201: &"lang_zh_CN",
	202: &"lang_en",
}

## popup instance_id → PackedStringArray（item 翻译 key）
var _item_keys: Dictionary = {}
var _grid_popup: PopupMenu
var _window_popup: PopupMenu
var _new_palette_popup: PopupMenu


func _ready() -> void:
	_bootstrap_items()
	_wire_popups()
	_setup_grid_submenu()
	_setup_new_palette_submenu()
	_localize()
	EditorI18n.locale_changed.connect(func(_loc: String) -> void: _localize())


func _setup_grid_submenu() -> void:
	var view := get_node_or_null("View") as PopupMenu
	_grid_popup = get_node_or_null("View/Grid") as PopupMenu
	if view == null or _grid_popup == null:
		return
	# item id 43 → 栅格子菜单
	for i in range(view.item_count):
		if view.get_item_id(i) == 43:
			view.set_item_submenu_node(i, _grid_popup)
			break
	_set_grid_level_checked(0)


func _setup_new_palette_submenu() -> void:
	_window_popup = get_node_or_null("Window") as PopupMenu
	_new_palette_popup = get_node_or_null("Window/NewPalette") as PopupMenu
	if _window_popup == null or _new_palette_popup == null:
		return
	# item id 102 → 新面板子菜单
	for i in range(_window_popup.item_count):
		if _window_popup.get_item_id(i) == 102:
			_window_popup.set_item_submenu_node(i, _new_palette_popup)
			break
	set_show_palettes_checked(true)


## level: 0无 / 1大 / 2中 / 3小
func set_grid_level_checked(level: int) -> void:
	_set_grid_level_checked(level)


func set_ramp_debug_checked(on: bool) -> void:
	var view := get_node_or_null("View") as PopupMenu
	if view == null:
		return
	for i in range(view.item_count):
		if view.get_item_id(i) == 434:
			view.set_item_checked(i, on)
			break


func set_pathing_checked(on: bool) -> void:
	var view := get_node_or_null("View") as PopupMenu
	if view == null:
		return
	for i in range(view.item_count):
		if view.get_item_id(i) == 38:
			view.set_item_checked(i, on)
			break


func _set_grid_level_checked(level: int) -> void:
	if _grid_popup == null:
		return
	var lv := clampi(level, 0, _grid_popup.item_count - 1)
	for i in range(_grid_popup.item_count):
		_grid_popup.set_item_checked(i, i == lv)


func set_show_palettes_checked(visible_on: bool) -> void:
	if _window_popup == null:
		return
	for i in range(_window_popup.item_count):
		if _window_popup.get_item_id(i) == 103:
			_window_popup.set_item_checked(i, visible_on)
			break


func set_undo_redo_enabled(can_undo: bool, can_redo: bool) -> void:
	var edit := get_node_or_null("Edit") as PopupMenu
	if edit == null:
		return
	for i in range(edit.item_count):
		var id: int = edit.get_item_id(i)
		if id == 20:
			edit.set_item_disabled(i, not can_undo)
		elif id == 21:
			edit.set_item_disabled(i, not can_redo)


func _wire_popups() -> void:
	_wire_popup_tree(self)


func _wire_popup_tree(node: Node) -> void:
	for child in node.get_children():
		if child is PopupMenu:
			var popup := child as PopupMenu
			popup.auto_translate = false
			popup.index_pressed.connect(_on_popup_index_pressed.bind(popup))
			_wire_popup_tree(popup)


func _bootstrap_items() -> void:
	_item_keys.clear()
	_bootstrap_popup_tree(self)


func _bootstrap_popup_tree(node: Node) -> void:
	for child in node.get_children():
		if child is PopupMenu:
			var popup := child as PopupMenu
			popup.auto_translate = false
			var keys: PackedStringArray = PackedStringArray()
			keys.resize(popup.item_count)
			for i in range(popup.item_count):
				if popup.is_item_separator(i):
					keys[i] = ""
					continue
				var text := popup.get_item_text(i)
				keys[i] = text if _is_i18n_key(text) else ""
			_item_keys[popup.get_instance_id()] = keys
			_bootstrap_popup_tree(popup)


func _localize() -> void:
	_localize_popup_tree(self)
	queue_redraw()


func _localize_popup_tree(node: Node) -> void:
	for child in node.get_children():
		if not (child is PopupMenu):
			continue
		var popup := child as PopupMenu
		var title_key := str(popup.get_meta("_title_key", ""))
		if not title_key.is_empty():
			popup.name = EditorI18n.t(title_key)
		var keys: PackedStringArray = _item_keys.get(popup.get_instance_id(), PackedStringArray())
		for i in range(popup.item_count):
			if popup.is_item_separator(i):
				continue
			var key := keys[i] if i < keys.size() else ""
			if key.is_empty():
				continue
			popup.set_item_text(i, EditorI18n.t(key))
		_localize_popup_tree(popup)


func _on_popup_index_pressed(index: int, popup: PopupMenu) -> void:
	if index < 0 or index >= popup.item_count:
		return
	if popup.is_item_separator(index) or popup.is_item_disabled(index):
		return
	var item_id: int = popup.get_item_id(index)
	var action: StringName = ID_TO_ACTION.get(item_id, &"") as StringName
	if action == &"":
		# 兼容：若日后 metadata 可用则回退读取
		action = _read_action_meta(popup.get_item_metadata(index))
	if action == &"":
		push_warning(
			"MenuBar: item %d id=%d has no action (text=%s)"
			% [index, item_id, popup.get_item_text(index)]
		)
		return
	action_triggered.emit(action)


func _read_action_meta(meta: Variant) -> StringName:
	match typeof(meta):
		TYPE_STRING, TYPE_STRING_NAME:
			var s := str(meta).strip_edges()
			if s.is_empty() or _is_i18n_key(s):
				return &""
			return StringName(s)
		TYPE_DICTIONARY:
			var d: Dictionary = meta
			if d.has("action"):
				return StringName(str(d["action"]))
	return &""


func _is_i18n_key(s: String) -> bool:
	return s.begins_with("WESTRING_") or s.begins_with("EDITOR_")
