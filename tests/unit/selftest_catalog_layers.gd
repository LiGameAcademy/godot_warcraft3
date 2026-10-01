extends SceneTree
## Executed by definition-layers-integration.test.mjs in its isolated project.
var failures: Array[String] = []

class FixtureStore extends Node:
	var tables: Dictionary = {}
	func ensure_table(_table: String) -> void:
		pass
	func get_ids(table: String) -> Array:
		return (tables.get(table, {}) as Dictionary).keys()
	func get_row(table: String, id: String) -> Resource:
		return (tables.get(table, {}) as Dictionary).get(id) as Resource

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var store: FixtureStore = FixtureStore.new()
	store.name = "Wc3DefStore"
	root.add_child(store)
	var unit: UnitUiDef = UnitUiDef.new()
	unit.unit_uiid = "hpea"
	unit.name_key = "Original name"
	unit.file = "Units/Human/Peasant/Peasant.mdx"
	unit.file_ver_flags = 2
	unit.in_editor = true
	unit.unit_class = "HUnit01"
	var data: UnitDataDef = UnitDataDef.new()
	data.race = "human"
	data.path_tex = "PathTextures/4x4Simple.tga"
	var balance: UnitBalanceDef = UnitBalanceDef.new()
	balance.collision = 16.0
	var doodad: DoodadDataDef = DoodadDataDef.new()
	doodad.dood_id = "Dfoo"
	doodad.name_key = "Doodad"
	doodad.tilesets = "L"
	doodad.category = "O"
	doodad.file = "Doodads/Fixture/Fixture"
	doodad.num_var = 3
	var tree: DestructableDataDef = DestructableDataDef.new()
	tree.destructable_id = "Tfoo"
	tree.name_key = "Tree"
	tree.tilesets = "*"
	tree.category = "D"
	store.tables = {UnitUiDef.TABLE_NAME: {"hpea": unit}, UnitDataDef.TABLE_NAME: {"hpea": data},
		UnitBalanceDef.TABLE_NAME: {"hpea": balance}, DoodadDataDef.TABLE_NAME: {"Dfoo": doodad},
		DestructableDataDef.TABLE_NAME: {"Tfoo": tree}}
	var catalog: Wc3IdCatalog = Wc3IdCatalog.new()
	catalog.load_default()
	var policy: Dictionary = RuntimeAssets.read_json_dict("res://packages/content/definitions/layer_policy.json")
	var base: bool = str(policy["default_profile"]) == "base"
	var row: Dictionary = catalog.lookup("hpea")
	var commands: CommandButtonCatalog = CommandButtonCatalog.new()
	_check(row["name"] == ("Base Peasant" if base else ""), "name inheritance / explicit empty clear")
	_check(row["art"] == commands.get_unit_ui("hpea")["art"], "map icon matches command catalog")
	_check(row["button_pos"] == (Vector2i(1, 2) if base else Vector2i.ZERO), "button position profile")
	_check(row["race"] == "human" and row["collision"] == 16.0, "SLK data and balance merge")
	_check(catalog.unit_count() == 3 and catalog.doodad_count() == 1 and catalog.destructable_count() == 1, "tables and injected markers")
	_check(catalog.lookup("unknown")["kind"] == "unknown", "unknown ID fallback")
	_check(catalog.model_base_path("hpea") == "Units/Human/Peasant/Peasant", "model extension normalization")
	_check(catalog.resolve_model_stem("hpea").ends_with("Peasant_V1"), "TFT model edition independent of definition profile")
	_check(catalog.converted_glb_path("hpea").ends_with("Peasant_V1.gltf"), "gltf before glb")
	_check(catalog.portrait_glb_path("hpea").ends_with("Peasant_V1_Portrait.glb"), "portrait variant")
	_check(catalog.converted_glb_path("Dfoo", 2).ends_with("Fixture2.glb"), "doodad numeric variation")
	ProjectSettings.set_setting("warcraft3/content/active_edition", "roc")
	_check(catalog.resolve_model_stem("hpea").ends_with("/Peasant"), "RoC base model")
	_check(catalog.portrait_glb_path("hpea").is_empty(), "base never takes TFT portrait")
	_check(catalog.list_placeables_filtered("L", "O").size() == 1, "doodad category and tileset")
	_check(catalog.list_placeables_filtered("A", "O").is_empty(), "unmatched tileset")
	_check(catalog.list_placeables(false, true).size() == 1, "destructable inclusion")
	_check(catalog.list_units_filtered("human").size() == 1, "unit race filtering")
	var sections: Dictionary = catalog.list_units_palette_sections("human")
	_check(sections["units"].size() == 1 and sections["buildings"][0]["id"] == "sloc", "start location remains first")
	_check(catalog.list_unit_races() == PackedStringArray(["human", "neutral"]), "race buckets")
	_check(catalog.list_units_palette_sections("neutral", "melee", "L", 2)["units"].is_empty(), "neutral level filter")
	_check(Wc3IdCatalog.parse_path_tex_cells("PathTextures/4x4Simple.tga") == Vector2i(4, 4), "pathing footprint")
	_check(Wc3IdCatalog.selection_diameter_wc3(row) == 128.0, "selection footprint precedence")
	_check(Wc3IdCatalog.default_facing_deg({"fixed_rot": -1}) == 270.0, "default facing")
	_check(Wc3IdCatalog.preview_distance_wc3({"vis_radius": 100}) == 800.0, "preview distance")
	var other: Wc3IdCatalog = Wc3IdCatalog.new()
	other.load_default()
	row["name"] = "Changed instance"
	_check(other.lookup("hpea")["name"] != row["name"] and unit.name_key == "Original name", "catalog instances do not mutate template resources")
	for failure: String in failures:
		printerr(failure)
	print("Catalog migration checks: ", "PASS" if failures.is_empty() else "FAIL")
	store.free()
	quit(0 if failures.is_empty() else 1)
