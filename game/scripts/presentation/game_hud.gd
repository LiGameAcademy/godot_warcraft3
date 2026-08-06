class_name GameHud
extends CanvasLayer

## 开发期逻辑 HUD：命令格支持图标 / tooltip / 执行中态；可日后换 WC3 Console 皮。

signal command_pressed(slot: int)
signal command_action(action_id: String)
signal minimap_clicked(uv: Vector2)

@export var map_dir: String = "res://assets/map-parsed/echoisles"
@export var console_height_ratio: float = 0.2
@export var show_dev_hint: bool = true

@onready var _gold_label: Label = %GoldValue
@onready var _lumber_label: Label = %LumberValue
@onready var _food_label: Label = %FoodValue
@onready var _unit_name: Label = %UnitName
@onready var _unit_hp: Label = %UnitHp
@onready var _minimap: Control = %Minimap
@onready var _command_grid: GridContainer = %CommandGrid
@onready var _status: Label = %StatusLabel
@onready var _hint: Label = %HintLabel
@onready var _bottom: Control = $Root/MarginContainer3

## slot → action_id（空=无动作）
var _slot_action_ids: PackedStringArray = PackedStringArray()
var _icon_cache: Dictionary = {} ## path → Texture2D


func _ready() -> void:
	_wire_command_buttons()
	_wire_minimap_input()
	if _hint:
		_hint.visible = show_dev_hint
	set_resources(0, 0, 0, 0)
	set_unit_info("—", 0, 0)
	_apply_bottom_height()
	get_viewport().size_changed.connect(_apply_bottom_height)


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
	if _unit_name:
		_unit_name.text = unit_name if not unit_name.is_empty() else "—"
	if _unit_hp:
		if hp_max > 0:
			_unit_hp.text = "HP %d / %d" % [hp, hp_max]
		else:
			_unit_hp.text = ""


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
			btn.text = "执行中" if executing else ""
		break


func set_status(text: String) -> void:
	if _status:
		_status.text = text


func set_portrait_texture(_tex: Texture2D) -> void:
	pass


func set_minimap_texture(_tex: Texture2D) -> void:
	pass


func _apply_command_button(btn: Button, slot: int, entry: Dictionary) -> void:
	var action_id := str(entry.get("id", "")).strip_edges()
	_slot_action_ids[slot] = action_id
	var enabled := bool(entry.get("enabled", not action_id.is_empty()))
	if action_id.is_empty():
		btn.text = ""
		btn.icon = null
		btn.disabled = true
		btn.tooltip_text = ""
		btn.modulate = Color.WHITE
		btn.focus_mode = Control.FOCUS_NONE
		return
	btn.disabled = not enabled
	btn.focus_mode = Control.FOCUS_ALL
	btn.tooltip_text = _plain_tooltip(str(entry.get("tooltip", "")))
	var executing := bool(entry.get("executing", false))
	var text := str(entry.get("text", ""))
	if executing and text.is_empty():
		text = "执行中"
	btn.text = text
	var icon_rel := str(entry.get("icon", ""))
	if not enabled:
		var dis := str(entry.get("icon_disabled", ""))
		if not dis.is_empty():
			icon_rel = dis
	btn.icon = _load_icon(icon_rel)
	btn.expand_icon = true
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
	if rel_or_res.is_empty():
		return null
	var path := RuntimeAssets.converted_path(rel_or_res)
	if _icon_cache.has(path):
		return _icon_cache[path] as Texture2D
	if not RuntimeAssets.file_exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex != null:
		_icon_cache[path] = tex
	return tex


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
	if _minimap == null:
		return
	if not _minimap.gui_input.is_connected(_on_minimap_gui_input):
		_minimap.gui_input.connect(_on_minimap_gui_input)


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
