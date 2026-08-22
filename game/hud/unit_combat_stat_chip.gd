class_name UnitCombatStatChip
extends HBoxContainer

## 中栏攻防一行：类型图标（可升级时右下角等级角标）+ 数值 + 类型名。
## 数据由 SelectionInfoBuilder 组装；本控件只展示。

const ICON_SIZE := Vector2(28, 28)

@onready var _icon_slot: Control = %IconSlot
@onready var _icon: TextureRect = %Icon
@onready var _level_badge: PanelContainer = %LevelBadge
@onready var _level: Label = %LevelLabel
@onready var _value: Label = %ValueLabel
@onready var _type: Label = %TypeLabel


func _ready() -> void:
	if _icon_slot:
		_icon_slot.custom_minimum_size = ICON_SIZE
	if _icon:
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_style_level_badge()
	mouse_filter = Control.MOUSE_FILTER_PASS


## info 键：type / type_label / value / icon / upgradeable / upgrade_level / tooltip
func set_stat(info: Dictionary) -> void:
	if info.is_empty() or str(info.get("value", "")).is_empty():
		clear()
		return
	visible = true
	var value_s := str(info.get("value", "—"))
	var type_label := str(info.get("type_label", "")).strip_edges()
	var upgradeable := bool(info.get("upgradeable", false))
	var level := int(info.get("upgrade_level", 0))
	var tip := str(info.get("tooltip", "")).strip_edges()
	if _value:
		_value.text = value_s
	if _type:
		_type.text = type_label
		_type.visible = not type_label.is_empty()
	_set_level_badge(upgradeable, level)
	_apply_icon(str(info.get("icon", "")))
	tooltip_text = tip if not tip.is_empty() else _default_tooltip(type_label, value_s, upgradeable, level)


func clear() -> void:
	visible = false
	if _value:
		_value.text = ""
	if _type:
		_type.text = ""
	_set_level_badge(false, 0)
	if _icon:
		_icon.texture = null
	tooltip_text = ""


func _set_level_badge(upgradeable: bool, level: int) -> void:
	if _level_badge == null:
		return
	# 不可升级：完全隐藏角标框；可升级：右下角显示当前等级（含 0）。
	_level_badge.visible = upgradeable
	if _level:
		_level.text = str(maxi(level, 0)) if upgradeable else ""


func _style_level_badge() -> void:
	if _level_badge == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.92)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.85, 0.75, 0.35, 0.95)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	_level_badge.add_theme_stylebox_override("panel", sb)


func _apply_icon(path: String) -> void:
	if _icon == null:
		return
	if path.is_empty():
		_icon.texture = null
		_icon.visible = false
		return
	var tex := RuntimeAssets.load_texture(path)
	_icon.texture = tex
	_icon.visible = tex != null


func _default_tooltip(type_label: String, value_s: String, upgradeable: bool, level: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if not type_label.is_empty():
		parts.append(type_label)
	if not value_s.is_empty():
		parts.append(value_s)
	if upgradeable:
		parts.append("升级 %d" % level)
	return " ".join(parts)
