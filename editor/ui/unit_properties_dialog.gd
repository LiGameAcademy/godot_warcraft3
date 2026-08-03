extends Window
## WE「单位属性」模态：普通 / 技能（有技能才显示）/ 掉落物品。


signal confirmed(entry: Dictionary)
signal cancelled

const ACQ_NORMAL := -1.0
const ACQ_CAMP := -2.0
const UnitEditCommandScript := preload("res://editor/scripts/commands/unit_edit_command.gd")

var _entry: Dictionary = {}
var _before: Dictionary = {}
var _catalog: Wc3IdCatalog = null
var _document = null
var _history: EditorCommandHistory = null

var _tabs: TabContainer
var _tab_general: Control
var _tab_skills: Control
var _tab_drops: Control

var _icon: TextureRect
var _title_label: Label
var _level_label: Label
var _owner_opt: OptionButton
var _facing_spin: SpinBox
var _hp_spin: SpinBox
var _hp_max_label: Label
var _mp_spin: SpinBox
var _mp_max_label: Label
var _acq_normal: CheckBox
var _acq_camp: CheckBox
var _skills_list: ItemList
var _drops_list: ItemList
var _ok_btn: Button
var _cancel_btn: Button

var _max_hp: int = 100
var _max_mp: int = 0
var _type_abil_ids: PackedStringArray = PackedStringArray()


func _ready() -> void:
	title = EditorI18n.t("EDITOR_UNIT_PROPS_TITLE")
	exclusive = true
	unresizable = false
	size = Vector2i(420, 380)
	min_size = Vector2i(360, 320)
	_build_ui()
	close_requested.connect(_on_cancel)
	if not EditorI18n.locale_changed.is_connected(_on_locale):
		EditorI18n.locale_changed.connect(_on_locale)
	hide()


func setup(catalog: Wc3IdCatalog = null, document = null, history: EditorCommandHistory = null) -> void:
	_catalog = catalog
	_document = document
	_history = history


## 打开并编辑一条单位（AoS Dictionary，含 creationNumber）。
func open_for_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	_before = entry.duplicate(true)
	_entry = entry.duplicate(true)
	_refresh_header()
	_load_balance_caps()
	_load_type_abilities()
	_populate_general()
	_populate_skills()
	_populate_drops()
	_apply_locale()
	_update_skills_tab_visibility()
	popup_centered()
	grab_focus()


func _on_locale(_loc: String = "") -> void:
	_apply_locale()


func _apply_locale() -> void:
	title = EditorI18n.t("EDITOR_UNIT_PROPS_TITLE")
	if _ok_btn:
		_ok_btn.text = EditorI18n.t("EDITOR_DIALOG_OK")
	if _cancel_btn:
		_cancel_btn.text = EditorI18n.t("EDITOR_DIALOG_CANCEL")
	if _tabs:
		_tabs.set_tab_title(0, EditorI18n.t("EDITOR_UNIT_PROPS_TAB_GENERAL"))
		var skills_i := _tabs.get_tab_idx_from_control(_tab_skills) if _tab_skills else -1
		var drops_i := _tabs.get_tab_idx_from_control(_tab_drops) if _tab_drops else -1
		if skills_i >= 0:
			_tabs.set_tab_title(skills_i, EditorI18n.t("EDITOR_UNIT_PROPS_TAB_SKILLS"))
		if drops_i >= 0:
			_tabs.set_tab_title(drops_i, EditorI18n.t("EDITOR_UNIT_PROPS_TAB_DROPS"))
	_localize_labeled_fields(_tab_general)
	if _tab_skills:
		var hint := _tab_skills.find_child("SkillsHint", true, false) as Label
		if hint:
			hint.text = EditorI18n.t("EDITOR_UNIT_PROPS_SKILLS_HINT")
	if _tab_drops:
		var dt := _tab_drops.find_child("DropsTitle", true, false) as Label
		if dt:
			dt.text = EditorI18n.t("EDITOR_UNIT_PROPS_DROPS_TITLE")
		var dn := _tab_drops.find_child("DropsNote", true, false) as Label
		if dn:
			dn.text = EditorI18n.t("EDITOR_UNIT_PROPS_DROPS_NOTE")
	if _acq_normal:
		_acq_normal.text = EditorI18n.t("EDITOR_UNIT_PROPS_ACQ_NORMAL", [500])
	if _acq_camp:
		_acq_camp.text = EditorI18n.t("EDITOR_UNIT_PROPS_ACQ_CAMP", [200])


