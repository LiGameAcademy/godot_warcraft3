import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {convertOneMdx} from './convert-mdx.js';
import {createBakeTask, writeBakeTask} from './bake-task.js';
import {prepareWorkerProject} from './prepare-worker-project.mjs';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
assert.ok(process.env.GODOT, 'Set GODOT to the engine executable');
const source = path.resolve(process.env.ASSET_SOURCE || path.join(repo,'.cache/wc3-assets'));
const output = path.join(repo,'.cache/ribbon-preview');
fs.mkdirSync(output,{recursive:true});
fs.writeFileSync(path.join(output,'project.godot'),'config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n');
prepareWorkerProject(repo,output);
const run = (project,script,args=[]) => {
  const result = spawnSync(process.env.GODOT,['--headless','--path',project,'--log-file',path.join(project,'run.log'),'-s',script,'--',...args],{encoding:'utf8',timeout:120000});
  assert.ifError(result.error);
  assert.equal(result.status,0,result.stdout+result.stderr);
  assert.doesNotMatch(result.stdout+result.stderr,/ERROR:/);
  return result.stdout;
};
const records=[];
for (const [logical,count] of [
  ['Abilities/Spells/NightElf/Rejuvenation/RejuvenationTarget.mdx',3],
  ['Abilities/Spells/Human/Resurrect/Resurrecttarget.mdx',4],
  ['Abilities/Spells/Human/FragmentationShards/FragMissile.mdx',1],
]) {
  await convertOneMdx(path.join(source,logical),logical,source,output);
  const stem=logical.slice(0,-4);
  const task=path.join(output,path.basename(stem)+'.task.json');
  const resultPath=path.join(output,path.basename(stem)+'.result.json');
  writeBakeTask(task,createBakeTask({asset_id:stem.toLowerCase(),ir_path:stem+'.ir.json',geometry_path:stem+'.gltf',output_scene:stem+'.scn'}));
  run(output,'res://import_worker.gd',['--task',task,'--result',resultPath]);
  const result=JSON.parse(fs.readFileSync(resultPath));
  assert.equal(result.ok,true);
  assert.equal(result.effect_compile.ribbons,count);
  assert.ok(!result.diagnostics.some(d=>d.code==='ribbon_controls_pending'));
  records.push({id:stem.toLowerCase(),logical_path:logical,scn_path:stem+'.scn',preview_absolute_path:path.join(output,stem+'.scn'),severity:'P1',visual_status:'unverified',profile:'fidelity',issues:result.diagnostics});
  console.log(`${logical}: ${count} ribbons compiled`);
}
fs.writeFileSync(path.join(output,'report.json'),JSON.stringify({schema_version:1,records},null,2));
const standalone=path.join(repo,'.cache/ribbon-runtime-check');
fs.mkdirSync(standalone,{recursive:true});
fs.copyFileSync(path.join(output,'project.godot'),path.join(standalone,'project.godot'));
for (const record of records) fs.copyFileSync(record.preview_absolute_path,path.join(standalone,path.basename(record.preview_absolute_path)));
fs.copyFileSync(path.join(repo,'tests/integration/selftest_import_ribbon.gd'),path.join(standalone,'selftest_import_ribbon.gd'));
assert.match(run(standalone,'res://selftest_import_ribbon.gd'),/Ribbon runtime PASS/);
console.log('Ribbon runtime PASS: standalone reload, animation, pause/rewind, expiry, instance isolation');
