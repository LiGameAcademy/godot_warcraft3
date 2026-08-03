class_name GameHud
extends CanvasLayer

## 人族游戏 HUD：纯 Control 底栏 + 顶栏资源（对标 WC3 Console 布局）。
##
## 注意：HumanUITile01–04 是 HumanUI.mdx 的 UV 材质切片，不是整屏 2D 外框；
## 不能当 TextureRect 全屏壳用。石质气质先用深色底栏 + Console 控件贴图近似；
## 远期可用 SubViewport(HumanUI.glb) 只替换装饰壳，本 API 不变。

signal command_pressed(slot: int)
signal minimap_clicked(uv: Vector2)

const BTN_UP := "res://assets/asset-converted/UI/Widgets/Console/Human/human-console-button-up.png"
const BTN_DOWN := "res://assets/asset-converted/UI/Widgets/Console/Human/human-console-button-down.png"
const BTN_HI := "res://assets/asset-converted/UI/Widgets/Console/Human/human-console-button-highlight.png"
const DEFAULT_MINIMAP := "res://assets/map-parsed/echoisles/war3mapMap.png"

@export var map_dir: String = "res://assets/map-parsed/echoisles"
@export var console_height_ratio: float = 0.24
@export var show_dev_hint: bool = true

@onready var _gold_label: Label = %GoldValue
@onready var _lumber_label: Label = %LumberValue
@onready var _food_label: Label = %FoodValue
@onready var _unit_name: Label = %UnitName
@onready var _unit_hp: Label = %UnitHp
@onready var _minimap: TextureRect = %Minimap
@onready var _portrait: TextureRect = %Portrait
@onready var _command_grid: GridContainer = %CommandGrid
@onready var _status: Label = %StatusLabel
@onready var _hint: Label = %HintLabel
@onready var _bottom: Control = $Root/BottomConsole

var _btn_up: Texture2D
var _btn_down: Texture2D
var _btn_hi: Texture2D


func _ready() -> void:
	_btn_up = load(BTN_UP) as Texture2D
	_btn_down = load(BTN_DOWN) as Texture2D
	_btn_hi = load(BTN_HI) as Texture2D
	_load_minimap_from_map_dir()
	_wire_command_buttons()
	_wire_minimap_input()
	if _hint:
		_hint.visible = show_dev_hint
	set_resources(750, 200, 5, 11)
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


func set_unit_info(unit_name: String, hp: int, hp_max: int) -> void:
	if _unit_name:
		_unit_name.text = unit_name if not unit_name.is_empty() else "—"
	if _unit_hp:
		if hp_max > 0:
			_unit_hp.text = "%d / %d" % [hp, hp_max]
		else:
			_unit_hp.text = ""


func set_portrait_texture(tex: Texture2D) -> void:
	if _portrait:
		_portrait.texture = tex


func set_minimap_texture(tex: Texture2D) -> void:
	if _minimap:
		_minimap.texture = tex


func set_status(text: String) -> void:
	if _status:
		_status.text = text


func set_command_icon(slot: int, tex: Texture2D) -> void:
	if _command_grid == null or slot < 0 or slot >= _command_grid.get_child_count():
		return
	var btn := _command_grid.get_child(slot) as TextureButton
	if btn == null:
		return
	if tex != null:
		btn.texture_normal = tex
	elif _btn_up != null:
		btn.texture_normal = _btn_up


func _load_minimap_from_map_dir() -> void:
	var path := map_dir.path_join("war3mapMap.png")
	if not ResourceLoader.exists(path):
		path = DEFAULT_MINIMAP
	if ResourceLoader.exists(path):
		set_minimap_texture(load(path) as Texture2D)


func _wire_command_buttons() -> void:
	if _command_grid == null:
		return
	for i in range(_command_grid.get_child_count()):
		var btn := _command_grid.get_child(i) as TextureButton
		if btn == null:
			continue
		if btn.texture_normal == null and _btn_up != null:
			btn.texture_normal = _btn_up
		if btn.texture_pressed == null and _btn_down != null:
			btn.texture_pressed = _btn_down
		if btn.texture_hover == null and _btn_hi != null:
			btn.texture_hover = _btn_hi
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_SCALE
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
