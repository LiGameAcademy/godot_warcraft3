import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { mergeDefinitionLayers, layerPolicy } from './definition-layers.js';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
assert.ok(process.env.GODOT, 'Set GODOT to the engine executable');
const scratch = path.join(repo, 'tools/asset-convert/tmp');
fs.mkdirSync(scratch, {recursive: true});
const out = fs.mkdtempSync(path.join(scratch, 'definition-layers-'));
const write = (name, data) => { const file = path.join(out, name); fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, data); };
const copy = name => write(name, fs.readFileSync(path.join(repo, name)));
write('project.godot', 'config_version=5\n[application]\nconfig/name="Definition policy regression"\n');
for (const name of ['definition_layer_merge.gd', 'definition_layers.gd']) copy(`packages/content/definitions/${name}`);
for (const name of ['command_button_catalog.gd', 'item_catalog.gd', 'worker_build_list_catalog.gd', 'unit_requires_catalog.gd']) copy(`packages/gameplay/catalog/${name}`);
for (const name of ['unit_abilities_def.gd', 'item_def.gd', 'ability_data_def.gd']) copy(`packages/content/definitions/units/${name}`);
for (const name of ['unit_ui_def.gd', 'unit_data_def.gd', 'unit_balance_def.gd', 'destructable_data_def.gd']) copy(`packages/content/definitions/units/${name}`);
copy('packages/content/definitions/doodads/doodad_data_def.gd');
copy('packages/map/infra/content_pack_rules.gd');
for (const name of ['wc3_id_catalog.gd', 'wc3_catalog_data.gd', 'wc3_catalog_models.gd', 'wc3_catalog_palette.gd']) copy(`packages/map/catalog/${name}`);
copy('tests/unit/selftest_catalog_layers.gd');
write('wc3_coords.gd', 'class_name Wc3Coords\nextends RefCounted\nconst PATHING_CELL: float = 32.0\n');
// Only filesystem access and unused presentation dependencies are isolated.
write('runtime_assets.gd', `class_name RuntimeAssets
extends RefCounted
static func read_json_dict(p: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(p)) as Dictionary
static func read_utf8_text(p: String) -> String:
	return FileAccess.get_file_as_string(p)
static func resolve(p: String) -> String:
	var file: String = "res://assets/slk-exported/" + p
	return file if FileAccess.file_exists(file) else ""
static func converted_path(p: String) -> String:
	return "res://assets/asset-converted/" + p
static func project_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)
static func load_converted_texture(_p: String) -> Texture2D:
	return null
static func file_exists(p: String) -> bool:
	return FileAccess.file_exists(p)
static func resolve_model_scene(_p: String) -> String:
	return ""
`);
write('tooltip.gd', 'class_name Wc3TooltipText\nextends RefCounted\nstatic func format(s: String, _level: int, _pick: bool) -> String:\n\treturn s\n');
write('ability_fx.gd', 'class_name AbilityFxCatalog\nextends RefCounted\nstatic func strip_autocast_art_suffix(s: String) -> String:\n\treturn s\n');
const layers = [
  {source: 'Units/HumanUnitFunc.txt', text: '[hpea]\nBuilds=htow,hbar\nRequires=halt\nArt="Base.blp"\nButtonpos=1,2\nTip="L1","L2"\n[Hpea]\nArt=Hero.blp'},
  {source: 'Custom_V1/Units/HumanUnitFunc.txt', text: '[hpea]\nbuilds=hfoo\nRequires=""\nArt=New.blp\nButtonpos=\n//Art=Ignored.blp'},
];
for (const layer of layers) write('assets/slk-exported/' + layer.source, layer.text);
write('assets/slk-exported/Units/ItemFunc.txt', '[phea]\nArt=BaseItem.blp');
write('assets/slk-exported/Custom_V1/Units/ItemFunc.txt', '[phea]\nArt=NewItem.blp');
write('assets/slk-exported/Units/HumanUnitStrings.txt', '[hpea]\nName=Base Peasant');
write('assets/slk-exported/Custom_V1/Units/HumanUnitStrings.txt', '[hpea]\nName=""');
write('assets/.gdignore', '');
for (const model of ['Units/Human/Peasant/Peasant.gltf', 'Units/Human/Peasant/Peasant_V1.gltf',
  'Units/Human/Peasant/Peasant_V1.glb', 'Units/Human/Peasant/Peasant_V1_Portrait.glb', 'Doodads/Fixture/Fixture2.glb']) {
  write('assets/asset-converted/' + model, 'path resolution fixture only');
}
write('fixture.json', JSON.stringify(layers));
write('run.gd', `extends SceneTree
const Merger: GDScript = preload("res://packages/content/definitions/definition_layer_merge.gd")
func _initialize() -> void:
	var layers: Array[Dictionary] = []
	for layer: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json")):
		layers.append(layer)
	var result: Dictionary = Merger.merge_layers(layers)
	var worker: WorkerBuildListCatalog = WorkerBuildListCatalog.new()
	var requires: UnitRequiresCatalog = UnitRequiresCatalog.new()
	var commands: CommandButtonCatalog = CommandButtonCatalog.new()
	ItemCatalog._merge_ini("res://assets/slk-exported/Units/ItemFunc.txt")
	result["integration"] = {"builds": worker.get_builds("hpea"), "commands": commands.get_builds("hpea"),
		"requires": requires.get_requires("hpea"), "item": ItemCatalog._ui["phea"]["art"]}
	var file: FileAccess = FileAccess.open("res://actual.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	quit()
`);
function run(args) {
  const result = spawnSync(process.env.GODOT, ['--headless', '--path', out, ...args], {encoding: 'utf8', timeout: 60000});
  assert.ok(!result.error, String(result.error) + '\n' + result.stdout + result.stderr);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.doesNotMatch(result.stdout + result.stderr, /SCRIPT ERROR|Parse Error|ERROR:/);
}
write('packages/content/definitions/layer_policy.json', JSON.stringify(layerPolicy));
run(['--editor', '--quit']);
for (const profile of ['base', 'custom_tft']) {
  write('packages/content/definitions/layer_policy.json', JSON.stringify({...layerPolicy, default_profile: profile}));
  run(['-s', 'res://run.gd']);
  const actual = JSON.parse(fs.readFileSync(path.join(out, 'actual.json')));
  const expected = mergeDefinitionLayers(layers);
  const integration = actual.integration;
  delete actual.integration;
  assert.deepEqual(actual, expected, 'Godot and JavaScript field merge must match');
  const base = profile === 'base';
  assert.deepEqual(integration, {builds: base ? ['htow', 'hbar'] : ['hfoo'], commands: base ? ['htow', 'hbar'] : ['hfoo'],
    requires: base ? ['halt'] : [], item: base ? 'BaseItem.blp' : 'NewItem.blp'});
  run(['-s', 'res://tests/unit/selftest_catalog_layers.gd']);
}
console.log(`Definition layer cross-language and five-catalog integration passed: ${out}`);
