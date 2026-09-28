import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { convertOneMdx } from './convert-mdx.js';
import { createBakeTask, writeBakeTask } from './bake-task.js';

// Broader real-source smoke test; not a claim of complete visual fidelity.
const repo = fileURLToPath(new URL('../../../', import.meta.url));
assert.ok(process.env.GODOT, 'Set GODOT to the engine executable');
const source = path.resolve(process.env.ASSET_SOURCE || path.join(repo, 'assets/.staging/wc3-assets'));
const scratch = path.join(repo, 'tools/asset-convert/tmp');
fs.mkdirSync(scratch, { recursive: true });
const output = fs.mkdtempSync(path.join(scratch, 'material-samples-'));
fs.writeFileSync(path.join(output, 'project.godot'), 'config_version=5\n[application]\nconfig/name="Material Samples"\n');
for (const name of ['import_worker', 'import_skeleton_compiler', 'import_material_compiler', 'import_material_animation', 'import_team_material', 'import_geoset_visibility', 'import_geoset_curves']) {
  fs.copyFileSync(path.join(repo, `tools/godot/${name}.gd`), path.join(output, `${name}.gd`));
}
for (const logical of ['Units/Human/Priest/Priest.mdx', 'Units/Human/HeroArchMage/HeroArchMage.mdx']) {
  assert.ok(fs.existsSync(path.join(source, logical)), `Required real source: ${logical}`);
  await convertOneMdx(path.join(source, logical), logical, source, output);
  const stem = logical.slice(0, -4);
  const taskPath = path.join(output, `${path.basename(stem)}.task.json`);
  const resultPath = path.join(output, `${path.basename(stem)}.result.json`);
  writeBakeTask(taskPath, createBakeTask({asset_id: stem.toLowerCase(), ir_path: `${stem}.ir.json`, geometry_path: `${stem}.gltf`, output_scene: `${stem}.scn`}));
  const child = spawnSync(process.env.GODOT, ['--headless', '--path', output, '--log-file', `${resultPath}.log`, '-s', 'res://import_worker.gd', '--', '--task', taskPath, '--result', resultPath], {encoding: 'utf8', timeout: 120000});
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stdout + child.stderr);
  assert.doesNotMatch(child.stdout + child.stderr, /ERROR:/);
  const result = JSON.parse(fs.readFileSync(resultPath, 'utf8'));
  assert.equal(result.ok, true);
  assert.equal(result.deliverable, false);
  assert.ok(result.material_compile.team_surfaces > 0, JSON.stringify(result.material_compile));
  console.log(JSON.stringify({logical, output_scene: path.join(output, `${stem}.scn`), material_compile: result.material_compile}));
}
