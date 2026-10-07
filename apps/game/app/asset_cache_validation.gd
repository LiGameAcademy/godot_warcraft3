extends RefCounted

## One validation attempt. Workers only read files; UI consumes locked snapshots.
## Independent 1 MiB streams bound memory and check cancellation inside large SCNs.
const CHUNK_BYTES: int = 1024 * 1024
var _mutex: Mutex = Mutex.new()
var _workers: int
var _paths: PackedStringArray = PackedStringArray()
var _hashes: PackedStringArray = PackedStringArray()
var _stage: String = "preparing"
var _completed: int = 0
var _total: int = 0
var _bytes: int = 0
var _cancelled: bool = false
var _failed: bool = false
var _error_path: String = ""
var _started_usec: int

func _init(workers: int = 2) -> void:
	_workers = clampi(workers, 1, 4)
	_started_usec = Time.get_ticks_usec()

func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()

func snapshot() -> Dictionary:
	_mutex.lock()
	var result: Dictionary = {
		"stage": _stage, "completed": _completed, "total": _total,
		"bytes": _bytes, "worker_count": _workers, "cancelled": _cancelled,
		"failed": _failed, "error_path": _error_path,
		"milliseconds": (Time.get_ticks_usec() - _started_usec) / 1000.0,
	}
	_mutex.unlock()
	return result

func validate_content(content: Dictionary) -> bool:
	if _should_stop():
		return false
	if content.is_empty():
		return true
	if not content.get("root") is String or not content.get("files") is Array or content.files.is_empty():
		return _fail("content")
	var root: String = str(content.root).replace("\\", "/").simplify_path()
	if not root.is_absolute_path() or not DirAccess.dir_exists_absolute(root):
		return _fail(root)
	var paths: PackedStringArray = PackedStringArray()
	var hashes: PackedStringArray = PackedStringArray()
	var seen: Dictionary[String, bool] = {}
	for entry: Variant in content.files:
		if _should_stop():
			return false
		if not entry is Dictionary or not entry.get("path") is String or not entry.get("sha256") is String:
			return _fail("content")
		var relative: String = str(entry.path).replace("\\", "/")
		if relative.is_empty() or relative.is_absolute_path() or relative.split("/").has(".."):
			return _fail(relative)
		relative = relative.simplify_path()
		if seen.has(relative.to_lower()) or str(entry.sha256).length() != 64:
			return _fail(relative)
		seen[relative.to_lower()] = true
		paths.append(root.path_join(relative))
		hashes.append(str(entry.sha256))
	return _run_hashes(paths, hashes, "content")

func validate_scenes(results: Array) -> bool:
	var paths: PackedStringArray = PackedStringArray()
	var hashes: PackedStringArray = PackedStringArray()
	for entry: Variant in results:
		if _should_stop():
			return false
		if not entry is Dictionary or not entry.get("output_scene") is String or not entry.get("output_sha256") is String:
			return _fail("scenes")
		var path: String = str(entry.output_scene)
		if path.is_empty() or str(entry.output_sha256).length() != 64:
			return _fail(path)
		paths.append(path)
		hashes.append(str(entry.output_sha256))
	return _run_hashes(paths, hashes, "scenes")

func _run_hashes(paths: PackedStringArray, hashes: PackedStringArray, stage: String) -> bool:
	_paths = paths
	_hashes = hashes
	_mutex.lock()
	_stage = stage
	_completed = 0
	_total = paths.size()
	_bytes = 0
	_mutex.unlock()
	if _should_stop():
		return false
	if _workers == 1 or paths.size() <= 1:
		for index: int in range(paths.size()):
			_hash_file(index)
	else:
		var group: int = WorkerThreadPool.add_group_task(_hash_file, paths.size(), mini(_workers, paths.size()), false, "Asset cache hashes")
		WorkerThreadPool.wait_for_group_task_completion(group)
	return not _should_stop()

func _hash_file(index: int) -> void:
	if _should_stop():
		return
	var path: String = _paths[index]
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail(path)
		return
	var size: int = file.get_length()
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		_fail(path)
		return
	while file.get_position() < size:
		if _should_stop():
			file.close()
			return
		var wanted: int = mini(CHUNK_BYTES, size - file.get_position())
		var chunk: PackedByteArray = file.get_buffer(wanted)
		if chunk.size() != wanted or context.update(chunk) != OK:
			file.close()
			_fail(path)
			return
		_mutex.lock()
		_bytes += chunk.size()
		_mutex.unlock()
	var same_size: bool = file.get_length() == size
	file.close()
	var actual: String = context.finish().hex_encode()
	_mutex.lock()
	_completed += 1
	_mutex.unlock()
	if not same_size or actual != _hashes[index]:
		_fail(path)

func _should_stop() -> bool:
	_mutex.lock()
	var stopped: bool = _cancelled or _failed
	_mutex.unlock()
	return stopped

func _fail(path: String) -> bool:
	_mutex.lock()
	if not _failed:
		_failed = true
		_error_path = path
	_mutex.unlock()
	return false
