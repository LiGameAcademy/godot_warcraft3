class_name GameHud
extends CanvasLayer

## 现代底栏 HUD（AOE4 向）：左小地图 / 中信息 / 右命令格。暂不复刻 WC3 Console。

signal command_pressed(slot: int)
signal command_action(action_id: String)
signal minimap_clicked(uv: Vector2)
## 多选条点击：instance_id → Director 设 primary
signal multi_select_clicked(instance_id: int)

@export var map_dir: String = "res://assets/map-parsed/echoisles"
@export var console_height_ratio: float = 0.2
@export var show_dev_hint: bool = true

@onready var _gold_label: Label = %GoldValue
@onready var _lumber_label: Label = %LumberValue
@onready var _food_label: Label = %FoodValue
@onready var _unit_name: Label = %UnitName
@onready var _unit_hp: Label = %UnitHp
@onready var _attack_line: Label = %AttackLine
@onready var _armor_line: Label = %ArmorLine
@onready var _special_lines: Label = %SpecialLines
@onready var _portrait_host: Control = %PortraitHost
@onready var _portrait: UnitPortraitView = %UnitPortraitView
@onready var _portrait_hp: ProgressBar = %PortraitHpBar
@onready var _portrait_mana: ProgressBar = %PortraitManaBar
@onready var _multi_strip: HBoxContainer = %MultiSelectStrip
@onready var _build_row: Control = %BuildProgressRow
@onready var _build_bar: ProgressBar = %BuildProgressBar
@onready var _build_label: Label = %BuildProgressLabel
@onready var _minimap: Control = %Minimap
@onready var _command_grid: GridContainer = %CommandGrid
@onready var _command_panel: Control = $Root/MarginContainer3/CommandPanel
@onready var _command_title: Label = $Root/MarginContainer3/CommandPanel/Inner/CommandTitle
@onready var _center_host: Control = $Root/MarginContainer2
@onready var _status: Label = %StatusLabel
@onready var _hint: Label = %HintLabel
@onready var _bottom: Control = $Root/MarginContainer3

## slot → action_id（空=无动作）
var _slot_action_ids: PackedStringArray = PackedStringArray()
var _icon_cache: Dictionary = {} ## path → Texture2D
var _game_minimap: Control = null


func _ready() -> void:
	_style_command_panel()
	_style_center_panel()
	_wire_command_buttons()
	_wire_minimap_input()
	if _hint:
		_hint.visible = show_dev_hint
	set_resources(0, 0, 0, 0)
	set_selection_info(SelectionInfoBuilder.build_empty())
	clear_build_progress()
	_apply_bottom_height()
	get_viewport().size_changed.connect(_apply_bottom_height)
	if not map_dir.is_empty():
		setup_minimap_map(map_dir)


## Director：注入 heightfield / 单位层 / 相机，并加载 war3mapMap。
func configure_minimap(
	map_directory: String,
	heightfield: Wc3Heightfield,
	unit_host: Node,
	camera: Camera3D,
	camera_rig: Node3D,
	local_player: int = 0,
	catalog: Wc3IdCatalog = null
) -> void:
	if not map_directory.is_empty():
		map_dir = map_directory
	_ensure_game_minimap()
	if _game_minimap == null:
		return
	_game_minimap.configure(heightfield, unit_host, camera, camera_rig, local_player, catalog)
	setup_minimap_map(map_dir)


func setup_minimap_map(map_directory: String) -> bool:
	_ensure_game_minimap()
	if _game_minimap == null:
		return false
	return _game_minimap.load_from_map_dir(map_directory)


func _ensure_game_minimap() -> void:
	if _game_minimap != null and is_instance_valid(_game_minimap):
		return
	if _minimap != null and _minimap.has_method("configure") and _minimap.has_signal("clicked"):
		_game_minimap = _minimap


func _apply_bottom_height() -> void:
	if _bottom == null:
		return
	var h := get_viewport().get_visible_rect().size.y
	_bottom.offset_top = -h * console_height_ratio
	if _hint:
		_hint.offset_top = _bottom.offset_top - 28.0
		_hint.offset_bottom = _bottom.offset_top - 8.0


