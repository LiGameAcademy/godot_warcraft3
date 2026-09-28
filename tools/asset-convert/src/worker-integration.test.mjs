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
fs.copyFileSync(path.join(repo, 'tools/godot/import_skeleton_compiler.gd'), path.join(output, 'import_skeleton_compiler.gd'));
fs.copyFileSync(path.join(repo, 'tools/godot/import_material_compiler.gd'), path.join(output, 'import_material_compiler.gd'));
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
assert.equal(success.result.skeleton_compile.rests, 40);
assert.equal(success.result.skeleton_compile.sockets, 9);
assert.equal(success.result.skeleton_compile.visibility_tracks, 91);
assert.ok(success.result.material_compile.compiled_surfaces > 0);
assert.ok(success.result.material_compile.diagnostics.some(d => d.code === 'multilayer_pending'));
fs.writeFileSync(path.join(output, 'verify.gd'), `extends SceneTree
func _initialize() -> void:
 call_deferred("_verify")
func _verify() -> void:
 var packed: PackedScene = load("res://result.scn")
 if packed == null:
  quit(1)
  return
 var instance: Node = packed.instantiate()
 root.add_child(instance)
 var ir: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://${stem}.ir.json"))
 var queue: Array[Node] = [instance]
 var counts: Dictionary = {"nodes": 0, "meshes": 0, "surfaces": 0, "bones": 0, "animations": 0}
 var player: AnimationPlayer
 var weapon: Marker3D
 var isolated_material: StandardMaterial3D
 while not queue.is_empty():
  var node: Node = queue.pop_back()
  counts.nodes += 1
  if node is MeshInstance3D and node.mesh != null:
   counts.meshes += 1
   counts.surfaces += node.mesh.get_surface_count()
   for surface: int in range(node.mesh.get_surface_count()):
    var material: Material = node.get_active_material(surface)
    if material.has_meta("import_material_id"):
     isolated_material = material
     if material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or not is_equal_approx(material.alpha_scissor_threshold, 0.75):
      push_error("Material mapping lost after reload")
      quit(1)
      return
  if node is Skeleton3D:
   counts.bones += node.get_bone_count()
   for entry: Dictionary in ir.skeleton.rest_payload.bones:
    var index: int = node.find_bone(entry.name)
    var t: Array = entry.translation
    var r: Array = entry.rotation
    var s: Array = entry.scale
    var expected: Transform3D = Transform3D(Basis(Quaternion(r[0], r[1], r[2], r[3])).scaled(Vector3(s[0], s[1], s[2])), Vector3(t[0], t[1], t[2]))
    if index < 0 or not node.get_bone_rest(index).is_equal_approx(expected):
     push_error("Rest transform mismatch")
     quit(1)
     return
  if node is BoneAttachment3D:
   if node.bone_idx < 0 or node.get_parent().get_bone_name(node.bone_idx) != node.bone_name:
    push_error("Socket bone mapping mismatch")
    quit(1)
    return
  if node.has_meta("import_socket"):
   if node.get_meta("import_socket") == "Weapon Ref":
    weapon = node
   for entry: Dictionary in ir.attachments.payload.attachments:
    if entry.name == node.get_meta("import_socket"):
     var p: Array = entry.pivot
     var expected: Vector3 = Vector3(p[0], p[1], p[2])
     if node.get_parent() is BoneAttachment3D:
      expected /= 0.01
     if not node.position.is_equal_approx(expected):
      push_error("Socket position mismatch")
      quit(1)
      return
  if node is AnimationPlayer:
   player = node
   counts.animations += node.get_animation_list().size()
  for child: Node in node.get_children():
   queue.append(child)
 if player == null or weapon == null:
  quit(1)
  return
 player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 for sample: Array in [["Stand-1", 0.0, true], ["DecayBone", 0.1, false], ["Stand-1", 0.0, true]]:
  player.play(sample[0])
  player.seek(sample[1], true)
  if weapon.visible != sample[2]:
   push_error("Socket visibility playback mismatch")
   quit(1)
   return
 var positions: Array[Vector3] = []
 var socket: BoneAttachment3D = weapon.get_parent()
 var skeleton: Skeleton3D = socket.get_parent()
 player.play("Attack-1")
 for time: float in [0.0, 0.3, 0.7]:
  player.seek(time, true)
  skeleton.force_update_all_bone_transforms()
  await process_frame
  # process_frame fires before node processing; allow deferred skeleton updates.
  await process_frame
  var expected: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(socket.bone_idx) * weapon.position
  if not weapon.global_position.is_equal_approx(expected):
   push_error("Socket failed to follow animated bone: actual=%s expected=%s" % [weapon.global_position, expected])
   quit(1)
   return
  positions.append(weapon.global_position)
 if positions[0].is_equal_approx(positions[1]) and positions[1].is_equal_approx(positions[2]):
  push_error("Attack socket did not move")
  quit(1)
  return
 if isolated_material == null:
  push_error("No compiled material survived reload")
  quit(1)
  return
 isolated_material.albedo_color = Color.MAGENTA
 for check: int in range(2):
  var other: Node = packed.instantiate()
  var other_nodes: Array[Node] = [other]
  while not other_nodes.is_empty():
   var node: Node = other_nodes.pop_back()
   if node is MeshInstance3D and node.mesh != null:
    for surface: int in range(node.mesh.get_surface_count()):
     var material: Material = node.get_active_material(surface)
     if material.has_meta("import_material_id") and (material == isolated_material or material.albedo_color == Color.MAGENTA):
      push_error("Material mutation leaked across instances")
      quit(1)
      return
   for child: Node in node.get_children():
    other_nodes.append(child)
  other.free()
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
const irPath = path.join(output, `${stem}.ir.json`);
const validIr = fs.readFileSync(irPath);
const invalidIr = JSON.parse(validIr);
invalidIr.skeleton.rest_payload.bones[0].name = 'missing_bone';
fs.writeFileSync(irPath, JSON.stringify(invalidIr));
const mappingFailure = run();
assert.notEqual(mappingFailure.child.status, 0);
assert.equal(mappingFailure.result.diagnostics[0].code, 'bone_mapping_failed');
assert.deepEqual(fs.readFileSync(path.join(output, 'result.scn')), saved);
fs.writeFileSync(irPath, validIr);
task.ir_path = 'missing.ir.json';
writeBakeTask(taskPath, task);
const failure = run();
assert.notEqual(failure.child.status, 0);
assert.equal(failure.result.ok, false);
assert.equal(failure.result.diagnostics[0].code, 'ir_invalid');
assert.deepEqual(fs.readFileSync(path.join(output, 'result.scn')), saved);
console.log(JSON.stringify({output, inventory: success.result.inventory, skeleton: success.result.skeleton_compile, checks: ['real_model_roundtrip', 'fresh_process_reload', 'rest_and_socket_transforms', 'visibility_clip_switch', 'animated_socket_follow', 'missing_bone_preserves_scene', 'missing_ir_preserves_scene']}, null, 2));
