import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {packageRuntime} from '../scripts/package-runtime.mjs';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const base = path.join(repo, 'tools/asset-convert/tmp');
fs.mkdirSync(base, {recursive: true});
const reuse = process.env.ASSET_TEST_REUSE || '';
const retry = process.env.ASSET_TEST_RETRY || '';
const recover = process.env.ASSET_TEST_RECOVER || '';
assert.ok([reuse, retry, recover].filter(Boolean).length <= 1, 'Choose one acceptance recovery mode');
const output = reuse || retry || recover ? path.resolve(reuse || retry || recover) : fs.mkdtempSync(path.join(base, 'development-'));
const release = path.join(output, 'release');
fs.mkdirSync(release, {recursive: true});
const binary = path.join(release, 'game.exe');
const gameDir = process.env.WC3_PATH || JSON.parse(fs.readFileSync(path.join(repo, 'tools/bootstrap.config.json'))).wc3.path;
const cache = path.join(output, 'cache');
let sequence = 0;
function launch(executable, args, player = false) {
  const started = Date.now();
  const child = spawnSync(executable.replace(/_console\.exe$/i, '.exe'), args, {
    cwd: repo, encoding: 'utf8', timeout: 3660000,
    env: player ? {...process.env, PATH: '', GODOT: '', ASSET_SOURCE: '', STORMLIB_DLL: '', NODE_PATH: '', NODE_OPTIONS: ''} : process.env,
  });
  const log = (child.stdout || '') + (child.stderr || '');
  fs.writeFileSync(path.join(output, `run-${sequence++}.log`), log);
  assert.ifError(child.error);
  assert.equal(child.status, 0, log);
  assert.doesNotMatch(log, /SCRIPT ERROR|Parse Error|Compile Error|Export .NET Project:/);
  console.log(`PASS: process ${sequence}, ${((Date.now() - started) / 1000).toFixed(1)}s`);
  return log;
}
launch(process.env.PYTHON || 'python', [path.join(repo, 'tools/workspace/sync_packages.py'), '--app', 'game']);
const tmp = path.join(repo, 'apps/game/tmp');
fs.mkdirSync(tmp, {recursive: true});
for (const ext of ['gd', 'tscn']) fs.copyFileSync(path.join(repo, `tests/integration/selftest_asset_import_wizard.${ext}`), path.join(tmp, `selftest_asset_import_wizard.${ext}`));
fs.writeFileSync(path.join(tmp, 'development_probe.gd'), `extends "res://boot.gd"
const Capture: GDScript = preload("res://tmp/development_capture.gd")
func _start() -> void:
	if "--mode" in OS.get_cmdline_user_args():
		var probe: Node = (load("res://tmp/selftest_asset_import_wizard.tscn") as PackedScene).instantiate()
		get_tree().root.add_child(probe)
	else:
		if "--capture-game" in OS.get_cmdline_user_args():
			get_tree().root.add_child(Capture.new())
		super._start()
`);
fs.writeFileSync(path.join(tmp, 'development_probe.tscn'), `[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tmp/development_probe.gd" id="1"]
[node name="Boot" type="Node"]
script = ExtResource("1")
`);
fs.copyFileSync(path.join(repo, 'tests/integration/development_capture.gd'), path.join(tmp, 'development_capture.gd'));
const project = path.join(repo, 'apps/game/project.godot');
const preset = path.join(repo, 'apps/game/export_presets.cfg');
const originalProject = fs.readFileSync(project);
const originalPreset = fs.readFileSync(preset);
try {
  fs.writeFileSync(project, originalProject.toString().replace('res://boot.tscn', 'res://tmp/development_probe.tscn'));
  fs.writeFileSync(preset, originalPreset.toString().replace('tests/*,tmp/*,', 'tests/*,'));
  launch(process.env.GODOT, ['--headless', '--path', path.join(repo, 'apps/game'), '--editor', '--import']);
  launch(process.env.GODOT, ['--headless', '--path', path.join(repo, 'apps/game'), '--export-release', 'Windows Desktop', binary]);
} finally {
  fs.writeFileSync(project, originalProject);
  fs.writeFileSync(preset, originalPreset);
}
const bundle = path.join(release, 'asset-import-runtime');
if (!reuse && !retry && !recover) await packageRuntime(bundle);
else if (fs.existsSync(path.join(bundle, 'node.disabled'))) fs.renameSync(path.join(bundle, 'node.disabled'), path.join(bundle, 'node.exe'));
const coldReport = path.join(output, 'cold.json');
if (!reuse && !recover) launch(binary, ['--headless', '--', '--mode', 'cold', '--development', '--cache', cache, '--source', gameDir, '--report', coldReport], true);
let cold;
let recoveredIndex = '';
if (recover) {
  launch(binary, ['--headless', '--', '--mode', 'warm', '--development', '--cache', cache,
    '--source', gameDir, '--report', path.join(output, 'recovered-index.json')], true);
  const indexes = fs.readdirSync(path.join(cache, 'indexes')).filter(name => name.endsWith('.json')).sort();
  assert.ok(indexes.length);
  recoveredIndex = path.join(cache, 'indexes', indexes.at(-1));
  const record = JSON.parse(fs.readFileSync(recoveredIndex));
  // The warm fixture has already hashed this publication and installed it.
  // Do not replace cold.json or manufacture cold UI/progress evidence.
  cold = {result: {ok: true, results: record.results, content: record.content}};
} else cold = JSON.parse(fs.readFileSync(coldReport));
assert.equal(cold.result.ok, true);
assert.equal(cold.result.content.coverage.complete, true);
assert.equal(cold.result.content.coverage.unresolved_references.length, 0);
assert.ok(cold.result.results.length >= 300);
assert.ok(cold.result.results.every(entry => !entry.diagnostics.some(row => row.code === "texture_placeholder")));
assert.ok(cold.result.content.files.length > 5000);
if (!recover) assert.ok(cold.frames > 10);
if (!recover) assert.ok(cold.events.filter(event => event.stage === '编译场景缓存').length > 10);
const before = fs.readdirSync(path.join(cache, 'indexes'));
let timings, capture, reviewCapture;
try {
  // Cache replay must not parse MPQs, regenerate IR or launch the source runtime.
  fs.renameSync(path.join(bundle, 'node.exe'), path.join(bundle, 'node.disabled'));
  if (fs.existsSync(path.join(cache, 'inputs'))) fs.renameSync(path.join(cache, 'inputs'), path.join(cache, 'inputs-disabled'));
  const replay = launch(binary, ['--headless', '--', '--asset-import-cache', cache, '--smoke-test', '--asset-import-profile'], true);
  assert.match(replay, /APP startup PASS: game/);
  assert.match(replay, /units=86/);
  timings = replay.split(/\r?\n/).filter(line => line.startsWith('ASSET_IMPORT_PROFILE ')).map(line => JSON.parse(line.slice('ASSET_IMPORT_PROFILE '.length)));
  assert.equal(timings.length, 3);
  assert.deepEqual(timings.map(row => row.stage), ["index_content_hashes", "index_scene_hashes", "install_cached_paths"]);
  assert.deepEqual(fs.readdirSync(path.join(cache, 'indexes')), before);
  capture = path.join(output, 'game.png');
  launch(binary, ['--position', '-10000,-10000', '--rendering-method', 'gl_compatibility', '--', '--asset-import-cache', cache, '--capture-game', capture], true);
  assert.ok(fs.statSync(capture).size > 10000);
  reviewCapture = path.join(output, 'asset-review.png');
  launch(binary, ['--position', '-10000,-10000', '--rendering-driver', 'vulkan', '--', '--asset-import-cache', cache, '--asset-review', '--capture-game', reviewCapture], true);
  assert.ok(fs.statSync(reviewCapture).size > 10000);
} finally {
  if (fs.existsSync(path.join(cache, 'inputs-disabled')) && !fs.existsSync(path.join(cache, 'inputs'))) fs.renameSync(path.join(cache, 'inputs-disabled'), path.join(cache, 'inputs'));
  if (fs.existsSync(path.join(bundle, 'node.disabled'))) fs.renameSync(path.join(bundle, 'node.disabled'), path.join(bundle, 'node.exe'));
}
fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify({binary, gameDir, cacheRoot: cache, capture, reviewCapture,
  startupTimings: timings, reusedColdImport: Boolean(reuse), recoveredPublishedIndex: Boolean(recover), recoveredIndex, retriedInterruptedImport: Boolean(retry), sceneCacheHits: cold.result.results.filter(row => row.cache?.status === "hit").length, coverage: cold.result.content.coverage, models: cold.result.results.length, contentFiles: cold.result.content.files.length,
  checks: [recover ? 'recovered_published_index_after_acceptance_timeout' : 'full_background_import', recover ? 'prior_batched_compilation_artifacts' : 'batched_compilation', 'no_external_asset_root', 'complete_reference_coverage',
    'no_packaged_original_map_or_definitions', 'offline_index_replay_without_node_or_ir', '86_unit_map_startup', 'rendered_map_and_icons', 'vulkan_asset_review_models_portraits_pathing'],
}, null, 2));
console.log(recover ? 'PASS: published full index -> offline standalone startup and rendered map' : 'PASS: original installation -> full background import -> standalone cached game');
console.log('Report: ' + path.join(output, 'report.json'));
