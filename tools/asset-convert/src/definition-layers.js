import fs from 'node:fs';

export const policyPath = new URL('../../../packages/content/definitions/layer_policy.json', import.meta.url);
export const layerPolicy = JSON.parse(fs.readFileSync(policyPath, 'utf8'));

export function definitionRoots(profile = layerPolicy.default_profile) {
  if (profile === 'candidates') return [...layerPolicy.audit_roots];
  if (!Object.hasOwn(layerPolicy.profiles, profile)) throw new Error(`Unknown definition profile: ${profile}`);
  return [...layerPolicy.profiles[profile]];
}

export function mergeDefinitionLayers(layers) {
  const rows = {}, origins = {}, changes = [];
  for (const {source, text} of layers) {
    let id = '';
    for (const raw of text.replace(/^\uFEFF/, '').split(/\r?\n/)) {
      const line = raw.trim();
      if (!line || line.startsWith('//') || line.startsWith(';')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        id = line.slice(1, -1).trim();
        if (id && !Object.hasOwn(rows, id)) {
          Object.defineProperty(rows, id, {value: {}, enumerable: true});
          Object.defineProperty(origins, id, {value: {}, enumerable: true});
        }
        continue;
      }
      const eq = line.indexOf('=');
      if (!id || eq <= 0) continue;
      const field = line.slice(0, eq).trim().toLowerCase();
      let value = line.slice(eq + 1).trim();
      if (!value.includes('\",\"') && value.length >= 2 && value.startsWith('"') && value.endsWith('"')) value = value.slice(1, -1);
      if (Object.hasOwn(rows[id], field) && rows[id][field] !== value) {
        changes.push({object_id: id, field, previous: {source: origins[id][field], value: rows[id][field]}, candidate: {source, value}});
      }
      Object.defineProperty(rows[id], field, {value, enumerable: true, configurable: true});
      Object.defineProperty(origins[id], field, {value: source, enumerable: true, configurable: true});
    }
  }
  return {rows, origins, changes};
}
