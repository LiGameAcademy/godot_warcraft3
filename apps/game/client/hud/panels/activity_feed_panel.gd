class_name ActivityFeedPanel
extends VBoxContainer

## 左下角全局活动条：当前训练/研发进度（不依赖选中）。

const _ACTIVITY_ICON := 28

var _icon_cache: HudIconCache = HudIconCache.new()
var _activity_sig: String = ""


func set_entries(entries: Array) -> void:
	if entries.is_empty():
		clear_entries()
		return
	visible = true
	var sig := ""
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d := e as Dictionary
		sig += "%s:%s;" % [str(d.get("kind", "")), str(d.get("id", ""))]
	if sig != _activity_sig or get_child_count() != entries.size():
		_activity_sig = sig
		_rebuild(entries)
	else:
		_refresh(entries)


func clear_entries() -> void:
	_activity_sig = ""
	for c in get_children():
		c.queue_free()
	visible = false


## 响应式：贴在小地图上方，宽度与小地图对齐。
func apply_layout(width: float, bottom_of_feed: float, margin: float, max_height: float = 200.0) -> void:
	var w := maxf(width, 120.0)
	var m := maxf(margin, 4.0)
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = m
	offset_right = m + w
	offset_bottom = -maxf(bottom_of_feed, m)
	offset_top = offset_bottom - maxf(max_height, 64.0)


func _rebuild(entries: Array) -> void:
	for c in get_children():
		c.queue_free()
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d := e as Dictionary
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(_ACTIVITY_ICON, _ACTIVITY_ICON)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex_path := str(d.get("icon", ""))
		if not tex_path.is_empty():
			icon.texture = _icon_cache.load_icon(tex_path)
		row.add_child(icon)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 1)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title := Label.new()
		var kind := str(d.get("kind", ""))
		var prefix := "训练"
		if kind == "research":
			prefix = "研发"
		elif kind == "upgrade":
			prefix = "升本"
		title.text = "%s · %s" % [prefix, str(d.get("name", d.get("id", "")))]
		title.add_theme_font_size_override("font_size", 12)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(title)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 10)
		bar.max_value = 100.0
		bar.value = clampf(float(d.get("progress", 0.0)), 0.0, 1.0) * 100.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(bar)
		row.add_child(col)
		add_child(row)


func _refresh(entries: Array) -> void:
	var i := 0
	for c in get_children():
		if i >= entries.size():
			break
		if typeof(entries[i]) != TYPE_DICTIONARY:
			i += 1
			continue
		var d: Dictionary = entries[i]
		if c is HBoxContainer and c.get_child_count() >= 2:
			var col := c.get_child(1)
			if col is VBoxContainer and col.get_child_count() >= 2:
				var bar := col.get_child(1) as ProgressBar
				if bar != null:
					bar.value = clampf(float(d.get("progress", 0.0)), 0.0, 1.0) * 100.0
		i += 1
