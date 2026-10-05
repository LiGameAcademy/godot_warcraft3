extends RefCounted

var _root: String = ""
var _token: String = ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not _token.is_empty():
		# The instance can no longer dispatch methods during RefCounted teardown.
		var directory: String = _root.path_join(".import-lock")
		var filename: String = directory.path_join("owner.json")
		if FileAccess.file_exists(filename):
			var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(filename))
			if value is Dictionary and value.get("token") == _token:
				DirAccess.remove_absolute(filename)
				DirAccess.remove_absolute(directory)

func acquire(cache_root: String, check_readers: bool = true) -> Error:
	_root = ProjectSettings.globalize_path(cache_root).simplify_path()
	if FileAccess.file_exists(_root.path_join("War3.mpq")):
		return ERR_INVALID_PARAMETER
	var error: Error = DirAccess.make_dir_recursive_absolute(_root)
	if error != OK:
		return error
	var directory: String = _root.path_join(".import-lock")
	error = DirAccess.make_dir_absolute(directory)
	if error != OK:
		var owner: Dictionary = _read(directory.path_join("owner.json"))
		var pid: int = int(owner.get("pid", 0))
		var children_alive: bool = false
		for child: Variant in owner.get("children", []):
			if child is Dictionary:
				children_alive = children_alive or _is_running(int(child.get("pid", 0)), str(child.get("birth", "")))
			else:
				children_alive = children_alive or _is_running(int(child))
		if pid <= 0 or _is_running(pid, str(owner.get("birth", ""))) or children_alive:
			return ERR_BUSY
		# Serialize takeover of this exact dead generation. A stale observer must
		# not rename a newer writer's directory after the first recovery finishes.
		var previous_token: String = str(owner.get("token", ""))
		if previous_token.is_empty():
			return ERR_BUSY
		var takeover: String = _root.path_join(".takeover-" + previous_token.sha256_text())
		if DirAccess.make_dir_absolute(takeover) != OK:
			return ERR_BUSY
		var stale: String = _root.path_join(".stale-lock-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()])
		var recovered: Error = ERR_BUSY
		if _read(directory.path_join("owner.json")).get("token") == previous_token:
			recovered = DirAccess.rename_absolute(directory, stale)
			if recovered == OK:
				recovered = DirAccess.make_dir_absolute(directory)
		DirAccess.remove_absolute(takeover)
		if recovered != OK:
			return ERR_BUSY
	_token = "%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _write(directory.path_join("owner.json"), {"pid": OS.get_process_id(), "birth": _birth(OS.get_process_id()), "token": _token}):
		DirAccess.remove_absolute(directory.path_join("owner.json"))
		DirAccess.remove_absolute(directory)
		_token = ""
		return ERR_CANT_CREATE
	if not _write(_root.path_join(".asset-cache-v1"), {"version": 1, "kind": "warcraft-derived-content"}):
		release()
		return ERR_CANT_CREATE
	if check_readers and DirAccess.dir_exists_absolute(_root.path_join(".readers")):
		for filename: String in DirAccess.get_files_at(_root.path_join(".readers")):
			var reader: Dictionary = _read(_root.path_join(".readers").path_join(filename))
			var pid: int = int(reader.get("pid", 0))
			if pid != OS.get_process_id() and (pid <= 0 or _is_running(pid, str(reader.get("birth", "")))):
				release()
				return ERR_BUSY
	return OK

func track_child(pid: int) -> void:
	if _token.is_empty():
		return
	var filename: String = _root.path_join(".import-lock/owner.json")
	var owner: Dictionary = _read(filename)
	if owner.get("token") != _token:
		return
	var birth: String = _birth(pid) if pid > 0 else ""
	owner["children"] = [{"pid": pid, "birth": birth}] if not birth.is_empty() else []
	if not _write(filename, owner):
		push_error("Cannot persist cache child-process ownership: " + filename)

func release() -> void:
	if _token.is_empty():
		return
	var directory: String = _root.path_join(".import-lock")
	if _read(directory.path_join("owner.json")).get("token") == _token:
		DirAccess.remove_absolute(directory.path_join("owner.json"))
		DirAccess.remove_absolute(directory)
	_token = ""

static func register_reader(cache_root: String) -> Error:
	var guard: RefCounted = load("res://app/asset_import_guard.gd").new()
	var error: Error = guard.acquire(cache_root, false)
	if error != OK:
		return error
	error = guard.retain_reader()
	guard.release()
	return error

## Publish the reader while still holding the writer lock: no cleanup race.
func retain_reader() -> Error:
	if _token.is_empty():
		return ERR_UNAUTHORIZED
	var directory: String = _root.path_join(".readers")
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error == OK and not _write(directory.path_join("%s.json" % OS.get_process_id()), {"pid": OS.get_process_id(), "birth": _birth(OS.get_process_id())}):
		return ERR_CANT_CREATE
	return error

static func _birth(pid: int) -> String:
	var probe: RefCounted = load("res://adapters/godot/AssetProcessProbe.cs").new()
	return str(probe.Identity(pid))

static func _is_running(pid: int, birth: String = "") -> bool:
	var probe: RefCounted = load("res://adapters/godot/AssetProcessProbe.cs").new()
	return bool(probe.IsRunning(pid, birth))

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {}
	return parser.data

static func _write(path: String, value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK
