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
for (const name of ['import_material_animation.gd', 'import_team_material.gd', 'import_geoset_visibility.gd', 'import_geoset_curves.gd']) {
  fs.copyFileSync(path.join(repo, 'tools/godot', name), path.join(output, name));
}
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
assert.doesNotMatch(success.child.stdout + success.child.stderr, /ERROR:/);
assert.equal(success.result.ok, true, JSON.stringify(success.result));
assert.equal(success.result.deliverable, false);
assert.ok(success.result.inventory.meshes > 0);
assert.ok(success.result.inventory.bones > 0);
assert.ok(success.result.inventory.animations > 0);
assert.equal(success.result.skeleton_compile.rests, 40);
assert.equal(success.result.skeleton_compile.sockets, 9);
assert.equal(success.result.skeleton_compile.visibility_tracks, 91);
assert.ok(success.result.material_compile.compiled_surfaces > 0);
assert.equal(success.result.material_compile.team_surfaces, 1);
assert.equal(success.result.material_compile.alpha_tracks, 13);
assert.deepEqual(success.result.material_compile.diagnostics, []);
assert.equal(success.result.geoset_compile.visibility_tracks, 65);
assert.deepEqual(success.result.geoset_compile.diagnostics, []);
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
 var team_material: ShaderMaterial
 var team_mesh: MeshInstance3D
 var animated_material: StandardMaterial3D
 var geosets: Dictionary = {}
 while not queue.is_empty():
  var node: Node = queue.pop_back()
  counts.nodes += 1
  if node is MeshInstance3D and node.mesh != null:
   geosets[str(node.name)] = node
   counts.meshes += 1
   counts.surfaces += node.mesh.get_surface_count()
   for surface: int in range(node.mesh.get_surface_count()):
    var material: Material = node.get_active_material(surface)
    if material is ShaderMaterial and material.has_meta("import_team_underlay"):
     team_material = material
     team_mesh = node
     if material.get_shader_parameter("team_color_tex") == null or material.get_shader_parameter("diffuse_tex") == null:
      push_error("Team textures lost after reload")
      quit(1)
      return
    if material is StandardMaterial3D and material.has_meta("import_material_id"):
     isolated_material = material
     if int(material.get_meta("import_material_id")) == 2:
      animated_material = material
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
 var alpha_compiler: GDScript = load("res://import_material_animation.gd")
 var alpha: Dictionary = {"Keys": [{"Frame": 167, "Vector": [0.2]}, {"Frame": 1667, "Vector": [0.8]}], "LineType": 1, "GlobalSeqId": null}
 if not alpha_compiler.supported(player, alpha, ir):
  quit(1)
  return
 alpha.GlobalSeqId = 0
 if alpha_compiler.supported(player, alpha, ir):
  push_error("Global material tracks must retain diagnostics")
  quit(1)
  return
 alpha.GlobalSeqId = null
 alpha.LineType = 2
 if alpha_compiler.supported(player, alpha, ir):
  push_error("Hermite material tracks must retain diagnostics")
  quit(1)
  return
 alpha.LineType = 1
 alpha_compiler.compile(player, team_mesh, 0, alpha, ir, true)
 player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 for sample: Array in [["Stand-1", 0.0, [true,true,false,false,false]], ["Death", 1.0, [true,true,false,false,false]], ["DecayFlesh", 0.1, [true,true,true,false,false]], ["DecayFlesh", 0.2, [true,true,true,false,true]], ["DecayBone", 0.1, [false,false,false,false,true]], ["Stand-4", 2.0, [true,true,true,true,false]], ["Stand-1", 0.0, [true,true,false,false,false]]]:
  player.play(sample[0])
  player.seek(sample[1], true)
  for index: int in range(5):
   if geosets["Geoset_%d" % index].visible != sample[2][index]:
    push_error("Geoset visibility mismatch: %s mesh %d" % [sample[0], index])
    quit(1)
    return
 if animated_material == null or team_material == null:
  push_error("Missing team or animated material")
  quit(1)
  return
 for sample: Array in [["Stand-1", 0.75, 0.5], ["Attack-1", 0.0, 1.0]]:
  player.play(sample[0])
  player.seek(sample[1], true)
  if absf(float(team_material.get_shader_parameter("layer_alpha")) - sample[2]) > 0.001:
   push_error("Team layer alpha playback mismatch")
   quit(1)
   return
 for sample: Array in [["DecayBone", 59.1665, 0.875], ["Stand-1", 0.0, 1.0]]:
  player.play(sample[0])
  player.seek(sample[1], true)
  if absf(animated_material.albedo_color.a - sample[2]) > 0.001:
   push_error("Material alpha playback mismatch: %s" % animated_material.albedo_color.a)
   quit(1)
   return
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
 team_material.set_shader_parameter("layer_alpha", 0.123)
 for check: int in range(2):
  var other: Node = packed.instantiate()
  root.add_child(other)
  await process_frame
  await process_frame
  var other_nodes: Array[Node] = [other]
  while not other_nodes.is_empty():
   var node: Node = other_nodes.pop_back()
   if node is MeshInstance3D and node.mesh != null:
    for surface: int in range(node.mesh.get_surface_count()):
     var material: Material = node.get_active_material(surface)
     if material is ShaderMaterial and material.has_meta("import_team_underlay") and (material == team_material or is_equal_approx(float(material.get_shader_parameter("layer_alpha")), 0.123)):
      push_error("Team material mutation leaked across instances")
      quit(1)
      return
     if material is StandardMaterial3D and material.has_meta("import_material_id") and (material == isolated_material or material.albedo_color == Color.MAGENTA):
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
// Use a real renderer for shader resource lifecycle checks as well as reload.
const verify = spawnSync(godot, ['--minimized', '--resolution', '64x64', '--path', output, '--log-file', path.join(output, 'verify.log'), '-s', 'res://verify.gd'], {encoding: 'utf8', windowsHide: true, timeout: 120000});
assert.ifError(verify.error);
assert.equal(verify.status, 0, verify.stdout + verify.stderr);
assert.doesNotMatch(verify.stdout + verify.stderr, /ERROR:/);
assert.deepEqual(JSON.parse(fs.readFileSync(path.join(output, 'verified.json'), 'utf8')), success.result.inventory);
fs.copyFileSync(path.join(repo, 'tests/integration/selftest_geoset_curves.gd'), path.join(output, 'curve-check.gd'));
const curves = spawnSync(godot, ['--minimized', '--resolution', '128x128', '--path', output, '--log-file', path.join(output, 'curves.log'), '-s', 'res://curve-check.gd'], {encoding: 'utf8', windowsHide: true, timeout: 120000});
assert.ifError(curves.error);
assert.equal(curves.status, 0, curves.stdout + curves.stderr);
assert.doesNotMatch(curves.stdout + curves.stderr, /ERROR:/);
assert.match(curves.stdout, /PASS: continuous Geoset/);
// Invalid IR must fail before touching the previously generated scene.
const saved = fs.readFileSync(path.join(output, 'result.scn'));
const irPath = path.join(output, `${stem}.ir.json`);
const validIr = fs.readFileSync(irPath);
// Continuous/global alpha must not silently become thresholded visibility.
const unsupportedIr = JSON.parse(validIr);
unsupportedIr.animations.payload.geoset_anims[0].alpha.line_type = 1;
unsupportedIr.animations.payload.geoset_anims[1].alpha.global_seq_id = 0;
unsupportedIr.animations.payload.geoset_anims[2].alpha.keys[0].vector[0] = 0.5;
fs.writeFileSync(irPath, JSON.stringify(unsupportedIr));
task.output_scene = 'unsupported.scn';
writeBakeTask(taskPath, task);
const unsupported = run();
assert.equal(unsupported.child.status, 0, unsupported.child.stdout + unsupported.child.stderr);
assert.equal(unsupported.result.geoset_compile.diagnostics.filter(d => d.code === 'geoset_alpha_pending').length, 3);
assert.equal(unsupported.result.geoset_compile.visibility_tracks, 26);
assert.deepEqual(fs.readFileSync(path.join(output, 'result.scn')), saved);
task.output_scene = 'result.scn';
writeBakeTask(taskPath, task);
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
console.log(JSON.stringify({output, inventory: success.result.inventory, skeleton: success.result.skeleton_compile, materials: success.result.material_compile, geosets: success.result.geoset_compile, checks: ['real_model_roundtrip', 'fresh_process_reload', 'rest_and_socket_transforms', 'visibility_clip_switch', 'animated_socket_follow', 'team_textures_embedded', 'material_alpha_clip_switch', 'material_instance_isolation', 'geoset_clip_switch', 'unsupported_geoset_diagnostics', 'missing_bone_preserves_scene', 'missing_ir_preserves_scene']}, null, 2));
