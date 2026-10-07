extends SceneTree

const Content: GDScript = preload("res://app/asset_import_content.gd")
const ASSET_IMPORT_PATH: String = "res://app/game_asset_import.gd"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var importer: RefCounted = load(ASSET_IMPORT_PATH).new()
	assert(importer.run_manifest("user://missing-manifest.json", true).diagnostics[0].code == "content_in_use")
	var manifest: String = "user://content-paths-test.manifest.json"
	var file: FileAccess = FileAccess.open(manifest, FileAccess.WRITE)
	file.store_string('{"manifest_version":1,"tasks":[]}')
	file.close()
	assert(importer.run_manifest(manifest, false).diagnostics[0].code == "manifest_invalid")
	var invalid: Dictionary[String, String] = {"unit.scn": "user://missing-content-paths.scn"}
	assert(ContentPaths.install_compiled_scenes(invalid) == ERR_INVALID_DATA)
	var loose_root: String = ProjectSettings.globalize_path("user://content-paths-loose")
	assert(DirAccess.make_dir_recursive_absolute(loose_root) == OK)
	var loose_file: String = loose_root.path_join("terrain.json")
	file = FileAccess.open(loose_file, FileAccess.WRITE)
	file.store_string("valid terrain")
	file.close()
	var content: Dictionary = {"root": loose_root, "files": [{"path": "terrain.json", "sha256": FileAccess.get_sha256(loose_file)}]}
	assert(Content.validate(content))
	var corrupt: Dictionary = content.duplicate(true)
	corrupt.files[0].sha256 = "corrupt"
	assert(not Content.validate(corrupt))
	var invalid_results: Array[Dictionary] = [{"ok": true, "asset_id": "unit", "output_scene": "missing"}]
	assert(importer.install_results(invalid_results, corrupt).diagnostics[0].code == "content_generation_invalid")
	corrupt.files[0].path = "../outside.json"
	assert(not Content.validate(corrupt))
	assert(not Content.validate({"root": loose_root, "files": [content.files[0], content.files[0]]}))
	var root_node: Node3D = Node3D.new()
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(root_node) == OK)
	root_node.free()
	var scene: String = "user://content-paths-test.scn"
	assert(ResourceSaver.save(packed, scene) == OK)
	var actual: String = ProjectSettings.globalize_path(scene)
	var paths: Dictionary[String, String] = {"units/test/unit.scn": actual}
	assert(ContentPaths.install_compiled_scenes(paths, loose_root) == OK)
	paths["units/test/unit.scn"] = "changed-after-install.scn"
	assert(ContentPaths.resolve("res://assets/asset-converted/Units/Test/Unit.scn") == actual)
	assert(ContentPaths.resolve("res://assets/terrain.json") == loose_file)
	assert(ContentPaths.install_compiled_scenes({}) == ERR_BUSY)
	assert(ContentPaths.resolve("res://assets/asset-converted/Units/Test/Unit.scn") == actual)
	assert(not ContentPaths.resolve("res://assets/unrelated.png").ends_with("content-paths-test.scn"))
	DirAccess.remove_absolute(loose_file)
	DirAccess.remove_absolute(loose_root)
	DirAccess.remove_absolute(actual)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest))
	print("PASS: invalid manifest, live-match rejection, atomic/read-only cache map, caller isolation")
	quit(0)