func set_resources(gold: int, lumber: int, food: int, food_max: int) -> void:
	if _gold_label:
		_gold_label.text = str(gold)
	if _lumber_label:
		_lumber_label.text = str(lumber)
	if _food_label:
		_food_label.text = "%d/%d" % [food, food_max]


func bind_stock(stock) -> void:
	if stock == null:
		return
	if not stock.changed.is_connected(_on_stock_changed):
		stock.changed.connect(_on_stock_changed)
	_on_stock_changed(stock)


func _on_stock_changed(stock) -> void:
	if stock == null:
		return
	set_resources(stock.gold, stock.lumber, stock.food_used, stock.food_cap)


func set_unit_info(unit_name: String, hp: int, hp_max: int) -> void:
	## 兼容旧调用；完整态请用 set_selection_info。
	if _unit_name:
		_unit_name.text = unit_name if not unit_name.is_empty() else "—"
	if _unit_hp:
		if hp_max > 0:
			_unit_hp.text = "生命 %d / %d" % [hp, hp_max]
		else:
			_unit_hp.text = ""
	_set_bar(_portrait_hp, hp, hp_max, true)


## 中栏完整刷新。info 见 SelectionInfoBuilder / docs/design/game/HUD.md。
func set_selection_info(info: Dictionary) -> void:
	if info.is_empty():
		info = SelectionInfoBuilder.build_empty()
	var mode := str(info.get("mode", "empty"))
	var display := str(info.get("display_name", "—"))
	var hp := int(info.get("hp", 0))
	var hp_max := int(info.get("hp_max", 0))
	var mana := int(info.get("mana", 0))
	var mana_max := int(info.get("mana_max", 0))
	if _unit_name:
		_unit_name.text = display if not display.is_empty() else "—"
	if _unit_hp:
		if hp_max > 0:
			_unit_hp.text = "生命 %d / %d" % [hp, hp_max]
			if mana_max > 0:
				_unit_hp.text += " · 魔法 %d / %d" % [mana, mana_max]
		else:
			_unit_hp.text = ""
	_set_bar(_portrait_hp, hp, hp_max, mode != "empty")
	_set_bar(_portrait_mana, mana, mana_max, mana_max > 0 and mode != "empty")
	if _attack_line:
		var atk := str(info.get("attack_line", ""))
		_attack_line.text = atk
		_attack_line.visible = not atk.is_empty() and mode != "empty"
	if _armor_line:
		var arm := str(info.get("armor_line", ""))
		_armor_line.text = arm
		_armor_line.visible = not arm.is_empty() and mode != "empty"
	if _special_lines:
		var specials: PackedStringArray = info.get("special_lines", PackedStringArray()) as PackedStringArray
		if specials == null:
			specials = PackedStringArray()
		_special_lines.text = "\n".join(specials)
		_special_lines.visible = not specials.is_empty()
	var tid := str(info.get("portrait_type_id", ""))
	var owner_id := int(info.get("owner_id", 0))
	if mode == "empty" or tid.is_empty():
		if _portrait != null:
			_portrait.clear_portrait()
	elif _portrait != null:
		_portrait.show_type(tid, owner_id)
	_refresh_multi_strip(info.get("multi", []) as Array, mode == "multi")
	var hint := str(info.get("status_hint", ""))
	if not hint.is_empty() and _status:
		# 不覆盖更具体的 Director 状态时：仅空/默认时写入
		pass


func configure_portrait(cache: MapModelCache, catalog: Wc3IdCatalog) -> void:
	if _portrait != null:
		_portrait.configure(cache, catalog)


func _set_bar(bar: ProgressBar, cur: int, mx: int, show_bar: bool) -> void:
	if bar == null:
		return
	bar.visible = show_bar and mx > 0
	if not bar.visible:
		return
	bar.max_value = 100.0
	bar.value = 100.0 * float(cur) / float(maxi(mx, 1))


