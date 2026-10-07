import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {prepareSourceImport} from './runtime-source-import.mjs';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const gameDir = process.env.WC3_PATH || JSON.parse(fs.readFileSync(path.join(repo, 'tools/bootstrap.config.json'))).wc3.path;
const base = path.join(repo, 'tools/asset-convert/tmp');
fs.mkdirSync(base, {recursive: true});
const output = fs.mkdtempSync(path.join(base, 'particle-only-'));
const models = ['Doodads/Ruins/Water/BubbleGeyser/BubbleGeyser.mdx',
  'Doodads/Icecrown/Water/BubbleGeyserSteam/BubbleGeyserSteam.mdx',
  'Objects/Spawnmodels/Human/HCancelDeath/HCancelDeath.mdx'];
const prepared = await prepareSourceImport({gameDir, outDir: output, request: {request_version: 1, models}});
const manifest = JSON.parse(fs.readFileSync(prepared.manifest_path));
for (const taskPath of manifest.tasks) {
  const task = JSON.parse(fs.readFileSync(taskPath));
  const gltf = JSON.parse(fs.readFileSync(task.geometry_path));
  const ir = JSON.parse(fs.readFileSync(task.ir_path));
  assert.ok(!gltf.buffers?.length);
  assert.ok(!gltf.animations?.length);
  assert.ok(ir.animations.payload.sequences.length > 0);
  assert.ok(ir.particles.count > 0);
}
console.log('PASS: real particle-only glTF omits unused buffers and empty channels; clips and emitters preserved in IR');
console.log('Manifest: ' + prepared.manifest_path);
