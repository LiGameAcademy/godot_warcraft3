extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var importer_script: GDScript = load("res://app/game_asset_import.gd")
	var index_script: GDScript = load("res://app/asset_import_index.gd")
	var cache: String = ProjectSettings.globalize_path("user://snapshot-test-%s" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(cache)
	var node: Node3D = Node3D.new()
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(node) == OK)
	var scene: String = cache.path_join("model.scn")
	assert(ResourceSaver.save(packed, scene) == OK)
	node.free()
	var file: FileAccess = FileAccess.open(cache.path_join("data.txt"), FileAccess.WRITE)
	file.store_string("complete")
	file.close()
	var content: Dictionary = {"root": cache, "files": [{"path": "data.txt", "sha256": FileAccess.get_sha256(cache.path_join("data.txt"))}]}
	var results: Array[Dictionary] = [{"ok": true, "asset_id": "test/model", "output_scene": scene, "output_sha256": FileAccess.get_sha256(scene)}]
	var request: String = "res://config/asset_import_samples.source"
	assert(index_script.save(cache, results, "test-source", content, request) == OK)
	var importer: RefCounted = importer_script.new()
	var altered: Array[Dictionary] = [results[0].duplicate(true)]
	altered[0]["output_sha256"] = "not-the-published-scene"
	assert(importer.install_results(altered, content).diagnostics[0].code == "cache_scene_hash_failed")
	assert(ContentPaths.resolve("res://assets/asset-converted/test/model.scn") != scene)
	assert(not importer.restore_validated_cache().ok)
	file = FileAccess.open(cache.path_join("data.txt"), FileAccess.WRITE)
	file.store_string("corrupt!")
	file.close()
	assert(not importer.validate_cache(cache, request))
	assert(not importer.restore_validated_cache().ok)
	file = FileAccess.open(cache.path_join("data.txt"), FileAccess.WRITE)
	file.store_string("complete")
	file.close()
	var worker: Thread = Thread.new()
	assert(worker.start(importer.validate_cache.bind(cache, request)) == OK)
	while worker.is_alive():
		await process_frame
	assert(worker.wait_to_finish() == true)
	var restored: Dictionary = importer.restore_validated_cache()
	assert(restored.ok)
	assert(restored.paths["test/model.scn"] == scene)
	assert(not importer.restore_validated_cache().ok)
	print("PASS: unvalidated/corrupt cache and changed scene rejected, background validation, one-use restore and atomic paths")
	quit(0)
