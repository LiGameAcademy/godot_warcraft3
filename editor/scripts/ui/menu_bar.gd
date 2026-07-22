extends MenuBar
## 复刻经典世界编辑器顶栏：文件/编辑/察看/层面/情节/工具/高级/模块/窗口/帮助。
## 文案来自 UI/WorldEditStrings.txt；未实现项触发 stub 提示。


signal action_triggered(action_id: StringName)

const StringsScript := preload("res://editor/scripts/ui/world_edit_strings.gd")

var _strings
var _id_to_action: Dictionary = {} ## popup_instance_id → { item_id → action }
var _next_item_id: int = 1


func _ready() -> void:
	_strings = StringsScript.load_default()
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_id_to_action.clear()
	_next_item_id = 1

	_add_top(
		"WESTRING_MENU_FILE",
		[
			["WESTRING_MENU_NEW", &"file_new"],
			["WESTRING_MENU_OPEN", &"file_open"],
			["WESTRING_MENU_CLOSE", &"file_close", false],
			null,
			["WESTRING_MENU_SAVE", &"file_save"],
			["WESTRING_MENU_SAVEAS", &"file_save_as", false],
			["WESTRING_MENU_CALCSHADOWS", &"file_calc_shadows", false],
			null,
			["WESTRING_MENU_EXPORTSCRIPT", &"file_export_script", false],
			["WESTRING_MENU_EXPORTMINIMAP", &"file_export_minimap", false],
			["WESTRING_MENU_EXPORTSTRINGS", &"file_export_strings", false],
			["WESTRING_MENU_IMPORTSTRINGS", &"file_import_strings", false],
			null,
			["WESTRING_MENU_EDITPREFS", &"file_prefs", false],
			["WESTRING_MENU_CONFIGCTRLS", &"file_config_controls", false],
			null,
			["WESTRING_MENU_TESTMAP", &"file_test_map", false],
			null,
			["WESTRING_MENU_EXIT", &"file_exit"],
		]
	)
	_add_top(
		"WESTRING_MENU_EDIT",
		[
			["WESTRING_MENU_UNDO", &"edit_undo", false],
			["WESTRING_MENU_REDO", &"edit_redo", false],
			null,
			["WESTRING_MENU_CUT", &"edit_cut", false],
			["WESTRING_MENU_COPY", &"edit_copy", false],
			["WESTRING_MENU_PASTE", &"edit_paste", false],
			["WESTRING_MENU_CLEAR", &"edit_clear", false],
			null,
			["WESTRING_MENU_SELECTALL", &"edit_select_all", false],
			["WESTRING_MENU_EDITPROPS", &"edit_props", false],
		]
	)
	_add_top(
		"WESTRING_MENU_VIEW",
		[
			["WESTRING_MENU_TEXTURED", &"view_textured", false],
			["WESTRING_MENU_WIREFRAME", &"view_wireframe", false],
			null,
			["WESTRING_MENU_TERRAIN", &"view_terrain", false],
			["WESTRING_MENU_DOODADS", &"view_doodads", false],
			["WESTRING_MENU_UNITS", &"view_units", false],
			["WESTRING_MENU_WATER", &"view_water", false],
			["WESTRING_MENU_BLIGHT", &"view_blight", false],
			["WESTRING_MENU_PATHING", &"view_pathing", false],
			["WESTRING_MENU_SHADOWS", &"view_shadows", false],
			["WESTRING_MENU_LIGHTING", &"view_lighting", false],
			["WESTRING_MENU_WEATHER", &"view_weather", false],
			null,
			["WESTRING_MENU_GRID", &"view_grid", false],
			["WESTRING_MENU_CAMERABOUNDS", &"view_camera_bounds", false],
			["WESTRING_MENU_REGIONS", &"view_regions", false],
			["WESTRING_MENU_CAMERAS", &"view_cameras", false],
			null,
			["WESTRING_MENU_SKY", &"view_sky", false],
			["WESTRING_MENU_FOGEFFECTS", &"view_fog", false],
			["WESTRING_MENU_LETTERBOX", &"view_letterbox", false],
			null,
			["WESTRING_MENU_GAMECAMERASNAP", &"view_camera_snap", false],
		]
	)
	_add_top(
		"WESTRING_MENU_LAYER",
		[
			["WESTRING_MENU_TERRAIN", &"layer_terrain"],
			["WESTRING_MENU_DOODADS", &"layer_doodads", false],
			["WESTRING_MENU_UNITS", &"layer_units", false],
			["WESTRING_MENU_REGIONS", &"layer_regions", false],
			["WESTRING_MENU_CAMERAS", &"layer_cameras", false],
		]
	)
	_add_top(
		"WESTRING_MENU_SCENARIO",
		[
			["WESTRING_MENU_MAPDESCRIPTION", &"scenario_desc", false],
			["WESTRING_MENU_MAPOPTIONS", &"scenario_options", false],
			["WESTRING_MENU_MAPSIZE", &"scenario_size", false],
			["WESTRING_MENU_LOADSCREEN", &"scenario_loadscreen", false],
			["WESTRING_MENU_PROLOGUE", &"scenario_prologue", false],
			null,
			["WESTRING_MENU_PLAYERPROPS", &"scenario_players", false],
			["WESTRING_MENU_FORCEPROPS", &"scenario_forces", false],
			["WESTRING_MENU_ALLYPRIPROPS", &"scenario_ally", false],
			["WESTRING_MENU_TECHPROPS", &"scenario_tech", false],
			["WESTRING_MENU_ABILITIES", &"scenario_abilities", false],
			["WESTRING_MENU_UPGRADEPROPS", &"scenario_upgrades", false],
		]
	)
	_add_top(
		"WESTRING_MENU_TOOLS",
		[
			["WESTRING_MENU_SELBRUSH", &"tools_sel_brush"],
			null,
			["WESTRING_MENU_HEIGHTBRUSH", &"tools_height", false],
			["WESTRING_MENU_LEVELBRUSH", &"tools_plateau", false],
			["WESTRING_MENU_NOISEBRUSH", &"tools_noise", false],
			["WESTRING_MENU_SMOOTHBRUSH", &"tools_smooth", false],
			null,
			["WESTRING_MENU_BRUSHSIZE", &"tools_brush_size", false],
			["WESTRING_MENU_BRUSHSHAPE", &"tools_brush_shape", false],
		]
	)
	_add_top(
		"WESTRING_MENU_ADVANCED",
		[
			["WESTRING_MENU_MODTILESET", &"adv_tileset", false],
			["WESTRING_MENU_RANDOMGROUPS", &"adv_random_groups", false],
			["WESTRING_MENU_ITEMTABLES", &"adv_item_tables", false],
			null,
			["WESTRING_MENU_RESETHEIGHT", &"adv_reset_height", false],
			["WESTRING_MENU_ADJUSTCLIFFLEVELS", &"adv_cliff_levels", false],
			["WESTRING_MENU_REPLACETILES", &"adv_replace_tiles", false],
			["WESTRING_MENU_REPLACECLIFFTYPE", &"adv_replace_cliff", false],
			["WESTRING_MENU_REPLACEDOODADS", &"adv_replace_doodads", false],
			["WESTRING_MENU_REPLACEUNITS", &"adv_replace_units", false],
			null,
			["WESTRING_MENU_GAMECONSTANTS", &"adv_game_constants", false],
			["WESTRING_MENU_GAMEINTERFACE", &"adv_game_interface", false],
			null,
			["WESTRING_MENU_VIEWENTIREMAP", &"adv_view_entire", false],
		]
	)
	_add_top(
		"WESTRING_MENU_MODULE",
		[
			["WESTRING_MENU_MODULE_TERRAIN", &"module_terrain"],
			["WESTRING_MENU_MODULE_SCRIPTS", &"module_triggers", false],
			["WESTRING_MENU_MODULE_SOUND", &"module_sound", false],
			["WESTRING_MENU_OBJECTEDITOR", &"module_object", false],
			["WESTRING_MENU_MODULE_CAMPAIGN", &"module_campaign", false],
			["WESTRING_MENU_OBJECTMANAGER", &"module_objman", false],
			["WESTRING_MENU_IMPORTMANAGER", &"module_import", false],
			["WESTRING_MENU_MODULE_AI", &"module_ai", false],
		]
	)
	_add_top(
		"WESTRING_MENU_WINDOW",
		[
			["WESTRING_MENU_NEWPALETTE", &"window_new_palette", false],
			["WESTRING_MENU_SHOWPALETTES", &"window_show_palettes", false],
			null,
			["WESTRING_MENU_TOOLBAR", &"window_toolbar", false],
			["WESTRING_MENU_MINIMAP", &"window_minimap", false],
			["WESTRING_MENU_PREVIEWER", &"window_previewer", false],
			["WESTRING_MENU_TREEVIEW", &"window_brush_list", false],
		]
	)
	_add_top(
		"WESTRING_MENU_HELP",
		[
			["WESTRING_MENU_W3HELP", &"help_manual", false],
			["WESTRING_MENU_LICENSE", &"help_license", false],
			null,
			["WESTRING_MENU_ABOUT", &"help_about"],
		]
	)


func _add_top(title_key: String, entries: Array) -> void:
	var popup := PopupMenu.new()
	popup.name = _strings.get_text(title_key)
	popup.id_pressed.connect(_on_popup_id_pressed.bind(popup))
	var actions: Dictionary = {}
	for e in entries:
		if e == null:
			popup.add_separator()
			continue
		var key: String = str(e[0])
		var action: StringName = e[1]
		var enabled: bool = true if e.size() < 3 else bool(e[2])
		var id: int = _next_item_id
		_next_item_id += 1
		popup.add_item(_strings.get_text(key), id)
		popup.set_item_disabled(popup.get_item_index(id), not enabled)
		actions[id] = action
	_id_to_action[popup.get_instance_id()] = actions
	add_child(popup)


func _on_popup_id_pressed(id: int, popup: PopupMenu) -> void:
	var actions: Dictionary = _id_to_action.get(popup.get_instance_id(), {})
	if not actions.has(id):
		return
	action_triggered.emit(actions[id] as StringName)
