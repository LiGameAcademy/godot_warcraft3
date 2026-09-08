class_name UnitBuffStrip
extends HBoxContainer

## 单位 Buff 图标条（Present）：常驻高度；HBox 横向图标；悬停 tooltip；即将结束闪烁。

const ICON_SIZE := 28
## 原作约 10s 内闪烁
const BLINK_LEFT_SEC := 10.0
const BLINK_HZ := 3.0

var _entry_sig: String = ""
var _blink_phase: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, ICON_SIZE)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visible = true
	set_process(true)


func set_entries(entries: Array) -> void:
	var sig := _build_sig(entries)
	if sig == _entry_sig and get_child_count() == entries.size():
		_update_tooltips_and_left(entries)
		return
	_entry_sig = sig
	for c in get_children():
		c.queue_free()
	for raw in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var e := raw as Dictionary
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		btn.focus_mode = Control.FOCUS_NONE
		btn.flat = true
		btn.expand_icon = true
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.tooltip_text = str(e.get("tooltip", "")).strip_edges()
		btn.set_meta("buff_left", float(e.get("left", 0.0)))
		btn.set_meta("buff_id", str(e.get("id", "")))
		var icon_rel := str(e.get("icon", "")).strip_edges()
		if not icon_rel.is_empty():
			var tex := _load_icon(icon_rel)
			if tex != null:
				btn.icon = tex
		if btn.icon == null:
			btn.text = str(e.get("short", "?")).substr(0, 2)
		add_child(btn)


func clear() -> void:
	_entry_sig = ""
	for c in get_children():
		c.queue_free()


func _process(delta: float) -> void:
	if delta <= 0.0 or get_child_count() == 0:
		return
	_blink_phase += delta * BLINK_HZ * TAU
	var pulse := 0.45 + 0.55 * (0.5 + 0.5 * sin(_blink_phase))
	for c in get_children():
		var btn := c as Button
		if btn == null:
			continue
		var left := float(btn.get_meta("buff_left", 0.0))
		# left < 0：光环等常驻展示，不闪烁
		if left > 0.0 and left <= BLINK_LEFT_SEC:
			btn.modulate = Color(1, 1, 1, pulse)
		else:
			btn.modulate = Color.WHITE


func _build_sig(entries: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for raw in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var e := raw as Dictionary
		parts.append(str(e.get("id", "")))
	return "|".join(parts)


func _update_tooltips_and_left(entries: Array) -> void:
	var i := 0
	for raw in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if i >= get_child_count():
			break
		var e := raw as Dictionary
		var btn := get_child(i) as Button
		if btn != null:
			btn.tooltip_text = str(e.get("tooltip", "")).strip_edges()
			btn.set_meta("buff_left", float(e.get("left", 0.0)))
		i += 1


static func _load_icon(rel_or_res: String) -> Texture2D:
	if rel_or_res.is_empty():
		return null
	var path := RuntimeAssets.converted_path(rel_or_res)
	return RuntimeAssets.load_texture(path)