func _refresh_multi_strip(entries: Array, show_strip: bool) -> void:
	if _multi_strip == null:
		return
	for c in _multi_strip.get_children():
		c.queue_free()
	_multi_strip.visible = show_strip and not entries.is_empty()
	if not _multi_strip.visible:
		return
	var shown := 0
	const MAX_ICONS := 16
	for e in entries:
		if shown >= MAX_ICONS:
			var more := Label.new()
			more.text = "+%d" % (entries.size() - shown)
			more.add_theme_font_size_override("font_size", 11)
			_multi_strip.add_child(more)
			break
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d := e as Dictionary
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(36, 36)
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = str(d.get("tooltip", ""))
		var icon := _load_icon(str(d.get("icon", "")))
		btn.icon = icon
		btn.expand_icon = true
		if icon == null:
			btn.text = str(d.get("type_id", "?")).substr(0, 3)
		var is_pri := bool(d.get("is_primary", false))
		btn.modulate = Color(1.15, 1.05, 0.55) if is_pri else Color(0.85, 0.85, 0.88)
		var iid := int(d.get("instance_id", 0))
		btn.pressed.connect(_on_multi_strip_pressed.bind(iid))
		_multi_strip.add_child(btn)
		shown += 1


func _on_multi_strip_pressed(instance_id: int) -> void:
	multi_select_clicked.emit(instance_id)


## 建造进度（中栏）；ratio 0..1。visible=false 时隐藏整行。
func set_build_progress(visible_on: bool, ratio: float = 0.0, caption: String = "") -> void:
	if _build_row:
		_build_row.visible = visible_on
	if not visible_on:
		return
	var r := clampf(ratio, 0.0, 1.0)
	if _build_bar:
		_build_bar.value = r * 100.0
	if _build_label:
		if caption.is_empty():
			_build_label.text = "建造 %d%%" % int(round(r * 100.0))
		else:
			_build_label.text = caption


func clear_build_progress() -> void:
	set_build_progress(false)


func _style_center_panel() -> void:
	if _center_host == null:
		return
	var panel := _center_host.get_node_or_null("InfoFrame") as PanelContainer
	if panel == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.9)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.45, 0.5, 0.55, 0.7)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	if _unit_name:
		_unit_name.add_theme_font_size_override("font_size", 16)
		_unit_name.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	if _unit_hp:
		_unit_hp.add_theme_color_override("font_color", Color(0.55, 0.9, 0.55))
		_unit_hp.add_theme_font_size_override("font_size", 12)
	if _attack_line:
		_attack_line.add_theme_color_override("font_color", Color(0.9, 0.82, 0.55))
	if _armor_line:
		_armor_line.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
	if _special_lines:
		_special_lines.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72))
	if _build_bar:
		_build_bar.min_value = 0.0
		_build_bar.max_value = 100.0
		_build_bar.show_percentage = false
		_build_bar.custom_minimum_size = Vector2(0, 14)
	_style_resource_bar(_portrait_hp, Color(0.2, 0.55, 0.22), Color(0.12, 0.14, 0.12))
	_style_resource_bar(_portrait_mana, Color(0.25, 0.4, 0.85), Color(0.1, 0.12, 0.18))


func _style_resource_bar(bar: ProgressBar, fill: Color, bg: Color) -> void:
	if bar == null:
		return
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = bg
	bg_sb.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg_sb)
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = fill
	fill_sb.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill_sb)


## 兼容旧调用：仅文字标签。
func set_command_labels(labels: PackedStringArray) -> void:
	var card: Array[Dictionary] = []
	card.resize(12)
	for i in range(12):
		var e: Dictionary = {}
		if i < labels.size() and not str(labels[i]).is_empty():
			e["id"] = "slot_%d" % i
			e["text"] = str(labels[i])
			e["tooltip"] = str(labels[i])
			e["enabled"] = true
		card[i] = e
	set_command_card(card)


func clear_command_labels() -> void:
	set_command_card([])


