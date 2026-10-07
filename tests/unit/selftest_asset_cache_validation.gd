extends SceneTree

const Validation: GDScript = preload("res://app/asset_cache_validation.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var root: String = ProjectSettings.globalize_path("user://hash-test-%s" % Time.get_ticks_usec())
	assert(DirAccess.make_dir_recursive_absolute(root) == OK)
	var files: Array[Dictionary] = []
	var block: PackedByteArray = PackedByteArray()
	block.resize(1024 * 1024 + 17)
	for index: int in range(8):
		block.fill(index + 1)
		var path: String = root.path_join("%s.bin" % index)
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(block)
		file.close()
		files.append({"path": path.get_file(), "sha256": FileAccess.get_sha256(path)})
	var content: Dictionary = {"root": root, "files": files}
	for workers: int in [1, 2, 4]:
		var validation: RefCounted = Validation.new(workers)
		assert(validation.validate_content(content))
		var progress: Dictionary = validation.snapshot()
		assert(progress.completed == 8 and progress.total == 8)
		assert(progress.bytes == block.size() * 8 and progress.worker_count == workers)
		var scenes: Array[Dictionary] = [{"output_scene": root.path_join("0.bin"), "output_sha256": files[0].sha256}]
		assert(validation.validate_scenes(scenes))
		assert(validation.snapshot().stage == "scenes")
		assert(validation.snapshot().completed == 1)
	var changed: Dictionary = content.duplicate(true)
	changed.files[0].sha256 = "0".repeat(64)
	assert(not Validation.new(2).validate_content(changed))
	assert(not Validation.new(2).validate_content({"root": root, "files": [files[0], files[0]]}))
	assert(not Validation.new(2).validate_content({"root": root, "files": [{"path": "../escape", "sha256": files[0].sha256}]}))
	assert(not Validation.new(2).validate_content({"root": root, "files": [{"path": "missing", "sha256": files[0].sha256}]}))
	assert(not Validation.new(2).validate_scenes([{"output_scene": root.path_join("0.bin"), "output_sha256": ""}]))
	assert(Validation.new(2).validate_content({}))
	var stopped: RefCounted = Validation.new(2)
	stopped.cancel()
	assert(not stopped.validate_content(content))
	assert(stopped.snapshot().cancelled and stopped.snapshot().completed == 0)
	var large_path: String = root.path_join("large.bin")
	var large: FileAccess = FileAccess.open(large_path, FileAccess.WRITE)
	for index: int in range(64):
		large.store_buffer(block)
	large.close()
	var large_content: Dictionary = {"root": root, "files": [{"path": "large.bin", "sha256": FileAccess.get_sha256(large_path)}]}
	var active: RefCounted = Validation.new(2)
	var worker: Thread = Thread.new()
	assert(worker.start(active.validate_content.bind(large_content)) == OK)
	while worker.is_alive() and int(active.snapshot().bytes) == 0:
		await process_frame
	active.cancel()
	assert(worker.wait_to_finish() == false)
	assert(active.snapshot().cancelled and int(active.snapshot().bytes) < block.size() * 64)
	# Successful and failed jobs never alter the files they inspect.
	assert(FileAccess.get_sha256(root.path_join("0.bin")) == files[0].sha256)
	assert(DirAccess.remove_absolute(large_path) == OK)
	for entry: Dictionary in files:
		assert(DirAccess.remove_absolute(root.path_join(str(entry.path))) == OK)
	print("PASS: 1/2/4 hash workers, full bytes, scene phase, corrupt/missing/duplicate/traversal rejection and chunk cancellation")
	quit(0)
