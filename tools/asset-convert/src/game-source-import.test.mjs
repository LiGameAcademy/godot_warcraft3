import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {packageRuntime} from '../scripts/package-runtime.mjs';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const base = path.join(repo,'tools/asset-convert/tmp');
fs.mkdirSync(base,{recursive:true});
const output = fs.mkdtempSync(path.join(base,'game-source-'));
const release = path.join(output,'release'); fs.mkdirSync(release);
const binary = path.join(release,'game.exe');
const gameDir = process.env.WC3_PATH || JSON.parse(fs.readFileSync(path.join(repo,'tools/bootstrap.config.json'))).wc3.path;
assert.ok(process.env.GODOT);
let sequence=0;
function launch(executable,args,player=false) {
  const child=spawnSync(executable,args,{cwd:repo,encoding:'utf8',timeout:240000,
    env:player?{...process.env,PATH:'',GODOT:'',ASSET_SOURCE:'',STORMLIB_DLL:'',NODE_PATH:'',NODE_OPTIONS:''}:process.env});
  assert.ifError(child.error);
  const log=child.stdout+child.stderr;
  fs.writeFileSync(path.join(output,`run-${sequence++}.log`),log);
  assert.doesNotMatch(log,/SCRIPT ERROR|Parse Error|Compile Error|Export .NET Project:/);
  return {status:child.status,log};
}
assert.equal(launch(process.env.PYTHON||'python',[path.join(repo,'tools/workspace/sync_packages.py'),'--app','game']).status,0);
const exported=launch(process.env.GODOT,['--headless','--path',path.join(repo,'apps/game'),'--export-release','Windows Desktop',binary]);
assert.equal(exported.status,0,exported.log);
const bundle=await packageRuntime(path.join(release,'asset-import-runtime'));
const resultPath=path.join(output,'result.json');
const cacheRoot=`user://wc3-cache/${path.basename(output)}`;
function run({dir=gameDir,request,ok=true,only=true}={}) {
  fs.rmSync(resultPath,{force:true});
  const args=['--headless','--','--warcraft-dir',dir,'--asset-import-cache',cacheRoot,'--asset-import-result',resultPath,only?'--asset-import-only':'--smoke-test'];
  // External map data is a separate lane, still required until the full map import phase.
  if(!only) args.push('--asset-root',path.join(repo,'assets'));
  if(request) args.push('--asset-import-request',request);
  const child=launch(binary,args,true);
  assert.equal(child.status,ok?0:1,child.log);
  const result=JSON.parse(fs.readFileSync(resultPath));
  assert.equal(result.ok,ok,JSON.stringify(result));
  return {result,log:child.log};
}
const cold=run();
assert.equal(cold.result.results.length,4);
assert.ok(cold.result.results.every(entry=>entry.cache.status==='rebuilt'));
assert.ok(cold.result.source.provenance.length>4);
for (const entry of cold.result.results) assert.ok(!entry.diagnostics.some(diagnostic => diagnostic.code==='texture_placeholder'));
const warm=run();
assert.ok(warm.result.results.every(entry=>entry.cache.status==='hit'));
assert.equal(warm.result.source.source_signature,cold.result.source.source_signature);
const before=JSON.stringify(warm.result.paths);
const manifest = JSON.parse(fs.readFileSync(warm.result.source.manifest_path));
const task = JSON.parse(fs.readFileSync(manifest.tasks[0]));
const gltf = JSON.parse(fs.readFileSync(task.geometry_path));
const png = path.resolve(path.dirname(task.geometry_path), gltf.images[0].uri);
fs.writeFileSync(png, 'broken texture');
const repaired = run();
assert.ok(repaired.result.results.every(entry=>entry.cache.status==='hit'));
assert.equal(JSON.stringify(repaired.result.paths),before);
const missing=run({dir:path.join(output,'not-installed'),ok:false});
assert.match(missing.result.diagnostics[0].message,/游戏目录不存在/);
const bad=path.join(output,'bad-request.json');
fs.writeFileSync(bad,JSON.stringify({request_version:1,models:['Units/../outside.mdx']}));
assert.match(run({request:bad,ok:false}).result.diagnostics[0].message,/logical_path_invalid/);
const absent=path.join(output,'missing-asset.json');
fs.writeFileSync(absent,JSON.stringify({request_version:1,models:['Units/NoSuchAsset.mdx']}));
assert.match(run({request:absent,ok:false}).result.diagnostics[0].message,/source_dependency_missing/);
fs.renameSync(path.join(bundle,'node.exe'),path.join(bundle,'node.disabled'));
assert.equal(run({ok:false}).result.diagnostics[0].code,'source_runtime_missing');
fs.renameSync(path.join(bundle,'node.disabled'),path.join(bundle,'node.exe'));
const retry=run();
assert.ok(retry.result.results.every(entry=>entry.cache.status==='hit'));
assert.equal(JSON.stringify(retry.result.paths),before);
const playable=run({only:false});
assert.match(playable.log,/APP startup PASS: game/); assert.match(playable.log,/units=86/);
fs.writeFileSync(path.join(output,'report.json'),JSON.stringify({binary,gameDir,cacheRoot,result:playable.result,
  checks:['raw_mpq_to_ir_to_scn','texture_and_archive_provenance','repeat_cache_hit','derived_texture_repair','invalid_installation','traversal_rejected','missing_model','missing_bundled_runtime','retry_preserves_scenes','playable_map_startup']},null,2));
console.log('PASS: original MPQs -> bundled adapter -> IR -> cached SCN -> formal playable game, PATH empty');
console.log('Report: '+path.join(output,'report.json'));
