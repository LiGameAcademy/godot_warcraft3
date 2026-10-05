extends SceneTree

var _failures: int = 0
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var guard_script: GDScript = load("res://app/asset_import_guard.gd")
	var root_path: String = "user://guard-test-%s" % Time.get_ticks_usec()
	var a: RefCounted = guard_script.new()
	var b: RefCounted = guard_script.new()
	_check(a.acquire(root_path) == OK, "first writer")
	_check(b.acquire(root_path) == ERR_BUSY, "second writer excluded")
	a.track_child(OS.get_process_id())
	a.track_child(OS.get_process_id())
	var owner_path: String = ProjectSettings.globalize_path(root_path).path_join(".import-lock/owner.json")
	var owner: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(owner_path))
	_check(owner.children.size() == 1, "only current child retained")
	a.track_child(-1)
	owner = JSON.parse_string(FileAccess.get_file_as_string(owner_path))
	_check(owner.children.is_empty(), "completed child removed")
	a.release()
	_check(b.acquire(root_path) == OK, "released writer retry")
	b.release()
	var lock_root: String = ProjectSettings.globalize_path(root_path).path_join(".import-lock")
	DirAccess.make_dir_absolute(lock_root)
	var dead_record: FileAccess = FileAccess.open(owner_path, FileAccess.WRITE)
	dead_record.store_string(JSON.stringify({"pid": OS.get_process_id(), "birth": "0", "token": "old-pid-generation"}))
	dead_record.close()
	var takeover: String = ProjectSettings.globalize_path(root_path).path_join(".takeover-" + "old-pid-generation".sha256_text())
	DirAccess.make_dir_absolute(takeover)
	_check(a.acquire(root_path) == ERR_BUSY, "concurrent stale-generation takeover excluded")
	DirAccess.remove_absolute(takeover)
	_check(a.acquire(root_path) == OK, "reused pid does not preserve stale lock")
	a.release()
	var scoped: RefCounted = guard_script.new()
	_check(scoped.acquire(root_path) == OK, "scoped writer")
	scoped = null
	_check(b.acquire(root_path) == OK, "scope teardown releases writer")
	b.release()
	_check(guard_script.register_reader(root_path) == OK, "reader registration")
	_check(a.acquire(root_path) == OK, "same process may import before match")
	a.release()
	var marker: String = ProjectSettings.globalize_path(root_path)
	var outside: String = marker.path_join("War3.mpq")
	var file: FileAccess = FileAccess.open(outside, FileAccess.WRITE)
	file.store_string("original archive marker")
	file.close()
	_check(a.acquire(root_path) == ERR_INVALID_PARAMETER, "original installation refused")
	print("PASS: cache writer exclusion, release/retry, readers and source-directory protection" if _failures == 0 else "FAIL: guard")
	quit(0 if _failures == 0 else 1)

func _check(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
