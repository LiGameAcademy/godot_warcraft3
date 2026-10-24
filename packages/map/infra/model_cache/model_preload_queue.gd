extends RefCounted
## 管理待预载任务和字节缓存；轮询回调按调用传入，不持有宿主引用。


var _preload: Dictionary = {}
var _bytes_cache: Dictionary = {}


func request_preload(glb_path: String, already_cached: bool) -> void:
	var path: String = glb_path.strip_edges()
	if path.is_empty() or already_cached or _preload.has(path):
		return
	var scn_path: String = RuntimeAssets.resolve_model_scene(path)
	if not scn_path.is_empty():
		# Godot 4.6 的 Dummy Renderer 资源 RID 分配不是线程安全的。
		# https://github.com/godotengine/godot/issues/121949
		# 保留完整资源，在主线程按帧预算加载；有窗口渲染仍使用后台预载。
		if DisplayServer.get_name() == "headless":
			_preload[path] = {"kind": "scn_main", "scn_path": scn_path}
			return
		var err: Error = ResourceLoader.load_threaded_request(scn_path, "PackedScene", true)
		# OK / ERR_BUSY（已在加载）均可轮询
		if err == OK or err == ERR_BUSY:
			_preload[path] = {"kind": "scn", "scn_path": scn_path}
			return
	# JSON .gltf 必须主线程 append_from_file（外链贴图）；勿读字节走 GLB 校验
	if path.to_lower().ends_with(".gltf"):
		_preload[path] = {"kind": "gltf_pending"}
		return
	_start_bytes_preload(path)


func is_preload_pending(glb_path: String) -> bool:
	return not glb_path.is_empty() and _preload.has(glb_path)


func preload_pending_count() -> int:
	return _preload.size()


func cancel_preloads() -> void:
	_preload.clear()


## 主线程每帧调用：收割线程结果；gltf_budget 限制 GLB 解析与无窗口 .scn 加载总数。
## 返回本帧新写入缓存的路径数。
func poll_preloads(gltf_budget: int, has_cached: Callable, register_packed: Callable, finish_gltf: Callable) -> int:
	if _preload.is_empty():
		return 0
	var newly: int = 0
	var gltf_left: int = maxi(gltf_budget, 0)
	var paths: Array = _preload.keys()
	for path_v: Variant in paths:
		var path: String = str(path_v)
		if bool(has_cached.call(path)):
			_preload.erase(path)
			newly += 1
			continue
		var info: Dictionary = _preload[path]
		var kind: String = str(info.get("kind", ""))
		match kind:
			"scn_main":
				if gltf_left <= 0:
					continue
				gltf_left -= 1
				var packed: PackedScene = ResourceLoader.load(str(info.scn_path), "PackedScene") as PackedScene
				if packed != null:
					register_packed.call(path, packed)
					newly += 1
				else:
					_preload.erase(path)
					_start_bytes_preload(path)
			"scn":
				newly += _poll_scn_preload(path, info, register_packed)
			"bytes":
				_poll_bytes_preload(path, info)
			"gltf_pending":
				if gltf_left <= 0:
					continue
				if bool(finish_gltf.call(path)):
					gltf_left -= 1
					newly += 1
			_:
				_preload.erase(path)
	return newly


func _start_bytes_preload(path: String) -> void:
	var disk_path: String = RuntimeAssets.project_abs(path)
	var holder: Dictionary = {"bytes": PackedByteArray(), "done": false, "ok": false}
	WorkerThreadPool.add_task(
		func() -> void:
			if FileAccess.file_exists(disk_path):
				var b: PackedByteArray = FileAccess.get_file_as_bytes(disk_path)
				holder["bytes"] = b
				holder["ok"] = not b.is_empty()
			holder["done"] = true
	)
	_preload[path] = {"kind": "bytes", "holder": holder}


func _poll_scn_preload(path: String, info: Dictionary, register_packed: Callable) -> int:
	var scn_path: String = str(info.get("scn_path", ""))
	if scn_path.is_empty():
		_preload.erase(path)
		_start_bytes_preload(path)
		return 0
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(scn_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return 0
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var res: Resource = ResourceLoader.load_threaded_get(scn_path)
		if res is PackedScene:
			register_packed.call(path, res as PackedScene)
			return 1
		_preload.erase(path)
		_start_bytes_preload(path)
		return 0
	# FAILED / INVALID → 回退读 GLB
	_preload.erase(path)
	_start_bytes_preload(path)
	return 0


func _poll_bytes_preload(path: String, info: Dictionary) -> void:
	var holder: Variant = info.get("holder", null)
	if typeof(holder) != TYPE_DICTIONARY:
		_preload.erase(path)
		return
	var h: Dictionary = holder
	if not bool(h.get("done", false)):
		return
	if bool(h.get("ok", false)):
		store_bytes(path, h.get("bytes", PackedByteArray()) as PackedByteArray)
		info["kind"] = "gltf_pending"
		_preload[path] = info
	else:
		_preload.erase(path)


func has_bytes_cached(path: String) -> bool:
	return not path.is_empty() and _bytes_cache.has(path)


func store_bytes(path: String, bytes: PackedByteArray) -> void:
	if path.is_empty() or bytes.is_empty():
		return
	_bytes_cache[path] = bytes


func take_cached_bytes(path: String) -> PackedByteArray:
	if path.is_empty() or not _bytes_cache.has(path):
		return PackedByteArray()
	return _bytes_cache[path] as PackedByteArray


func complete(path: String) -> void:
	_preload.erase(path)


func evict_bytes(path: String) -> void:
	_bytes_cache.erase(path)