## entries：长度最多 12；每项 Dictionary：
## id / text / tooltip / icon / icon_disabled / hotkey_label / executing / enabled
func set_command_card(entries: Array) -> void:
	if _command_grid == null:
		return
	_slot_action_ids = PackedStringArray()
	_slot_action_ids.resize(_command_grid.get_child_count())
	for i in range(_command_grid.get_child_count()):
		var btn := _command_grid.get_child(i) as Button
		if btn == null:
			continue
		var entry: Dictionary = {}
		if i < entries.size() and entries[i] is Dictionary:
			entry = entries[i] as Dictionary
		_apply_command_button(btn, i, entry)


## 只刷新执行中态（避免整卡重建闪烁）。
func set_command_executing(action_id: String, executing: bool) -> void:
	if _command_grid == null or action_id.is_empty():
		return
	for i in range(_command_grid.get_child_count()):
		if i >= _slot_action_ids.size():
			break
		if str(_slot_action_ids[i]) != action_id:
			continue
		var btn := _command_grid.get_child(i) as Button
		if btn == null:
			continue
		_set_button_executing(btn, executing)
		if action_id == "move":
			btn.tooltip_text = _plain_tooltip(_move_tooltip(executing))
			# 有图标时不盖「执行中」字，只靠 modulate 高亮
			if btn.icon == null:
				btn.text = "执行中" if executing else ""
			else:
				btn.text = ""
		break


func set_status(text: String) -> void:
	if _status:
		_status.text = text


func set_portrait_texture(_tex: Texture2D) -> void:
	## 已改用 3D UnitPortraitView；保留空实现以免旧调用报错。
	pass


func set_minimap_texture(tex: Texture2D) -> void:
	_ensure_game_minimap()
	if _game_minimap != null:
		_game_minimap.set_background_texture(tex)


func _apply_command_button(btn: Button, slot: int, entry: Dictionary) -> void:
	var action_id := str(entry.get("id", "")).strip_edges()
	_slot_action_ids[slot] = action_id
	var enabled := bool(entry.get("enabled", not action_id.is_empty()))
	if action_id.is_empty():
		btn.text = ""
		btn.icon = null
		btn.disabled = true
		btn.tooltip_text = ""
		btn.modulate = Color(1, 1, 1, 0.55)
		btn.focus_mode = Control.FOCUS_NONE
		return
	btn.disabled = not enabled
	btn.focus_mode = Control.FOCUS_ALL
	btn.tooltip_text = _plain_tooltip(str(entry.get("tooltip", "")))
	var executing := bool(entry.get("executing", false))
	# 有图标时尽量不盖字；执行中只靠高亮 + tooltip。
	var text := str(entry.get("text", ""))
	var icon_rel := str(entry.get("icon", ""))
	if not enabled:
		var dis := str(entry.get("icon_disabled", ""))
		if not dis.is_empty():
			icon_rel = dis
	var icon := _load_icon(icon_rel)
	btn.icon = icon
	btn.expand_icon = true
	if icon != null and (text.is_empty() or text == "执行中"):
		btn.text = ""
	else:
		if executing and text.is_empty():
			text = "执行中"
		btn.text = text
	_set_button_executing(btn, executing)


func _set_button_executing(btn: Button, executing: bool) -> void:
	# 对齐原作：进行中命令格高亮
	btn.modulate = Color(1.15, 1.05, 0.55) if executing else Color.WHITE


func _move_tooltip(executing: bool) -> String:
	var body := "移动 (M)\n命令单位移动到指定地点。"
	if executing:
		return body + "\n当前：执行中"
	return body


func _plain_tooltip(raw: String) -> String:
	var re := RegEx.new()
	if re.compile("\\|c[0-9a-fA-F]{8}") != OK:
		return raw.replace("|r", "")
	var s := re.sub(raw, "", true)
	return s.replace("|r", "")


func _load_icon(rel_or_res: String) -> Texture2D:
	# asset-converted 有 .gdignore，不能 ResourceLoader.load；走磁盘 Image → Texture2D。
	if rel_or_res.is_empty():
		return null
	var path := RuntimeAssets.converted_path(rel_or_res)
	if _icon_cache.has(path):
		return _icon_cache[path] as Texture2D
	var tex := RuntimeAssets.load_texture(path)
	if tex != null:
		_icon_cache[path] = tex
	return tex


