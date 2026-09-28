import fs from 'node:fs';
import path from 'node:path';
import { inventory, hash } from './asset-audit.js';

const TABLES = {
  'Units/UnitUI.json': 'unitUIID', 'Units/UnitAbilities.json': 'unitAbilID',
  'Units/UnitWeapons.json': 'unitWeapID', 'Units/ItemData.json': 'itemID',
  'Units/AbilityData.json': 'alias', 'Units/DestructableData.json': 'DestructableID',
  'Doodads/Doodads.json': 'doodID',
};
const clean = value => String(value ?? '').trim().replaceAll('\\', '/').replace(/^"|"$/g, '');
const split = value => clean(value).split(',').map(s => s.trim()).filter(Boolean);
const LINKS = /^(Builds|Trains|Upgrade|Sellunits|Sellitems|abilList|heroAbilList|auto|BuffID\d*|EfctID\d*|Data[A-I]\d*)$/i;

/** Conservative reference graph. Base Func tables are used; overlays stay an
 * explicit coverage gap until runtime precedence is centralized. */
export function collectDevelopmentReferences({map, definitions, seeds = []}) {
  const inputs = [];
  const entities = new Map();
  const refs = [];
  const unresolved = [];
  function read(root, logical) {
    const file = path.join(root, logical);
    const bytes = fs.readFileSync(file);
    inputs.push({path: path.resolve(file), sha256: hash(bytes)});
    return bytes.toString('utf8').replace(/^\uFEFF/, '');
  }
  function add(id, fields, source) {
    if (!entities.has(id)) entities.set(id, []);
    entities.get(id).push({fields, source});
  }
  for (const [file, key] of Object.entries(TABLES)) {
    for (const row of JSON.parse(read(definitions, file)).records ?? []) {
      if (row[key]) add(String(row[key]), row, file);
    }
  }
  for (const file of inventory(path.join(definitions, 'Units')).filter(f => /Func\.txt$/i.test(f))) {
    let id = '';
    let fields = {};
    const source = `Units/${file}`;
    const flush = () => { if (id) add(id, fields, source); };
    for (const raw of read(definitions, source).split(/\r?\n/)) {
      const line = raw.trim();
      const section = line.match(/^\[([^\]]+)\]$/);
      if (section) { flush(); id = section[1]; fields = {}; }
      else {
        const pair = line.match(/^([^=]+)=(.*)$/);
        if (pair && id) fields[pair[1].trim()] = pair[2].trim();
      }
    }
    flush();
  }
  const queue = [];
  const visited = new Set();
  const objectReasons = new Map();
  const variations = new Map();
  function enqueue(id, reason) {
    if (!objectReasons.has(id)) objectReasons.set(id, new Set());
    objectReasons.get(id).add(reason);
    if (!visited.has(id)) { visited.add(id); queue.push(id); }
  }
  const units = JSON.parse(read(map, 'units.json'));
  const doodads = JSON.parse(read(map, 'doodads.json'));
  for (const unit of units.units ?? []) enqueue(unit.typeId, 'map:units.json');
  for (const doodad of [...(doodads.doodads ?? []), ...(doodads.specialDoodads ?? [])]) {
    enqueue(doodad.id, 'map:doodads.json');
    if (!variations.has(doodad.id)) variations.set(doodad.id, new Set());
    variations.get(doodad.id).add(Number(doodad.variation ?? 0));
  }
  // Inventory and fixed drop entries carry explicit item IDs; random item tables
  // require game-table interpretation and are intentionally not guessed here.
  function nested(value, source) {
    if (Array.isArray(value)) { for (const child of value) nested(child, source); return; }
    if (!value || typeof value !== 'object') return;
    for (const [key, child] of Object.entries(value)) {
      if (['itemId', 'itemID', 'abilityId', 'abilityID'].includes(key) && typeof child === 'string') enqueue(child, source);
      else if (child && typeof child === 'object') nested(child, source);
    }
  }
  nested(units, 'map:inventory/ability/drop');
  nested(doodads, 'map:drop');
  for (const id of seeds) enqueue(id, 'configured:development-bootstrap');
  for (let index = 0; index < queue.length; index++) {
    const id = queue[index];
    const records = entities.get(id);
    if (!records) {
      if (id !== 'sloc') unresolved.push({kind: 'object', id, reasons: [...objectReasons.get(id)]});
      continue;
    }
    for (const {fields, source} of records) {
      for (const [field, value] of Object.entries(fields)) {
        if (typeof value !== 'string') continue;
        if (LINKS.test(field)) {
          for (const target of split(value)) {
            if (/^[A-Za-z0-9]{4}$/.test(target)) {
              if (entities.has(target)) enqueue(target, `${id}:${source}:${field}`);
              else if (!/^Data/i.test(field)) unresolved.push({kind: 'object_link', id, field, target, source});
            }
          }
        }
        for (let logical of split(value)) {
          if (field.toLowerCase() === 'file' && logical.includes('/') && !/\.[^/]+$/.test(logical)) logical += '.mdx';
          if (!/\.(mdx|mdl|blp|tga|dds)$/i.test(logical)) continue;
          const reason = {object_id: id, table: source, field};
          if (field === 'file' && /Doodads|DestructableData/.test(source) && Number(fields.numVar) > 1) {
            for (const variation of variations.get(id) ?? [0]) refs.push({logical: logical.replace(/\.(mdx|mdl)$/i, `${variation}.mdx`), reason: {...reason, variation}});
          } else {
            const candidates = /\.(mdx|mdl)$/i.test(logical) && Number(fields.fileVerFlags) > 0
              ? [logical.replace(/\.(mdx|mdl)$/i, '_V1.mdx'), logical] : [logical];
            refs.push({logical, candidates, reason});
          }
        }
      }
    }
  }
  return {refs, inputs, unresolved, objects: [...objectReasons].map(([id, reasons]) => ({id, reasons: [...reasons].sort()})).sort((a,b) => a.id.localeCompare(b.id))};
}
