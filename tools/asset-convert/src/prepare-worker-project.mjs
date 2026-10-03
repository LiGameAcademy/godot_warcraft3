import fs from 'node:fs';
import path from 'node:path';

// Isolated compiler projects include the shared, dependency-free particle shader
// builder. The resulting PackedScene embeds its Shader/Texture resources.
export function prepareWorkerProject(repo, output) {
  for (const name of fs.readdirSync(path.join(repo, 'tools/godot')).filter(n => /^import_.*\.gd$/.test(n))) {
    fs.copyFileSync(path.join(repo, 'tools/godot', name), path.join(output, name));
  }
  // Release script exports may strip source_code. Keep an explicit source payload
  // for scripts embedded into newly compiled SCNs; .gd remains authoritative.
  for (const name of ['import_billboard_pose.gd', 'import_ribbon_runtime.gd']) {
    fs.copyFileSync(path.join(repo, 'tools/godot', name), path.join(output, `${name}.source`));
  }
  const relative = 'presentation/wc3_model/wc3_pe2_material.gd';
  const target = path.join(output, 'packages/map', relative);
  fs.mkdirSync(path.dirname(target), {recursive:true});
  fs.copyFileSync(path.join(repo, 'packages/map', relative), target);
}
