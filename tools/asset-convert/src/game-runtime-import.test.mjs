import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {convertOneMdx} from './convert-mdx.js';
import {createBakeTask, writeBakeTask} from './bake-task.js';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
assert.equal(process.platform,'win32');
assert.ok(process.env.GODOT,'Set GODOT');
const base = path.join(repo,'tools/asset-convert/tmp');
fs.mkdirSync(base,{recursive:true});
const output = fs.mkdtempSync(path.join(base,'game-runtime-'));
const inputs = path.join(output,'inputs');
fs.mkdirSync(inputs);
const source = path.resolve(process.env.ASSET_SOURCE || path.join(repo,'assets/.staging/wc3-assets'));
const binary = path.resolve(process.env.GAME_BINARY || path.join(output,'release/game.exe'));
let sequence = 0;
function launch(executable,args,player=false,timeout=240000) {
  const child = spawnSync(executable,args,{cwd:repo,encoding:'utf8',timeout,
    env:player ? {...process.env,PATH:'',GODOT:'',ASSET_SOURCE:''} : process.env});
  assert.ifError(child.error);
  const log = child.stdout + child.stderr;
  fs.writeFileSync(path.join(output,`run-${sequence++}.log`),log);
  return {status:child.status,log};
}
if (!process.env.GAME_BINARY) {
  const synced = launch(process.env.PYTHON || 'python',[path.join(repo,'tools/workspace/sync_packages.py'),'--app','game']);
  assert.equal(synced.status,0,synced.log);
  fs.mkdirSync(path.dirname(binary),{recursive:true});
  const exported = launch(process.env.GODOT,['--headless','--path',path.join(repo,'apps/game'),'--export-release','Windows Desktop',binary]);
  assert.equal(exported.status,0,exported.log);
  assert.doesNotMatch(exported.log,/SCRIPT ERROR|Parse Error|Compile Error|Export .NET Project:/);
}
assert.ok(fs.existsSync(binary),'Formal exported game is required');
const tasks = [];
for (const logical of ['Units/Human/Footman/Footman.mdx','Abilities/Weapons/PriestMissile/PriestMissile.mdx','Abilities/Spells/NightElf/Rejuvenation/RejuvenationTarget.mdx']) {
  await convertOneMdx(path.join(source,logical),logical,source,inputs);
  const stem = logical.slice(0,-4);
  const taskPath = path.join(inputs,path.basename(stem)+'.task.json');
  writeBakeTask(taskPath,createBakeTask({asset_id:stem.toLowerCase(),ir_path:path.join(inputs,stem+'.ir.json'),geometry_path:path.join(inputs,stem+'.gltf'),output_scene:`user://wc3-cache/${path.basename(output)}/${path.basename(stem)}.scn`}));
  tasks.push(taskPath);
}
const manifestPath = path.join(output,'manifest.json');
fs.writeFileSync(manifestPath,JSON.stringify({manifest_version:1,tasks},null,2));
const resultPath = path.join(output,'game-import.result.json');
function run({only=true,ok=true}={}) {
  fs.rmSync(resultPath,{force:true});
  const args = ['--headless','--','--asset-root',path.join(repo,'assets'),'--asset-import-manifest',manifestPath,'--asset-import-result',resultPath,only ? '--asset-import-only' : '--smoke-test'];
  const child = launch(binary,args,true);
  assert.equal(child.status,ok ? 0 : 1,child.log);
  assert.doesNotMatch(child.log,/SCRIPT ERROR|Parse Error|Compile Error|DefStore 缺少|EditorI18n: missing/);
  assert.ok(fs.existsSync(resultPath),child.log);
  const result = JSON.parse(fs.readFileSync(resultPath));
  assert.equal(result.ok,ok,JSON.stringify(result));
  if (ok) {
    assert.equal(Object.keys(result.paths).length,3);
    assert.match(child.log,/GAME asset import PASS/);
    for (const entry of result.results) assert.equal(result.paths[entry.asset_id+'.scn'],entry.output_scene);
  }
  return {result,log:child.log};
}
const first = run();
assert.ok(first.result.results.every(entry => entry.cache.status==='rebuilt'));
const second = run();
assert.ok(second.result.results.every(entry => entry.cache.status==='hit'));
const priest = JSON.parse(fs.readFileSync(tasks[1]));
const original = fs.readFileSync(priest.ir_path);
const changed = JSON.parse(original);
changed.source.source_hash = 'game invalidation test';
fs.writeFileSync(priest.ir_path,JSON.stringify(changed));
const invalidated = run();
assert.equal(invalidated.result.results[1].cache.status,'rebuilt');
fs.writeFileSync(priest.ir_path,original);
const restored = run();
const scene = restored.result.results[1].output_scene;
fs.writeFileSync(scene,'corrupt cache');
const repaired = run();
assert.equal(repaired.result.results[1].cache.reason,'scene_corrupt');
const preserved = repaired.result.results[1].output_scene;
const digest = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const before = digest(preserved);
fs.writeFileSync(priest.ir_path,'{"schema_version":999}');
run({ok:false});
assert.equal(digest(preserved),before);
fs.writeFileSync(priest.ir_path,original);
const retry = run();
assert.ok(retry.result.results.every(entry => entry.cache.status==='hit'));
const playable = run({only:false});
assert.match(playable.log,/APP startup PASS: game/);
assert.match(playable.log,/units=86/);
fs.writeFileSync(path.join(output,'report.json'),JSON.stringify({binary,manifestPath,result:playable.result,checks:['first_import','cache_hit','signature_invalidation','corrupt_scene_rebuild','failed_ir_preserves_previous','valid_retry','game_resolves_actual_cache_paths','playable_map_startup']},null,2));
console.log('FORMAL GAME IMPORT PASS: cold/hit/invalidation/corruption/retry, cached scenes resolved, playable map ready');
console.log('Report: '+path.join(output,'report.json'));
