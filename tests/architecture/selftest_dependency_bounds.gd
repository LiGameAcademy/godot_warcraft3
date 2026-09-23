extends Node

## D0 架构门禁：依赖禁区静态扫描（基线）。
## 禁止在 packages 目标区域（及当前等价路径）新增对应用配置的硬编码引用。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ARCH BOUNDS: " + label)


func _ready() -> void:
	# 契约文档必须存在
	check(FileAccess.file_exists("res://docs/architecture/STATE_OWNERS.md"), "STATE_OWNERS.md")
	check(FileAccess.file_exists("res://docs/architecture/DEPENDENCY_BOUNDS.md"), "DEPENDENCY_BOUNDS.md")
	check(FileAccess.file_exists("res://docs/architecture/PRODUCT_AUTOLOADS.md"), "PRODUCT_AUTOLOADS.md")

	# 活跃代码不得再引用已迁走的旧路径（D1 清零）
	var stale := [
		"res://game/scripts/game_director.gd",
		"res://game/scripts/session/game_session.gd",
		"res://game/features/match/",
		"res://game/scripts/logic/command/unit_order.gd",
		"res://game/scripts/logic/command/order_queue.gd",
	]
	var roots: Array[String] = [
		"res://game/app",
		"res://game/match",
		"res://game/entities",
		"res://game/features",
	]
	for pattern in stale:
		var hit := _scan_contains(roots, pattern)
		check(hit.is_empty(), "无旧路径 %s（命中: %s）" % [pattern, ",".join(hit)])

	# 新目录存在
	check(FileAccess.file_exists("res://game/app/game_director.gd"), "game/app/game_director.gd")
	check(FileAccess.file_exists("res://game/match/game_session.gd"), "game/match/game_session.gd")
	check(FileAccess.file_exists("res://game/entities/commands/unit_order.gd"), "entities/commands/unit_order.gd")

	print("selftest_dependency_bounds: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _scan_contains(dirs: Array[String], needle: String) -> PackedStringArray:
	var hits: PackedStringArray = []
	for d in dirs:
		_scan_dir(d, needle, hits)
	return hits


func _scan_dir(path: String, needle: String, hits: PackedStringArray) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := path.path_join(name)
		if dir.current_is_dir():
			_scan_dir(full, needle, hits)
		elif name.ends_with(".gd") or name.ends_with(".tscn"):
			var txt := FileAccess.get_file_as_string(full)
			if txt.contains(needle):
				hits.append(full)
		name = dir.get_next()
	dir.list_dir_end()
