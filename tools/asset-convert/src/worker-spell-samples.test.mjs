import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {convertOneMdx} from './convert-mdx.js';
import {createBakeTask, writeBakeTask} from './bake-task.js';
import {prepareWorkerProject} from './prepare-worker-project.mjs';
const repo = fileURLToPath(new URL('../../../', import.meta.url));
const source = path.join(repo, 'assets/.staging/wc3-assets');
const output = fs.mkdtempSync(path.join(repo, 'tools/asset-convert/tmp/spell-samples-'));
fs.writeFileSync(path.join(output, 'project.godot'), 'config_version=5\n[application]\nconfig/name="Spell Samples"\n');
prepareWorkerProject(repo, output);
for (const [logical, emitters] of [
  ['Units/Human/WaterElemental/WaterElemental.mdx', -1],
  ['Abilities/Spells/Human/Blizzard/BlizzardTarget.mdx', 5],
  ['Abilities/Spells/Other/FrostDamage/FrostDamage.mdx', -1],
  ['Abilities/Spells/Human/MassTeleport/MassTeleportCaster.mdx', 1],
  ['Abilities/Spells/Human/MassTeleport/MassTeleportTarget.mdx', 1],
  ['Abilities/Spells/Human/MassTeleport/MassTeleportTo.mdx', 5],
]) {
  await convertOneMdx(path.join(source, logical), logical, source, output);
  const stem = logical.slice(0, -4);
  const task = path.join(output, path.basename(stem) + '.task.json');
  const resultPath = task.replace('.task.json', '.result.json');
  writeBakeTask(task, createBakeTask({asset_id: stem.toLowerCase(), ir_path: stem + '.ir.json', geometry_path: stem + '.gltf', output_scene: stem + '.scn'}));
  const child = spawnSync(process.env.GODOT, ['--headless', '--path', output, '-s', 'res://import_worker.gd', '--', '--task', task, '--result', resultPath], {encoding: 'utf8', timeout: 120000});
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stdout + child.stderr);
  assert.doesNotMatch(child.stdout + child.stderr, /SCRIPT ERROR|ERROR:/);
  const result = JSON.parse(fs.readFileSync(resultPath));
  assert.equal(result.ok, true);
  if (emitters >= 0) assert.equal(result.effect_compile.emitters, emitters);
  assert.ok(!result.diagnostics.some(row => row.code === 'particle_controls_pending'));
  console.log(JSON.stringify({logical, effects: result.effect_compile, materials: result.material_compile, geosets: result.geoset_compile}));
}
console.log('PASS: original Water Elemental, Blizzard and Mass Teleport compiled: ' + output);
