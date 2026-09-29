import { prepareWorkerProject } from './prepare-worker-project.mjs';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { convertOneMdx } from './convert-mdx.js';
import { createBakeTask, writeBakeTask } from './bake-task.js';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
assert.ok(process.env.GODOT, 'Set GODOT to the engine executable');
const source = path.resolve(process.env.ASSET_SOURCE || path.join(repo, '.cache/wc3-assets'));
const output = path.join(repo, '.cache/fx-preview');
fs.mkdirSync(output, {recursive:true});
fs.writeFileSync(path.join(output, 'project.godot'), 'config_version=5\n[application]\nconfig/name="FX Samples"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n');
prepareWorkerProject(repo, output);
const records = [];
for (const [logical, emitters, billboards] of [
  ['Abilities/Weapons/PriestMissile/PriestMissile.mdx', 2, 1],
  ['Abilities/Weapons/FireBallMissile/FireBallMissile.mdx', 3, 4],
  ['Units/Human/HeroArchMage/HeroArchMage.mdx', 3, 1],
]) {
  await convertOneMdx(path.join(source, logical), logical, source, output);
  const stem = logical.slice(0,-4);
  const taskPath = path.join(output, `${path.basename(stem)}.task.json`);
  const resultPath = path.join(output, `${path.basename(stem)}.result.json`);
  writeBakeTask(taskPath, createBakeTask({asset_id:stem.toLowerCase(),ir_path:`${stem}.ir.json`,geometry_path:`${stem}.gltf`,output_scene:`${stem}.scn`}));
  const child = spawnSync(process.env.GODOT, ['--headless','--path',output,'--log-file',`${resultPath}.log`,'-s','res://import_worker.gd','--','--task',taskPath,'--result',resultPath], {encoding:'utf8', timeout:120000});
  assert.ifError(child.error);
  assert.equal(child.status,0,child.stdout+child.stderr);
  assert.doesNotMatch(child.stdout+child.stderr,/ERROR:/);
  const result = JSON.parse(fs.readFileSync(resultPath,'utf8'));
  assert.equal(result.ok,true);
  assert.equal(result.effect_compile.emitters,emitters);
  assert.equal(result.effect_compile.billboards,billboards);
  assert.equal(result.deliverable,false);
  records.push({id:stem.toLowerCase(),logical_path:logical,scn_path:`${stem}.scn`,preview_absolute_path:path.join(output,`${stem}.scn`),severity:'P1',visual_status:'unverified',profile:'fidelity',issues:result.diagnostics});
  console.log(JSON.stringify({logical,effects:result.effect_compile,materials:result.material_compile,geosets:result.geoset_compile}));
}
fs.writeFileSync(path.join(output,'report.json'),JSON.stringify({schema_version:1,records},null,2));
console.log(`FX preview report: ${path.join(output,'report.json')}`);
// Fresh project deliberately has no converter scripts, source models or textures.
const standalone = path.join(repo, '.cache/fx-runtime-check');
fs.mkdirSync(standalone, {recursive:true});
fs.copyFileSync(path.join(output,'project.godot'),path.join(standalone,'project.godot'));
fs.copyFileSync(path.join(repo,'tests/integration/selftest_import_fx.gd'),path.join(standalone,'selftest_import_fx.gd'));
for (const record of records) fs.copyFileSync(record.preview_absolute_path,path.join(standalone,path.basename(record.preview_absolute_path)));
const check = spawnSync(process.env.GODOT,['--headless','--path',standalone,'--log-file',path.join(standalone,'run.log'),'-s','res://selftest_import_fx.gd'],{encoding:'utf8',timeout:120000});
assert.ifError(check.error);
assert.equal(check.status,0,check.stdout+check.stderr);
assert.doesNotMatch(check.stdout+check.stderr,/ERROR:/);
assert.match(check.stdout,/FX runtime PASS/);
console.log(check.stdout.trim());
