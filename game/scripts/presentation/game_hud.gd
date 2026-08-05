class_name GameHud
extends CanvasLayer

## 开发期逻辑 HUD：默认 Control，不绑 WC3 Console 贴图。
## API 稳定，日后可换皮而不改 Director / Session。

signal command_pressed(slot: int)
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
@onready var _bottom: Control = $Root/BottomConsole


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


func set_command_labels(labels: PackedStringArray) -> void:
	if _command_grid == null:
		return
	for i in range(_command_grid.get_child_count()):
		var btn := _command_grid.get_child(i) as Button
		if btn == null:
			continue
		if i < labels.size() and not str(labels[i]).is_empty():
			btn.text = str(labels[i])
		else:
			btn.text = str(i)


func clear_command_labels() -> void:
	set_command_labels(PackedStringArray())


func set_status(text: String) -> void:
	if _status:
		_status.text = text


## 兼容旧调用：开发期无肖像贴图。
func set_portrait_texture(_tex: Texture2D) -> void:
	pass


## 兼容旧调用：小地图暂为色块，点击仍发 uv。
func set_minimap_texture(_tex: Texture2D) -> void:
	pass


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
