import fs from 'node:fs';
import path from 'node:path';

// Isolated compiler projects include the shared, dependency-free particle shader
// builder. The resulting PackedScene embeds its Shader/Texture resources.
export function prepareWorkerProject(repo, output) {
  for (const name of fs.readdirSync(path.join(repo, 'tools/godot')).filter(n => /^import_.*\.gd$/.test(n))) {
    fs.copyFileSync(path.join(repo, 'tools/godot', name), path.join(output, name));
  }
  const relative = 'presentation/wc3_model/wc3_pe2_material.gd';
  const target = path.join(output, 'addons/rts_map', relative);
  fs.mkdirSync(path.dirname(target), {recursive:true});
  fs.copyFileSync(path.join(repo, 'packages/map', relative), target);
}
