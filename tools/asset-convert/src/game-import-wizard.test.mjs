import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawn, spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {packageRuntime} from '../scripts/package-runtime.mjs';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const base = path.join(repo, 'tools/asset-convert/tmp');
fs.mkdirSync(base, {recursive: true});
const output = fs.mkdtempSync(path.join(base, 'wizard-'));
const release = path.join(output, 'release');
fs.mkdirSync(release);
const binary = path.join(release, 'game.exe');
const gameDir = JSON.parse(fs.readFileSync(path.join(repo, 'tools/bootstrap.config.json'))).wc3.path;
let sequence = 0;

function run(executable, args, player = false) {
  // The console wrapper can outlive the engine after export; spawn the engine directly.
  if (executable === process.env.GODOT && fs.existsSync(executable.replace(/_console\.exe$/i, '.exe'))) {
    executable = executable.replace(/_console\.exe$/i, '.exe');
  }
  const child = spawnSync(executable, args, {
    cwd: repo,
    encoding: 'utf8',
    timeout: 240000,
    env: player ? {...process.env, PATH: '', GODOT: '', ASSET_SOURCE: '', STORMLIB_DLL: '',
      NODE_PATH: '', NODE_OPTIONS: ''} : process.env,
  });
  const log = (child.stdout || '') + (child.stderr || '');
  fs.writeFileSync(path.join(output, `run-${sequence++}.log`), log);
  assert.ifError(child.error);
  assert.equal(child.status, 0, log);
  assert.doesNotMatch(log, /SCRIPT ERROR|Parse Error|Compile Error|Export .NET Project:/);
  return log;
}

run(process.env.PYTHON || 'python', [path.join(repo, 'tools/workspace/sync_packages.py'), '--app', 'game']);
for (const extension of ['gd', 'tscn']) {
  fs.copyFileSync(path.join(repo, `tests/integration/selftest_asset_import_wizard.${extension}`),
    path.join(repo, `apps/game/tmp/selftest_asset_import_wizard.${extension}`));
}
// Official release templates prohibit command-line scene overrides. This test-only
// bootstrap runs the fixture for --mode, and the real boot for workers and gameplay.
fs.writeFileSync(path.join(repo, 'apps/game/tmp/wizard_probe_boot.gd'), `extends "res://boot.gd"
func _start() -> void:
	if "--mode" in OS.get_cmdline_user_args():
		var probe: Node = (load("res://tmp/selftest_asset_import_wizard.tscn") as PackedScene).instantiate()
		get_tree().root.add_child(probe)
	else:
		super._start()
`);
fs.writeFileSync(path.join(repo, 'apps/game/tmp/wizard_probe_boot.tscn'), `[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tmp/wizard_probe_boot.gd" id="1"]
[node name="Boot" type="Node"]
script = ExtResource("1")
`);
const project = path.join(repo, 'apps/game/project.godot');
const originalProject = fs.readFileSync(project);
const preset = path.join(repo, 'apps/game/export_presets.cfg');
const original = fs.readFileSync(preset);
try {
  fs.writeFileSync(project, originalProject.toString().replace('res://boot.tscn', 'res://tmp/wizard_probe_boot.tscn'));
  fs.writeFileSync(preset, original.toString().replace('tests/*,tmp/*,', 'tests/*,'));
  run(process.env.GODOT, ['--headless', '--path', path.join(repo, 'apps/game'), '--editor', '--import']);
  run(process.env.GODOT, ['--headless', '--path', path.join(repo, 'apps/game'), '--export-release', 'Windows Desktop', binary]);
} finally {
  fs.writeFileSync(preset, original);
  fs.writeFileSync(project, originalProject);
}
const bundle = await packageRuntime(path.join(release, 'asset-import-runtime'));
const cache = path.join(output, 'cache');

function probe(mode, extra = [], root = cache) {
  const report = path.join(output, mode + '.json');
  const rendering = extra.includes('--capture')
    ? ['--position', '-10000,-10000', '--rendering-method', 'gl_compatibility'] : ['--headless'];
  run(binary, [...rendering, '--', '--mode', mode, '--cache', root,
    '--source', gameDir, '--report', report, ...extra], true);
  return JSON.parse(fs.readFileSync(report));
}

