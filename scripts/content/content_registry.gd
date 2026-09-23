class_name ContentRegistry
extends RefCounted

## 内容包挂载与快照构造（D3 第一版）。
## 定义表与资源应消费同一快照；换快照时作废 DefStore / 失败缓存约定由调用方执行。

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
func commit_snapshot(snapshot_id: String = "") -> ContentSnapshot:
	var snap := ContentSnapshot.new()
	snap.snapshot_id = snapshot_id if not snapshot_id.is_empty() else _make_id()
	var ids := PackedStringArray()
	var hash_parts: PackedStringArray = PackedStringArray()
	# AssetProvider 为 Autoload（无 class_name）
	var ap: Node = Engine.get_main_loop().root.get_node_or_null("/root/AssetProvider")
	if ap != null and ap.has_method("clear_overlays"):
		ap.call("clear_overlays")
	for pid in _pending_overlays.keys():
		var root: String = str(_pending_overlays[pid])
		ids.append(str(pid))
		hash_parts.append("%s:%s" % [pid, root])
		if ap != null and ap.has_method("register_overlay"):
			ap.call("register_overlay", str(pid), root)
	snap.package_ids = ids
	snap.content_hash = ",".join(hash_parts).sha256_text() if not hash_parts.is_empty() else "base"
	snap.freeze()
	_current = snap
	_clear_def_store()
	snapshot_changed.emit(snap)
	return snap


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
