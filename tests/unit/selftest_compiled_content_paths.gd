extends SceneTree

const AssetImport: GDScript = preload("res://app/game_asset_import.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var importer: RefCounted = AssetImport.new()
	assert(importer.run_manifest("user://missing-manifest.json", true).diagnostics[0].code == "content_in_use")
	var manifest: String = "user://content-paths-test.manifest.json"
	var file: FileAccess = FileAccess.open(manifest, FileAccess.WRITE)
	file.store_string('{"manifest_version":1,"tasks":[]}')
	file.close()
	assert(importer.run_manifest(manifest, false).diagnostics[0].code == "manifest_invalid")
	var invalid: Dictionary[String, String] = {"unit.scn": "user://missing-content-paths.scn"}
	assert(ContentPaths.install_compiled_scenes(invalid) == ERR_INVALID_DATA)
	var root_node: Node3D = Node3D.new()
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(root_node) == OK)
	root_node.free()
	var scene: String = "user://content-paths-test.scn"
	assert(ResourceSaver.save(packed, scene) == OK)
	var actual: String = ProjectSettings.globalize_path(scene)
	var paths: Dictionary[String, String] = {"units/test/unit.scn": actual}
	assert(ContentPaths.install_compiled_scenes(paths) == OK)
	paths["units/test/unit.scn"] = "changed-after-install.scn"
	assert(ContentPaths.resolve("res://assets/asset-converted/Units/Test/Unit.scn") == actual)
	assert(ContentPaths.install_compiled_scenes({}) == ERR_BUSY)
	assert(ContentPaths.resolve("res://assets/asset-converted/Units/Test/Unit.scn") == actual)
	assert(not ContentPaths.resolve("res://assets/unrelated.png").ends_with("content-paths-test.scn"))
	DirAccess.remove_absolute(actual)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest))
	print("PASS: invalid manifest, live-match rejection, atomic/read-only cache map, caller isolation")
	quit(0)
