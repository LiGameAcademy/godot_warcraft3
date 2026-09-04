class_name GmDebugPanel
extends CanvasLayer

## 开发 GM 面板。热键由 GameDirector 转发（默认 ` 反引号 / F4），避免编辑器抢走 F10。
## 控制地面栅格、pathing overlay、斜坡 debug、寻路线等。

signal toggled(visible_now: bool)

var _panel: PanelContainer
var _grid_option: OptionButton
var _pathing_check: CheckBox
var _ramp_check: CheckBox
var _path_dbg_check: CheckBox
var _hp_bar_check: CheckBox
var _hint: Label
var _map: MapLoader
var _director: Node
var _health_bars: HealthBarManager


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_resolve_refs()
	_build_ui()
	_sync_from_world()


func toggle() -> void:
	set_open(not visible)


func set_open(on: bool) -> void:
	visible = on
	if on:
		_resolve_refs()
		_sync_from_world()
	AppLog.info(AppLog.Layer.GM, "GM", "panel=%s" % ("open" if on else "closed"))
	toggled.emit(on)


func _resolve_refs() -> void:
	var parent_n := get_parent()
	if parent_n != null:
		if _map == null or not is_instance_valid(_map):
			_map = parent_n.get_node_or_null("MapRoot") as MapLoader
		if _director == null or not is_instance_valid(_director):
			_director = parent_n.get_node_or_null("GameDirector")
		if _health_bars == null or not is_instance_valid(_health_bars):
			_health_bars = parent_n.get_node_or_null("HealthBarManager") as HealthBarManager
			if _health_bars == null and _director != null:
				_health_bars = _director.get("health_bar_manager") as HealthBarManager


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(12, 72)
	_panel.custom_minimum_size = Vector2(300, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.focus_mode = Control.FOCUS_CLICK
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_STOP
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)

	var title := Label.new()
	title.text = "GM / 调试（` 或 F4）"
	title.add_theme_font_size_override("font_size", 16)
	v.add_child(title)

	var grid_row := HBoxContainer.new()
	v.add_child(grid_row)
	var gl := Label.new()
	gl.text = "地面栅格"
	gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_row.add_child(gl)
	_grid_option = OptionButton.new()
	_grid_option.add_item("关", 0)
	_grid_option.add_item("大", 1)
	_grid_option.add_item("大+中", 2)
	_grid_option.add_item("大+中+小", 3)
	_grid_option.item_selected.connect(_on_grid_selected)
	grid_row.add_child(_grid_option)

	_pathing_check = CheckBox.new()
	_pathing_check.text = "Pathing 地面色块"
	_pathing_check.toggled.connect(_on_pathing_toggled)
	v.add_child(_pathing_check)

	_ramp_check = CheckBox.new()
	_ramp_check.text = "斜坡 Debug"
	_ramp_check.toggled.connect(_on_ramp_toggled)
	v.add_child(_ramp_check)

	_path_dbg_check = CheckBox.new()
	_path_dbg_check.text = "寻路线（同 F9）"
	_path_dbg_check.toggled.connect(_on_path_dbg_toggled)
	v.add_child(_path_dbg_check)

	_hp_bar_check = CheckBox.new()
	_hp_bar_check.text = "全局血条常显（关则按住 Alt）"
	_hp_bar_check.toggled.connect(_on_hp_bar_toggled)
	v.add_child(_hp_bar_check)

	var sep := HSeparator.new()
	v.add_child(sep)
	var hero_title := Label.new()
	hero_title.text = "英雄（需选中）"
	hero_title.add_theme_font_size_override("font_size", 14)
	v.add_child(hero_title)

	var hero_row := HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", 6)
	v.add_child(hero_row)
	_add_btn(hero_row, "升级+1", _on_hero_level_up)
	_add_btn(hero_row, "升到10", _on_hero_max_level)

	var skill_row := HBoxContainer.new()
	skill_row.add_theme_constant_override("separation", 6)
	v.add_child(skill_row)
	_add_btn(skill_row, "学一点", _on_hero_learn_one)
	_add_btn(skill_row, "解锁全技能", _on_hero_unlock_all)

	_hint = Label.new()
	_hint.text = "日志：game/config/debug_log.json · 英雄 GM 作用于主选"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	v.add_child(_hint)


func _add_btn(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)


func _call_director_gm(method: String) -> void:
	_resolve_refs()
	if _director == null or not _director.has_method(method):
		AppLog.warn(AppLog.Layer.GM, "GM", "missing %s" % method)
		return
	_director.call(method)


func _on_hero_level_up() -> void:
	_call_director_gm("gm_hero_level_up")


func _on_hero_max_level() -> void:
	_call_director_gm("gm_hero_max_level")


func _on_hero_learn_one() -> void:
	_call_director_gm("gm_hero_learn_one_point")


func _on_hero_unlock_all() -> void:
	_call_director_gm("gm_hero_unlock_all_skills")


func _sync_from_world() -> void:
	_resolve_refs()
	if _grid_option != null and _map != null:
		_grid_option.select(clampi(_map.get_view_grid_level(), 0, 3))
	elif _grid_option != null and _director != null:
		_grid_option.select(clampi(int(_director.get("view_grid_level")), 0, 3))
	if _pathing_check != null and _map != null:
		_pathing_check.set_pressed_no_signal(_map.get_show_pathing_ground())
	if _ramp_check != null and _map != null:
		_ramp_check.set_pressed_no_signal(_map.get_show_ramp_debug())
	elif _ramp_check != null and _director != null:
		_ramp_check.set_pressed_no_signal(bool(_director.get("show_ramp_debug")))
	if _path_dbg_check != null and _director != null:
		_path_dbg_check.set_pressed_no_signal(bool(_director.get("show_path_debug")))
	if _hp_bar_check != null:
		var on := true
		if _health_bars != null:
			on = _health_bars.is_always_show()
		_hp_bar_check.set_pressed_no_signal(on)


func _on_grid_selected(idx: int) -> void:
	_resolve_refs()
	var level := idx
	if _grid_option != null:
		level = _grid_option.get_item_id(idx)
	if _map != null:
		_map.set_view_grid_level(level)
	if _director != null:
		_director.set("view_grid_level", level)
	AppLog.info(AppLog.Layer.GM, "GM", "view_grid_level=%d" % level)


func _on_pathing_toggled(on: bool) -> void:
	_resolve_refs()
	if _map != null:
		_map.set_show_pathing_ground(on)
	if _director != null:
		_director.set("show_pathing_ground", on)
	AppLog.info(AppLog.Layer.GM, "GM", "pathing_ground=%s" % on)


func _on_ramp_toggled(on: bool) -> void:
	_resolve_refs()
	if _map != null:
		_map.set_show_ramp_debug(on)
	if _director != null:
		_director.set("show_ramp_debug", on)
	AppLog.info(AppLog.Layer.GM, "GM", "ramp_debug=%s" % on)


func _on_path_dbg_toggled(on: bool) -> void:
	_resolve_refs()
	if _director != null:
		_director.set("show_path_debug", on)
		if _director.has_method("_apply_path_debug_visibility"):
			_director.call("_apply_path_debug_visibility")
	AppLog.info(AppLog.Layer.GM, "GM", "path_debug=%s" % on)


func _on_hp_bar_toggled(on: bool) -> void:
	_resolve_refs()
	if _health_bars != null:
		_health_bars.set_always_show(on)
	AppLog.info(AppLog.Layer.GM, "GM", "hp_bars_always=%s" % on)
