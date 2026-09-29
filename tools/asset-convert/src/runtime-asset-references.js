import fs from 'node:fs';
import path from 'node:path';
import { inventory, hash } from './asset-audit.js';

/** Conservative literals, not execution tracing. Ignore comments and report
 * interpolated paths separately instead of treating them as existing assets. */
export function collectRuntimeAssetReferences(roots = []) {
  const refs = [], inputs = [], dynamic = [];
  for (const root of roots) {
    if (!fs.existsSync(root)) throw new Error(`Runtime script root does not exist: ${root}`);
    for (const logical of inventory(root).filter(file => file.endsWith('.gd'))) {
      const file = path.resolve(root, logical);
      const bytes = fs.readFileSync(file);
      inputs.push({path: file, sha256: hash(bytes)});
      const lines = bytes.toString('utf8').split(/\r?\n/);
      // Tokenize quotes and comments together; # inside a quoted string is not a comment.
      for (const [index, line] of lines.entries()) {
        for (const match of line.matchAll(/#[^\r\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g)) {
          if (match[0].startsWith('#')) break;
          const value = match[0].slice(1, -1).replaceAll('\\\\', '/').replaceAll('\\', '/');
          if (!/^(Abilities|Units|Buildings|Doodads|Objects|UI\/Feedback|ReplaceableTextures)\//i.test(value)) continue;
          if (!/\.(mdx|mdl|gltf|glb|scn|blp|tga|dds)$/i.test(value)) continue;
          const reason = {script: file, line: index + 1, runtime_path: value, kind: 'runtime_literal_candidate'};
          if (/[%{}]/.test(value)) { dynamic.push(reason); continue; }
          refs.push({logical: value.replace(/\.(glb|gltf|scn)$/i, '.mdx'), reason});
        }
      }
    }
  }
  return {refs, inputs, dynamic};
}

export function modelVersionCandidates(logical, flags, edition = 'tft') {
  if (!['roc', 'tft'].includes(edition)) throw new Error(`Unsupported model edition: ${edition}`);
  if (edition === 'roc' || !Number(flags) || !/\.(mdl|mdx)$/i.test(logical)) return [logical];
  const stem = logical.replace(/\.(mdl|mdx)$/i, '');
  return stem.endsWith('_V1') ? [logical] : [`${stem}_V1.mdx`, logical];
}
