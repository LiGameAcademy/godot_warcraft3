import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {convertOneMdx} from './convert-mdx.js';
import {createBakeTask, writeBakeTask} from './bake-task.js';
import {prepareWorkerProject} from './prepare-worker-project.mjs';

// Node and the editor only prepare/export the experiment. Player phases execute
// the release binary with an empty PATH and a separate, read-only input directory.
const repo = fileURLToPath(new URL('../../../', import.meta.url));
assert.equal(process.platform, 'win32', 'This experiment targets Windows exports');
assert.ok(process.env.GODOT, 'Set GODOT to the editor executable');
const source = path.resolve(process.env.ASSET_SOURCE || path.join(repo, 'assets/.staging/wc3-assets'));
const base = path.join(repo, 'tools/asset-convert/tmp');
fs.mkdirSync(base, {recursive:true});
const scratch = fs.mkdtempSync(path.join(base, 'exported-'));
const project = path.join(scratch, 'project');
const inputs = path.join(scratch, 'inputs');
const release = path.join(scratch, 'release');
for (const dir of [project, inputs, release]) fs.mkdirSync(dir);
prepareWorkerProject(repo, project);
fs.copyFileSync(path.join(repo, 'tests/integration/runtime_import_probe.gd'), path.join(project, 'runtime_import_probe.gd'));
fs.writeFileSync(path.join(project, 'main.tscn'), '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://runtime_import_probe.gd" id="1"]\n[node name="RuntimeImportProbe" type="Node"]\nscript = ExtResource("1")\n');
fs.writeFileSync(path.join(project, 'project.godot'), 'config_version=5\n[application]\nconfig/name="Runtime Import Experiment"\nrun/main_scene="res://main.tscn"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n');
fs.writeFileSync(path.join(project, 'export_presets.cfg'), '[preset.0]\nname="Windows Desktop"\nplatform="Windows Desktop"\nexport_filter="all_resources"\ninclude_filter="*.source"\nscript_export_mode=2\n[preset.0.options]\nbinary_format/architecture="x86_64"\nbinary_format/embed_pck=false\ndebug/export_console_wrapper=1\n');
function run(executable, args, cwd, player = false) {
  const child = spawnSync(executable, args, {cwd, encoding:'utf8', timeout:180000,
    env:player ? {...process.env, PATH:'', GODOT:'', ASSET_SOURCE:''} : process.env});
  assert.ifError(child.error);
  const log = child.stdout + child.stderr;
  fs.writeFileSync(path.join(scratch, `run-${run.index++}.log`), log);
  return {status:child.status, log};
}
run.index = 0;
const binary = path.join(release, 'runtime-import.exe');
const exported = run(process.env.GODOT, ['--headless', '--path', project, '--export-release', 'Windows Desktop', binary], project);
assert.equal(exported.status, 0, exported.log);
assert.ok(fs.existsSync(binary));
function snapshot(directory) {
  const files = fs.readdirSync(directory, {recursive:true, withFileTypes:true});
  return files.filter(entry => entry.isFile()).map(entry => {
    const absolute = path.join(entry.parentPath ?? entry.path, entry.name);
    return [path.relative(directory, absolute), createHash('sha256').update(fs.readFileSync(absolute)).digest('hex')];
  }).sort((a,b) => a[0].localeCompare(b[0]));
}
const records = [];
const runId = path.basename(scratch);
for (const [logical, expected] of [
  ['Units/Human/Footman/Footman.mdx', {particles:0, ribbons:0, billboard_nodes:1}],
  ['Abilities/Weapons/PriestMissile/PriestMissile.mdx', {particles:2, ribbons:0, billboard_nodes:1}],
  ['Abilities/Spells/NightElf/Rejuvenation/RejuvenationTarget.mdx', {particles:0, ribbons:3, billboard_nodes:0}],
]) {
  await convertOneMdx(path.join(source, logical), logical, source, inputs);
  const stem = logical.slice(0,-4);
  const name = path.basename(stem);
  const task = path.join(inputs, `${name}.task.json`);
  const resultPath = path.join(scratch, `${name}.result.json`);
  const reloadPath = path.join(scratch, `${name}.reload.json`);
  writeBakeTask(task, createBakeTask({asset_id:stem.toLowerCase(),
    ir_path:path.join(inputs, `${stem}.ir.json`), geometry_path:path.join(inputs, `${stem}.gltf`),
    output_scene:`user://wc3-cache/${runId}/${name}.scn`}));
  const inputBefore = snapshot(inputs);
  const compiled = run(binary, ['--headless', '--', '--compile', task, resultPath], release, true);
  assert.equal(compiled.status, 0, compiled.log);
  assert.doesNotMatch(compiled.log, /SCRIPT ERROR|ERROR:/);
  const result = JSON.parse(fs.readFileSync(resultPath, 'utf8'));
  assert.equal(result.ok, true);
  assert.deepEqual(snapshot(inputs), inputBefore, 'Runtime modified source inputs');
  assert.ok(result.output_scene.includes('wc3-cache'));
  records.push({name, expected, resultPath, reloadPath, output_scene:result.output_scene});
}
// A rejected IR must preserve an existing good scene; retry is a new invocation.
const priest = records.find(record => record.name === 'PriestMissile');
const validTask = JSON.parse(fs.readFileSync(path.join(inputs, 'PriestMissile.task.json')));
const badIr = path.join(inputs, 'corrupt.ir.json');
fs.writeFileSync(badIr, '{"schema_version":999}');
const badTask = path.join(inputs, 'corrupt.task.json');
writeBakeTask(badTask, {...validTask, ir_path:badIr});
const failedPath = path.join(scratch, 'failed.result.json');
const oldSceneHash = createHash('sha256').update(fs.readFileSync(priest.output_scene)).digest('hex');
const rejected = run(binary, ['--headless', '--', '--compile', badTask, failedPath], release, true);
assert.equal(rejected.status, 2, rejected.log);
const failure = JSON.parse(fs.readFileSync(failedPath));
assert.equal(failure.ok, false);
assert.equal(failure.diagnostics[0].code, 'ir_invalid');
assert.equal(createHash('sha256').update(fs.readFileSync(priest.output_scene)).digest('hex'), oldSceneHash);
const retry = run(binary, ['--headless', '--', '--compile', path.join(inputs, 'PriestMissile.task.json'), priest.resultPath], release, true);
assert.equal(retry.status, 0, retry.log);
assert.doesNotMatch(retry.log, /SCRIPT ERROR|ERROR:/);
console.log('Exported runtime PASS: rejected IR preserves cache; valid retry succeeds');
// Missing export payload must be a diagnostic failure, never a partial success.
const presetPath = path.join(project, 'export_presets.cfg');
const preset = fs.readFileSync(presetPath, 'utf8');
fs.writeFileSync(presetPath, preset.replace('include_filter="*.source"', 'include_filter=""'));
const missingBinary = path.join(release, 'runtime-import-no-source.exe');
const missingExport = run(process.env.GODOT, ['--headless', '--path', project, '--export-release', 'Windows Desktop', missingBinary], project);
assert.equal(missingExport.status, 0, missingExport.log);
fs.writeFileSync(presetPath, preset);
const missingResultPath = path.join(scratch, 'missing-payload.result.json');
const missingPayload = run(missingBinary, ['--headless', '--', '--compile', path.join(inputs, 'Footman.task.json'), missingResultPath], release, true);
assert.equal(missingPayload.status, 1, missingPayload.log);
const missingResult = JSON.parse(fs.readFileSync(missingResultPath));
assert.equal(missingResult.ok, false);
assert.ok(missingResult.diagnostics.some(item => item.code === 'billboard_script_invalid' && item.severity === 'error'));
console.log('Exported runtime PASS: missing embedded source is rejected');
// Remove access to all converter inputs before restarting the exported process.
fs.renameSync(inputs, path.join(scratch, 'inputs-offline'));
for (const record of records) {
  const reloaded = run(binary, ['--headless', '--', '--reload', record.resultPath, record.reloadPath], release, true);
  assert.equal(reloaded.status, 0, reloaded.log);
  assert.doesNotMatch(reloaded.log, /SCRIPT ERROR|ERROR:/);
  const result = JSON.parse(fs.readFileSync(record.reloadPath, 'utf8'));
  assert.equal(result.reloaded, true);
  assert.deepEqual(result.runtime_features, record.expected, record.name);
  if (record.expected.particles) assert.equal(result.particle_isolation, true);
  console.log(`Exported runtime PASS: ${record.name}`);
}
fs.writeFileSync(path.join(scratch, 'report.json'), JSON.stringify({scratch, binary, records}, null, 2));
console.log(`Exported runtime report: ${path.join(scratch, 'report.json')}`);