func _localize_labeled_fields(root: Node) -> void:
	if root == null:
		return
	for c in root.find_children("*", "Label", true, false):
		var l := c as Label
		if l == null:
			continue
		var key: String = str(l.get_meta("i18n_key", ""))
		if not key.is_empty():
			l.text = EditorI18n.t(key)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(48, 48)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(_icon)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 16)
	titles.add_child(_title_label)
	_level_label = Label.new()
	titles.add_child(_level_label)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	_tab_general = _make_general_tab()
	_tab_general.name = "General"
	_tabs.add_child(_tab_general)

	_tab_skills = _make_skills_tab()
	_tab_skills.name = "Skills"
	_tabs.add_child(_tab_skills)

	_tab_drops = _make_drops_tab()
	_tab_drops.name = "Drops"
	_tabs.add_child(_tab_drops)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	root.add_child(buttons)
	_ok_btn = Button.new()
	_ok_btn.custom_minimum_size = Vector2(88, 0)
	_ok_btn.pressed.connect(_on_ok)
	buttons.add_child(_ok_btn)
	_cancel_btn = Button.new()
	_cancel_btn.custom_minimum_size = Vector2(88, 0)
	_cancel_btn.pressed.connect(_on_cancel)
	buttons.add_child(_cancel_btn)


func _make_general_tab() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	margin.add_child(grid)

	grid.add_child(_make_field_label("EDITOR_UNIT_PROPS_OWNER"))
	_owner_opt = OptionButton.new()
	_owner_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_owner_opt)
	_fill_owner_options()

	grid.add_child(_make_field_label("EDITOR_UNIT_PROPS_FACING"))
	_facing_spin = SpinBox.new()
	_facing_spin.min_value = 0.0
	_facing_spin.max_value = 359.99
	_facing_spin.step = 0.01
	_facing_spin.allow_greater = false
	_facing_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_facing_spin)

	grid.add_child(_make_field_label("EDITOR_UNIT_PROPS_HP_PCT"))
	var hp_row := HBoxContainer.new()
	_hp_spin = SpinBox.new()
	_hp_spin.min_value = 1
	_hp_spin.max_value = 100
	_hp_spin.step = 1
	_hp_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_row.add_child(_hp_spin)
	_hp_max_label = Label.new()
	hp_row.add_child(_hp_max_label)
	grid.add_child(hp_row)

	grid.add_child(_make_field_label("EDITOR_UNIT_PROPS_MP"))
	var mp_row := HBoxContainer.new()
	_mp_spin = SpinBox.new()
	_mp_spin.min_value = 0
	_mp_spin.max_value = 99999
	_mp_spin.step = 1
	_mp_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp_row.add_child(_mp_spin)
	_mp_max_label = Label.new()
	mp_row.add_child(_mp_max_label)
	grid.add_child(mp_row)

	grid.add_child(_make_field_label("EDITOR_UNIT_PROPS_ACQ"))
	var acq := VBoxContainer.new()
	_acq_normal = CheckBox.new()
	_acq_normal.button_group = ButtonGroup.new()
	_acq_camp = CheckBox.new()
	_acq_camp.button_group = _acq_normal.button_group
	acq.add_child(_acq_normal)
	acq.add_child(_acq_camp)
	grid.add_child(acq)
	return margin


func _make_skills_tab() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	var v := VBoxContainer.new()
	margin.add_child(v)
	var hint := Label.new()
	hint.name = "SkillsHint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "EDITOR_UNIT_PROPS_SKILLS_HINT"
	v.add_child(hint)
	_skills_list = ItemList.new()
	_skills_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skills_list.custom_minimum_size = Vector2(0, 160)
	v.add_child(_skills_list)
	return margin


