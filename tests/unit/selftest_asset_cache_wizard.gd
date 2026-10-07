extends SceneTree

const Index: GDScript = preload("res://app/asset_import_index.gd")
var _ready_count: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame
	var cache: String = ProjectSettings.globalize_path("user://cache-wizard-%s" % Time.get_ticks_usec())
	assert(DirAccess.make_dir_recursive_absolute(cache) == OK)
	var data_path: String = cache.path_join("large.bin")
	var file: FileAccess = FileAccess.open(data_path, FileAccess.WRITE)
	var chunk: PackedByteArray = PackedByteArray()
	chunk.resize(4 * 1024 * 1024)
	chunk.fill(27)
	for index: int in range(16):
		file.store_buffer(chunk)
	file.close()
	var scene: String = cache.path_join("model.scn")
	file = FileAccess.open(scene, FileAccess.WRITE)
	file.store_string("Never mount this cancelled fixture")
	file.close()
	var content: Dictionary = {"root": cache, "files": [{"path": "large.bin", "sha256": FileAccess.get_sha256(data_path)}]}
	var results: Array[Dictionary] = [{"ok": true, "asset_id": "test/cancelled-model", "output_scene": scene, "output_sha256": FileAccess.get_sha256(scene)}]
	var request: String = "res://config/asset_import_samples.source"
	assert(Index.save(cache, results, "test-source", content, request) == OK)
	var original_path: String = ContentPaths.resolve("res://assets/asset-converted/test/cancelled-model.scn")

	print("CACHE_WIZARD: fixture ready")
	var wizard: Control = _create(cache, request)
	assert(wizard.cancel_button.text == "取消校验" and not wizard.cancel_button.disabled)
	await _wait_progress(wizard)
	assert(wizard.status.text.contains("MiB") and wizard.progress.max_value == 1)
	wizard.cancel_button.pressed.emit()
	await _wait_finished(wizard)
	assert(_ready_count == 0 and not wizard.start_button.disabled and wizard.play_button.disabled)
	assert(wizard.status.text.contains("已取消") and wizard.cancel_button.text == "取消导入")
	assert(ContentPaths.resolve("res://assets/asset-converted/test/cancelled-model.scn") == original_path)
	wizard.free()

	# Hold UI polling until the worker has finished, then cancel before installation.
	wizard = _create(cache, request)
	wizard.set_process(false)
	var deadline: int = Time.get_ticks_msec() + 10000
	while wizard._cache_thread.is_alive() and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(not wizard._cache_thread.is_alive())
	wizard.cancel_button.pressed.emit()
	wizard.set_process(true)
	await _wait_finished(wizard)
	assert(_ready_count == 0 and wizard.status.text.contains("已取消"))
	assert(ContentPaths.resolve("res://assets/asset-converted/test/cancelled-model.scn") == original_path)
	wizard.free()

	wizard = _create(cache, request)
	await _wait_progress(wizard)
	assert(wizard._cache_thread.is_alive())
	var closed_started: int = Time.get_ticks_usec()
	wizard.free()
	var closed_ms: float = (Time.get_ticks_usec() - closed_started) / 1000.0
	assert(closed_ms < 2000.0, "Closing must cancel chunk reads instead of hashing the whole cache")
	assert(_ready_count == 0)
	assert(DirAccess.remove_absolute(data_path) == OK)
	assert(DirAccess.remove_absolute(scene) == OK)
	print("PASS: cache progress, cancellation without mounting, late-cancel race and close join %.1f ms" % closed_ms)
	quit(0)

func _create(cache: String, request: String) -> Control:
	var scene: PackedScene = load("res://client/asset_import/asset_import_wizard.tscn") as PackedScene
	var wizard: Control = scene.instantiate() as Control
	wizard.cache_root = cache
	wizard.request_resource = request
	wizard.cache_validation_workers = 1
	wizard.ready_to_play.connect(func() -> void: _ready_count += 1)
	root.add_child(wizard)
	return wizard

func _wait_progress(wizard: Control) -> void:
	var deadline: int = Time.get_ticks_msec() + 10000
	# Inspect the running attempt before a slow unrelated startup frame can finish it.
	while int(wizard._cache_validation.snapshot().bytes) == 0 and wizard._cache_thread.is_alive() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
	wizard._show_cache_progress()
	assert(wizard.checking_cache and wizard._cache_thread.is_alive())

func _wait_finished(wizard: Control) -> void:
	var deadline: int = Time.get_ticks_msec() + 10000
	while wizard.checking_cache and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	assert(not wizard.checking_cache, "Cancelled validation must stop promptly")