assert.equal(probe('source-overlap', [], gameDir).result.diagnostics[0].code, 'source_cache_overlap');
const cold = probe('cold');
assert.equal(cold.result.results.length, 4);
assert.ok(cold.frames > 10);
assert.ok(cold.events.some(event => event.stage === '编译场景缓存'));
const indexDir = path.join(cache, 'indexes');
const indexBefore = fs.readdirSync(indexDir);
const coldPaths = JSON.stringify(cold.result.paths);
for (const mode of ['hold-writer', 'hold-reader']) {
  const ready = path.join(output, mode + '.ready');
  const holder = spawn(binary, ['--headless', '--', '--mode', mode, '--cache', cache, '--source', gameDir, '--report', ready], {cwd: repo, stdio: 'ignore'});
  try {
    const deadline = Date.now() + 20000;
    while (!fs.existsSync(ready) && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 100));
    assert.ok(fs.existsSync(ready), 'Concurrent cache holder did not start');
    assert.equal(probe('busy').result.diagnostics[0].code, 'cache_busy');
    assert.deepEqual(fs.readdirSync(indexDir), indexBefore);
  } finally {
    holder.kill();
    if (holder.exitCode === null) await new Promise(resolve => holder.once('exit', resolve));
  }
}
assert.equal(probe('cancel-source').result.cancelled, true);
assert.deepEqual(fs.readdirSync(indexDir), indexBefore);
assert.equal(probe('cancel-compile').result.cancelled, true);
assert.deepEqual(fs.readdirSync(indexDir), indexBefore);
fs.renameSync(path.join(bundle, 'node.exe'), path.join(bundle, 'node.disabled'));
fs.renameSync(path.join(cache, 'inputs'), path.join(cache, 'inputs-disabled'));
assert.equal(probe('warm').result.resumed, true);
fs.renameSync(path.join(cache, 'inputs-disabled'), path.join(cache, 'inputs'));
fs.renameSync(path.join(bundle, 'node.disabled'), path.join(bundle, 'node.exe'));
const cleanup = path.join(bundle, 'tools/asset-convert/src/cache-maintenance.mjs');
const preview = JSON.parse(run(path.join(bundle, 'node.exe'), [cleanup, cache], true));
assert.equal(preview.apply, false);
assert.ok(preview.reclaimBytes > 0);
const cleaned = JSON.parse(run(path.join(bundle, 'node.exe'), [cleanup, cache, '--apply'], true));
assert.equal(cleaned.apply, true);
assert.deepEqual(fs.readdirSync(indexDir), indexBefore);
assert.equal(probe('warm').result.resumed, true);
const retry = probe('retry', [], path.join(output, 'retry-cache'));
assert.equal(retry.result.ok, true);
const damaged = path.join(indexDir, indexBefore.at(-1));
fs.writeFileSync(damaged, 'broken index');
const rebuilt = probe('rebuild');
assert.equal(rebuilt.result.ok, true);
assert.equal(JSON.stringify(rebuilt.result.paths), coldPaths);
probe('render', ['--capture']);
// A four-model fixture cannot validate the complete development map.
// game-development-import.test.mjs owns the standalone game startup regression.
fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify({
  binary, gameDir, cache,
  checks: ['source_directory_readonly', 'responsive_cold_import', 'source_cancel_preserves_index',
    'compile_cancel_preserves_index', 'offline_index_restore', 'invalid_directory_retry',
    'broken_index_rebuild', 'rendered_wizard', 'concurrent_writer_exclusion', 'active_reader_exclusion', 'bundled_cache_cleanup', 'restore_after_cleanup'],
}, null, 2));
console.log('PASS: formal wizard cold/progress/responsive/cancel-source/cancel-compile/offline/retry/index rebuild');
console.log('Report: ' + path.join(output, 'report.json'));