func _make_drops_tab() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	var v := VBoxContainer.new()
	margin.add_child(v)
	var title := Label.new()
	title.name = "DropsTitle"
	title.text = "EDITOR_UNIT_PROPS_DROPS_TITLE"
	v.add_child(title)
	_drops_list = ItemList.new()
	_drops_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drops_list.custom_minimum_size = Vector2(0, 180)
	v.add_child(_drops_list)
	var note := Label.new()
	note.name = "DropsNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "EDITOR_UNIT_PROPS_DROPS_NOTE"
	v.add_child(note)
	return margin


func _make_field_label(key: String) -> Label:
	var l := Label.new()
	l.text = key
	l.set_meta("i18n_key", key)
	return l


func _fill_owner_options() -> void:
	_owner_opt.clear()
	for p in range(12):
		_owner_opt.add_item(EditorI18n.t("EDITOR_UNIT_OWNER_PLAYER_N", [p + 1]))
		_owner_opt.set_item_metadata(_owner_opt.item_count - 1, p)
	_owner_opt.add_item(EditorI18n.t("EDITOR_UNIT_OWNER_NEUTRAL_HOSTILE"))
	_owner_opt.set_item_metadata(_owner_opt.item_count - 1, 12)
	_owner_opt.add_item(EditorI18n.t("EDITOR_UNIT_OWNER_NEUTRAL_PASSIVE"))
	_owner_opt.set_item_metadata(_owner_opt.item_count - 1, 15)


func _refresh_header() -> void:
	var tid := str(_entry.get("typeId", ""))
	var info: Dictionary = {}
	if _catalog != null:
		info = _catalog.lookup(tid)
	var display := str(info.get("name", tid))
	if display.is_empty():
		display = tid
	var cn := int(_entry.get("creationNumber", -1))
	_title_label.text = "%s (%d)" % [display, maxi(cn, 0)]
	var level := _lookup_unit_level(tid)
	_level_label.text = EditorI18n.t("EDITOR_UNIT_PROPS_LEVEL", [level])
	if _catalog != null and _catalog.has_method("unit_art_texture"):
		var tex: Texture2D = _catalog.unit_art_texture(tid)
		_icon.texture = tex


func _lookup_unit_level(type_id: String) -> int:
	var bal := _read_unit_balance(type_id)
	return int(bal.get("level", int(_entry.get("heroLevel", 1))))


func _load_balance_caps() -> void:
	var tid := str(_entry.get("typeId", ""))
	var bal := _read_unit_balance(tid)
	_max_hp = maxi(int(bal.get("HP", bal.get("realHP", 100))), 1)
	_max_mp = maxi(int(bal.get("manaN", bal.get("realM", 0))), 0)
	_hp_max_label.text = str(_max_hp)
	_mp_max_label.text = str(_max_mp)
	_mp_spin.max_value = maxf(float(_max_mp), 1.0)
	_mp_spin.editable = _max_mp > 0


func _read_unit_balance(type_id: String) -> Dictionary:
	if type_id.is_empty():
		return {}
	var path := RuntimeAssets.slk_path("Units/UnitBalance.json")
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	for rec in (data as Dictionary).get("records", []):
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		if str((rec as Dictionary).get("unitBalanceID", "")) == type_id:
			return rec as Dictionary
	return {}


func _load_type_abilities() -> void:
	_type_abil_ids = PackedStringArray()
	var tid := str(_entry.get("typeId", ""))
	if tid.is_empty():
		return
	var path := RuntimeAssets.slk_path("Units/UnitAbilities.json")
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	for rec in (data as Dictionary).get("records", []):
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var d := rec as Dictionary
		if str(d.get("unitAbilID", "")) != tid:
			continue
		var list := str(d.get("abilList", "")).strip_edges()
		if list.is_empty() or list == "_":
			return
		for part in list.split(",", false):
			var code := str(part).strip_edges()
			if not code.is_empty() and code != "_":
				_type_abil_ids.append(code)
		return


