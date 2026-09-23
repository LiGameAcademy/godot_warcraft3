class_name ContentRegistry
extends RefCounted

## 内容包挂载与快照构造（D3 第一版）。
## 仅启动前允许选择内容；开始对局后 AssetProvider 封闭，换包必须重启应用。

signal snapshot_changed(snapshot: ContentSnapshot)

var _current: ContentSnapshot = null
## mod_id → absolute root
var _pending_overlays: Dictionary = {}


func current_snapshot() -> ContentSnapshot:
	return _current


func register_package(package_id: String, root_abs: String) -> void:
	if package_id.is_empty() or root_abs.is_empty():
		return
	_pending_overlays[package_id] = root_abs.replace("\\", "/").simplify_path()


func clear_packages() -> void:
	_pending_overlays.clear()


## 应用 pending overlays 到 AssetProvider，构造并冻结快照；清空 DefStore 表缓存。
var last_error: String = ""

func commit_snapshot(snapshot_id: String = "") -> ContentSnapshot:
	last_error = ""
	var tree := Engine.get_main_loop() as SceneTree
	var ap: Node = tree.root.get_node_or_null("AssetProvider") if tree != null else null
	if ap == null:
		last_error = "AssetProvider unavailable"
		return null
	if ap.runtime_content_sealed:
		last_error = "Content is in use; restart the application to change packages"
		return null
	var ids := PackedStringArray()
	var parts := PackedStringArray()
	# Validate and hash before modifying any visible overlay or definition cache.
	for pid in _pending_overlays:
		var root: String = _pending_overlays[pid]
		if not DirAccess.dir_exists_absolute(root):
			last_error = "Missing package directory: " + str(pid)
			return null
		var files := PackedStringArray()
		if not _collect_files(root, "", files):
			return null
		files.sort()
		var records: Array = []
		for relative in files:
			var digest := FileAccess.get_sha256(root.path_join(relative))
			if digest.is_empty():
				last_error = "Unreadable package file: " + relative
				return null
			records.append([relative, digest])
		ids.append(str(pid))
		parts.append(JSON.stringify([pid, records]))
	var snap := ContentSnapshot.new()
	snap.snapshot_id = snapshot_id if not snapshot_id.is_empty() else _make_id()
	snap.package_ids = ids
	snap.content_hash = "base" if parts.is_empty() else JSON.stringify(Array(parts)).sha256_text()
	snap.freeze()
	ap.clear_overlays()
	for pid in _pending_overlays:
		ap.register_overlay(str(pid), str(_pending_overlays[pid]))
	_current = snap
	_clear_def_store()
	snapshot_changed.emit(snap)
	return snap

func _collect_files(root: String, relative: String, out: PackedStringArray) -> bool:
	var directory := DirAccess.open(root.path_join(relative))
	if directory == null:
		last_error = "Unreadable package directory: " + relative
		return false
	for name in directory.get_files():
		if directory.is_link(name):
			last_error = "Package symlinks are unsupported"
			return false
		out.append(relative.path_join(name))
	for name in directory.get_directories():
		if directory.is_link(name):
			last_error = "Package symlinks are unsupported"
			return false
		if not _collect_files(root, relative.path_join(name), out):
			return false
	return true


## 仅基础内容（清 overlay）。
func commit_base_snapshot() -> ContentSnapshot:
	clear_packages()
	return commit_snapshot("base")


func _clear_def_store() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var store: Node = tree.root.get_node_or_null("/root/Wc3DefStore")
	if store != null and store.has_method("clear_loaded_tables"):
		store.call("clear_loaded_tables")


func _make_id() -> String:
	return "snap_%d" % Time.get_ticks_msec()
