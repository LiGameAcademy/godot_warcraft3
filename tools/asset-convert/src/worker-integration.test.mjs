import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { convertOneMdx } from './convert-mdx.js';
import { createBakeTask, writeBakeTask, validateWorkerResult } from './bake-task.js';

// Explicit real-asset integration check: missing prerequisites fail, never skip.
const repo = fileURLToPath(new URL('../../../', import.meta.url));
const godot = process.env.GODOT;
assert.ok(godot, 'Set GODOT to the engine executable');
const source = path.resolve(process.env.ASSET_SOURCE || path.join(repo, 'assets/.staging/wc3-assets'));
const logical = 'Units/Human/Footman/Footman.mdx';
assert.ok(fs.existsSync(path.join(source, logical)), 'Footman source is required');
const scratch = path.join(repo, 'tools/asset-convert/tmp');
fs.mkdirSync(scratch, {recursive: true});
const output = fs.mkdtempSync(path.join(scratch, 'worker-'));
fs.writeFileSync(path.join(output, 'project.godot'), 'config_version=5\n[application]\nconfig/name="Import Worker Test"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n');
fs.copyFileSync(path.join(repo, 'tools/godot/import_worker.gd'), path.join(output, 'import_worker.gd'));
await convertOneMdx(path.join(source, logical), logical, source, output);
const stem = logical.slice(0, -4);
const task = createBakeTask({asset_id: stem.toLowerCase(), ir_path: `${stem}.ir.json`, geometry_path: `${stem}.gltf`, output_scene: 'result.scn'});
const taskPath = path.join(output, 'task.json');
const resultPath = path.join(output, 'result.json');
function run() {
  fs.rmSync(resultPath, {force: true});
  const child = spawnSync(godot, ['--headless', '--path', output, '--log-file', path.join(output, 'godot.log'), '-s', 'res://import_worker.gd', '--', '--task', taskPath, '--result', resultPath], {encoding: 'utf8', timeout: 120000});
  assert.ifError(child.error);
  assert.ok(fs.existsSync(resultPath), child.stdout + child.stderr);
  const result = JSON.parse(fs.readFileSync(resultPath, 'utf8'));
  assert.equal(validateWorkerResult(result).ok, true);
  return {child, result};
}
writeBakeTask(taskPath, task);
const success = run();
assert.equal(success.child.status, 0, success.child.stdout + success.child.stderr);
assert.equal(success.result.ok, true, JSON.stringify(success.result));
assert.equal(success.result.deliverable, false);
assert.ok(success.result.inventory.meshes > 0);
assert.ok(success.result.inventory.bones > 0);
assert.ok(success.result.inventory.animations > 0);
fs.writeFileSync(path.join(output, 'verify.gd'), `extends SceneTree
func _initialize() -> void:
 var packed: PackedScene = load("res://result.scn")
 if packed == null:
  quit(1)
  return
 var instance: Node = packed.instantiate()
 var queue: Array[Node] = [instance]
 var counts: Dictionary = {"nodes": 0, "meshes": 0, "surfaces": 0, "bones": 0, "animations": 0}
 while not queue.is_empty():
  var node: Node = queue.pop_back()
  counts.nodes += 1
  if node is MeshInstance3D and node.mesh != null:
   counts.meshes += 1
   counts.surfaces += node.mesh.get_surface_count()
  if node is Skeleton3D:
   counts.bones += node.get_bone_count()
  if node is AnimationPlayer:
   counts.animations += node.get_animation_list().size()
  for child: Node in node.get_children():
   queue.append(child)
 var file: FileAccess = FileAccess.open("res://verified.json", FileAccess.WRITE)
 file.store_string(JSON.stringify(counts))
 file.close()
 instance.free()
 quit(0)
`);
const verify = spawnSync(godot, ['--headless', '--path', output, '--log-file', path.join(output, 'verify.log'), '-s', 'res://verify.gd'], {encoding: 'utf8', timeout: 120000});
assert.ifError(verify.error);
assert.equal(verify.status, 0, verify.stdout + verify.stderr);
assert.doesNotMatch(verify.stdout + verify.stderr, /ERROR:/);
assert.deepEqual(JSON.parse(fs.readFileSync(path.join(output, 'verified.json'), 'utf8')), success.result.inventory);
// Invalid IR must fail before touching the previously generated scene.
const saved = fs.readFileSync(path.join(output, 'result.scn'));
task.ir_path = 'missing.ir.json';
writeBakeTask(taskPath, task);
const failure = run();
assert.notEqual(failure.child.status, 0);
assert.equal(failure.result.ok, false);
assert.equal(failure.result.diagnostics[0].code, 'ir_invalid');
assert.deepEqual(fs.readFileSync(path.join(output, 'result.scn')), saved);
console.log(JSON.stringify({output, inventory: success.result.inventory, checks: ['real_model_roundtrip', 'fresh_process_reload', 'missing_ir_preserves_scene']}, null, 2));