func _populate_general() -> void:
	var owner := clampi(int(_entry.get("owner", 0)), 0, 15)
	for i in range(_owner_opt.item_count):
		if int(_owner_opt.get_item_metadata(i)) == owner:
			_owner_opt.select(i)
			break
	var deg := float(_entry.get("angleDegrees", rad_to_deg(float(_entry.get("angle", 0.0)))))
	_facing_spin.value = fposmod(deg, 360.0)
	var hp := float(_entry.get("hitPoints", -1.0))
	_hp_spin.value = 100.0 if hp < 0.0 else clampf(hp, 1.0, 100.0)
	var mp := float(_entry.get("manaPoints", -1.0))
	if _max_mp <= 0:
		_mp_spin.value = 0
	elif mp < 0.0:
		_mp_spin.value = float(_max_mp)
	else:
		_mp_spin.value = clampf(mp, 0.0, float(_max_mp))
	var acq := float(_entry.get("targetAcquisition", ACQ_NORMAL))
	var is_camp := absf(acq - ACQ_CAMP) < 0.01 or absf(acq - 200.0) < 0.5
	_acq_camp.button_pressed = is_camp
	_acq_normal.button_pressed = not is_camp
	_acq_normal.text = EditorI18n.t("EDITOR_UNIT_PROPS_ACQ_NORMAL", [500])
	_acq_camp.text = EditorI18n.t("EDITOR_UNIT_PROPS_ACQ_CAMP", [200])


func _populate_skills() -> void:
	_skills_list.clear()
	for code in _type_abil_ids:
		_skills_list.add_item("%s" % code)
	var placed: Variant = _entry.get("abilities", [])
	if typeof(placed) == TYPE_ARRAY:
		for a in placed as Array:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var d := a as Dictionary
			var id := str(d.get("id", ""))
			if id.is_empty():
				continue
			var active := int(d.get("active", 0)) != 0
			var level := int(d.get("level", 1))
			_skills_list.add_item("%s  lv%d  %s" % [id, level, "ON" if active else "OFF"])


func _populate_drops() -> void:
	_drops_list.clear()
	var store := get_node_or_null("/root/Wc3DefStore")
	if store != null and store.has_method("ensure_table"):
		store.ensure_table(ItemDef.TABLE_NAME)
	var rows := Wc3DroppedItemEntry.flatten_rows(_entry.get("droppedItemSets", []))
	if rows.is_empty():
		_drops_list.add_item(EditorI18n.t("EDITOR_UNIT_PROPS_DROPS_EMPTY"))
		return
	for row in rows:
		_drops_list.add_item(
			EditorI18n.t(
				"EDITOR_UNIT_PROPS_DROPS_ROW",
				[int(row.get("set_index", 1)), str(row.get("name", "")), int(row.get("chance", 0))]
			)
		)


func _update_skills_tab_visibility() -> void:
	var show_skills := not _type_abil_ids.is_empty()
	var placed: Variant = _entry.get("abilities", [])
	if typeof(placed) == TYPE_ARRAY and not (placed as Array).is_empty():
		show_skills = true
	# 技能系统未完整接入：有技能列表才显示页签
	_tabs.set_tab_hidden(_tabs.get_tab_idx_from_control(_tab_skills), not show_skills)


func _collect_entry() -> Dictionary:
	var out := _entry.duplicate(true)
	var owner := int(_owner_opt.get_item_metadata(_owner_opt.selected))
	out["owner"] = clampi(owner, 0, 15)
	var deg := float(_facing_spin.value)
	out["angleDegrees"] = deg
	out["angle"] = deg_to_rad(deg)
	var hp_pct := float(_hp_spin.value)
	out["hitPoints"] = -1.0 if absf(hp_pct - 100.0) < 0.5 else hp_pct
	if _max_mp <= 0:
		out["manaPoints"] = -1.0
	else:
		var mp := float(_mp_spin.value)
		out["manaPoints"] = -1.0 if absf(mp - float(_max_mp)) < 0.5 else mp
	out["targetAcquisition"] = ACQ_CAMP if _acq_camp.button_pressed else ACQ_NORMAL
	return out


func _on_ok() -> void:
	var after := _collect_entry()
	if _document != null:
		var cn := int(after.get("creationNumber", -1))
		if cn >= 0:
			_document.update_unit_by_creation_number(cn, after)
			if _history != null:
				_history.record(
					UnitEditCommandScript.make_modify([_before], [after], "Edit Unit Props")
				)
	confirmed.emit(after)
	hide()


func _on_cancel() -> void:
	cancelled.emit()
	hide()