## 临时美化：深色面板 + 金边命令格（日后可换 WC3 Console 皮）。
func _style_command_panel() -> void:
	if _command_panel:
		var panel_sb := StyleBoxFlat.new()
		panel_sb.bg_color = Color(0.06, 0.07, 0.1, 0.94)
		panel_sb.set_border_width_all(2)
		panel_sb.border_color = Color(0.62, 0.48, 0.2, 0.95)
		panel_sb.set_corner_radius_all(6)
		panel_sb.content_margin_left = 10
		panel_sb.content_margin_right = 10
		panel_sb.content_margin_top = 8
		panel_sb.content_margin_bottom = 10
		panel_sb.shadow_color = Color(0, 0, 0, 0.45)
		panel_sb.shadow_size = 6
		_command_panel.add_theme_stylebox_override("panel", panel_sb)
	if _command_title:
		_command_title.add_theme_color_override("font_color", Color(0.92, 0.82, 0.45))
		_command_title.add_theme_font_size_override("font_size", 14)
		_command_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _command_grid == null:
		return
	_command_grid.add_theme_constant_override("h_separation", 6)
	_command_grid.add_theme_constant_override("v_separation", 6)
	var normal := _make_cmd_stylebox(Color(0.14, 0.15, 0.2, 1.0), Color(0.55, 0.44, 0.2))
	var hover := _make_cmd_stylebox(Color(0.22, 0.2, 0.14, 1.0), Color(0.85, 0.7, 0.28))
	var pressed := _make_cmd_stylebox(Color(0.28, 0.24, 0.12, 1.0), Color(1.0, 0.85, 0.35))
	var disabled := _make_cmd_stylebox(Color(0.1, 0.1, 0.12, 0.85), Color(0.28, 0.28, 0.3))
	for i in range(_command_grid.get_child_count()):
		var btn := _command_grid.get_child(i) as Button
		if btn == null:
			continue
		btn.custom_minimum_size = Vector2(52, 52)
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", pressed)
		btn.add_theme_stylebox_override("disabled", disabled)
		btn.add_theme_stylebox_override("focus", hover)
		btn.add_theme_color_override("font_color", Color(0.95, 0.9, 0.55))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.65))
		btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.48))
		btn.add_theme_font_size_override("font_size", 11)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.expand_icon = true
		btn.clip_text = true


func _make_cmd_stylebox(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _wire_command_buttons() -> void:
	if _command_grid == null:
		return
	for i in range(_command_grid.get_child_count()):
		var btn := _command_grid.get_child(i) as Button
		if btn == null:
			continue
		if not btn.pressed.is_connected(_on_command_pressed.bind(i)):
			btn.pressed.connect(_on_command_pressed.bind(i))


func _on_command_pressed(slot: int) -> void:
	command_pressed.emit(slot)
	var action_id := ""
	if slot >= 0 and slot < _slot_action_ids.size():
		action_id = str(_slot_action_ids[slot])
	if not action_id.is_empty():
		command_action.emit(action_id)


func _wire_minimap_input() -> void:
	_ensure_game_minimap()
	if _game_minimap != null:
		if not _game_minimap.clicked.is_connected(_on_game_minimap_clicked):
			_game_minimap.clicked.connect(_on_game_minimap_clicked)
		return
	# 兼容旧 ColorRect 占位
	if _minimap == null:
		return
	if not _minimap.gui_input.is_connected(_on_minimap_gui_input):
		_minimap.gui_input.connect(_on_minimap_gui_input)


func _on_game_minimap_clicked(uv: Vector2) -> void:
	minimap_clicked.emit(uv)


func _on_minimap_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var sz := _minimap.size
			if sz.x < 1.0 or sz.y < 1.0:
				return
			var uv := Vector2(mb.position.x / sz.x, mb.position.y / sz.y)
			uv = uv.clamp(Vector2.ZERO, Vector2.ONE)
			minimap_clicked.emit(uv)
			_minimap.accept_event()
