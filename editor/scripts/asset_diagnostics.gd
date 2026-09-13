extends RefCounted
## Read-only model reference checks; no document or source asset changes.
static func scan(data: Dictionary, catalog: Wc3IdCatalog) -> Array:
	var groups: Dictionary = {}
	for kind in ["units", "doodads"]:
		for entry in data.get(kind, {}).get(kind, []):
			var id := str(entry.get("typeId" if kind == "units" else "id", ""))
			var variation := int(entry.get("variation", 0))
			var key := "%s:%s:%d" % [kind, id, variation]
			if not groups.has(key):
				var info := catalog.lookup(id)
				var reason := ""
				var source := str(info.get("file", ""))
				if str(info.get("kind", "unknown")) == "unknown":
					reason = "原版对象目录中没有此 ID"
				elif not bool(info.get("use_click_helper", false)) and catalog.converted_glb_path(id, variation).is_empty():
					reason = "未找到可用的转换模型" if not source.is_empty() else "对象定义未提供模型路径"
				groups[key] = {"id": id, "kind": kind, "variation": variation, "source": source, "reason": reason, "count": 0, "instances": []}
			var group: Dictionary = groups[key]
			group.count += 1
			if group.instances.size() < 5:
				group.instances.append(int(entry.get("creationNumber", -1)))
	var issues: Array = []
	for key in groups:
		if not str(groups[key].reason).is_empty():
			issues.append(groups[key])
	return issues

static func report(data: Dictionary, catalog: Wc3IdCatalog) -> String:
	var issues := scan(data, catalog)
	var lines := PackedStringArray(["模型引用检查（只读）", "检查对象 ID 和转换模型路径；不验证模型内部贴图、动画或视觉完整性。", ""])
	if issues.is_empty():
		lines.append("未发现缺失的对象定义或转换模型路径。")
	for issue in issues:
		lines.append("%s · %s · 变体 %d · %d 个实例" % ["单位/建筑" if issue.kind == "units" else "树木/装饰物", issue.id, issue.variation, issue.count])
		lines.append("原因：" + issue.reason)
		lines.append("原版模型路径：" + (issue.source if not issue.source.is_empty() else "未提供"))
		lines.append("实例编号（最多列出 5 个）：" + str(issue.instances))
		lines.append("")
	return "\n".join(lines)

static func show_report(parent: Node, data: Dictionary, catalog: Wc3IdCatalog) -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = "地图资源检查"
	dialog.ok_button_text = EditorI18n.t("EDITOR_DIALOG_OK")
	dialog.min_size = Vector2i(620, 420)
	var text := TextEdit.new()
	text.editable = false
	text.add_theme_color_override("font_readonly_color", Color(0.9, 0.9, 0.9))
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.custom_minimum_size = Vector2(580, 340)
	text.text = report(data, catalog)
	dialog.add_child(text)
	parent.add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
	return dialog
