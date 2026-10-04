import fs from 'node:fs';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {safeLogical} from './classic-mpq-source.mjs';
import {parseSlk} from '../../slk-export/src/parse-slk.js';
import {parseMap} from '../../map-parse/src/parse-map.js';
import {collectDevelopmentReferences} from './development-references.js';
import {sha256Bytes} from './model-ir.js';

function write(filename, bytes) {
  fs.mkdirSync(path.dirname(filename), {recursive: true});
  fs.writeFileSync(filename, bytes);
}

function find(reader, candidates) {
  for (const logical of candidates) {
    try { return reader.read(safeLogical(logical)); }
    catch (error) {
      if (!String(error.message).startsWith('source_dependency_missing:')) throw error;
    }
  }
  return null;
}

function candidates(logical) {
  const clean = safeLogical(logical);
  if (/\.(mdl|mdx)$/i.test(clean)) return [clean.replace(/\.(mdl|mdx)$/i, '.mdx'), clean.replace(/\.(mdl|mdx)$/i, '.mdl')];
  if (/\.(png|tga)$/i.test(clean)) return [clean.replace(/\.(png|tga)$/i, '.blp'), clean];
  return [clean];
}

/** Reconstruct runtime tables and map data from the player's source, then resolve
 * placed objects and production/ability/item links against those same tables. */
export function prepareDevelopmentContent({gameDir, outDir, request, reader, onProgress}) {
  const spec = request.development_map;
  if (!spec || spec.slug !== 'echoisles' || !Array.isArray(spec.data_files)
      || !Array.isArray(spec.runtime_references) || !Array.isArray(spec.texture_prefixes)) {
    throw new Error('development_request_invalid');
  }
  const sourceMap = path.join(gameDir, safeLogical(spec.path));
  const relative = path.relative(fs.realpathSync(gameDir), fs.realpathSync(sourceMap));
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('map_outside_installation');
  const workspace = path.join(outDir, 'content', randomUUID());
  const root = path.join(workspace, 'assets');
  const definitions = path.join(root, 'slk-exported');
  const originals = path.join(workspace, 'definitions');
  const diagnostics = [];
  const provenance = [];
  for (const [index, logical] of spec.data_files.entries()) {
    onProgress('读取游戏定义表', index, spec.data_files.length);
    const entry = find(reader, [logical]);
    if (!entry) {
      // Source editions may omit unused metadata and override layers; never hide it.
      diagnostics.push({code: 'definition_source_missing', severity: 'warning', logical_path: logical});
      continue;
    }
    provenance.push({...entry, bytes: undefined, sha256: sha256Bytes(entry.bytes)});
    write(path.join(originals, logical), entry.bytes);
    if (/\.slk$/i.test(logical)) {
      const table = parseSlk(entry.bytes);
      write(path.join(definitions, logical.replace(/\.slk$/i, '.json')), JSON.stringify({
        source: logical, columns: table.columns, rows: table.rows,
        headers: table.headers, recordCount: table.records.length, records: table.records,
      }));
    } else write(path.join(definitions, logical), entry.bytes);
  }
  onProgress('解析开发地图', 0, 1);
  const parsed = parseMap(sourceMap, {outDir: path.join(root, 'map-parsed'), force: true});
  for (const section of ['info', 'terrain', 'units', 'doodads', 'pathing']) {
    if (parsed.errors[section]) throw new Error('map_parse_failed: ' + section + ': ' + parsed.errors[section]);
  }
  if (path.basename(parsed.outDir) !== spec.slug) throw new Error('development_map_identity_mismatch');
  provenance.push({logical_path: spec.path, source_package: 'installation-map', sha256: sha256Bytes(fs.readFileSync(sourceMap))});
  const collected = collectDevelopmentReferences({map: parsed.outDir, definitions, source: originals, seeds: spec.seeds});
  if (collected.missingDefinitions.length) throw new Error('required_definitions_missing: ' + collected.missingDefinitions.join(','));
  const models = new Map();
  const textures = new Map();
  const aliases = [];
  const configuredAliases = new Map((spec.asset_aliases || []).map(row => [safeLogical(row.requested).toLowerCase(), safeLogical(row.selected)]));
  const add = (choices, reason) => {
    const entry = find(reader, [...new Set(choices.flatMap(logical => candidates(configuredAliases.get(logical.toLowerCase()) || logical)))]);
    if (!entry) {
      diagnostics.push({code: 'reference_source_missing', severity: 'warning', candidates: choices, reason});
      return;
    }
    const target = /\.(mdx|mdl)$/i.test(entry.logical_path) ? models : textures;
    target.set(entry.logical_path.toLowerCase(), entry.logical_path);
    if (entry.logical_path.toLowerCase() !== choices[0].replace(/\.mdl$/i, '.mdx').toLowerCase()) {
      aliases.push({requested: choices[0], selected: entry.logical_path, reason});
    }
  };
  for (const ref of collected.refs) add(ref.candidates || [ref.logical], ref.reason);
  for (const logical of spec.runtime_references) add([logical], {kind: 'runtime_literal'});
  const terrain = JSON.parse(fs.readFileSync(path.join(parsed.outDir, 'terrain.json')));
  const cliffTable = JSON.parse(fs.readFileSync(path.join(definitions, 'TerrainArt/CliffTypes.json')));
  const cliffDirs = new Set(cliffTable.records.filter(row => terrain.cliffTilesets.includes(row.cliffID))
    .flatMap(row => [row.cliffModelDir, row.rampModelDir]).filter(Boolean));
  const prefixes = spec.texture_prefixes.map(prefix => safeLogical(prefix.replace(/\/$/, '')) + '/');
  // Listfiles supplement exact definition probes; they are not the sole authority.
  for (const logical of reader.list()) {
    if (/\.(blp|tga|dds)$/i.test(logical) && prefixes.some(prefix => logical.toLowerCase().startsWith(prefix.toLowerCase()))) {
      textures.set(logical.toLowerCase(), logical);
    }
    if (/\.(mdx|mdl)$/i.test(logical) && [...cliffDirs].some(dir => logical.toLowerCase().startsWith(`doodads/terrain/${dir}/`.toLowerCase()))) {
      models.set(logical.toLowerCase(), logical);
    }
  }
  for (const logical of [...models.values()]) {
    // Portraits are optional in WC3; absent portraits intentionally use the body.
    const entry = find(reader, [logical.replace(/\.(mdx|mdl)$/i, '_Portrait.mdx')]);
    if (entry) models.set(entry.logical_path.toLowerCase(), entry.logical_path);
  }
  const coverage = {
    map: spec.path, objects: collected.objects.length, models: models.size, textures: textures.size,
    unresolved_references: collected.unresolved, diagnostics, aliases,
    scope: 'echoisles-placed-objects-human-production-abilities-items-runtime-literals-terrain-ui',
    visual: 'unverified', complete: collected.unresolved.length === 0 && diagnostics.every(row => row.code !== 'reference_source_missing'),
  };
  write(path.join(root, 'coverage.json'), JSON.stringify(coverage, null, 2));
  return {root, models: [...models.values()], textures: [...textures.values()], provenance, coverage,
    signature: sha256Bytes(Buffer.from(JSON.stringify({provenance, request: spec})))};
}

export function finalizeDevelopmentContent(content, converted) {
  fs.cpSync(converted, path.join(content.root, 'asset-converted'), {recursive: true});
  for (const alias of content.coverage.aliases) {
    if (!/\.(blp|tga|png)$/i.test(alias.requested)) continue;
    const selected = path.join(content.root, 'asset-converted', alias.selected.replace(/\.(blp|tga)$/i, '.png'));
    const requested = path.join(content.root, 'asset-converted', alias.requested.replace(/\.(blp|tga)$/i, '.png'));
    if (selected !== requested && fs.existsSync(selected)) write(requested, fs.readFileSync(selected));
  }
  const files = fs.readdirSync(content.root, {recursive: true})
    .filter(relative => fs.statSync(path.join(content.root, relative)).isFile()).sort()
    .map(relative => ({path: relative.replaceAll('\\', '/'), sha256: sha256Bytes(fs.readFileSync(path.join(content.root, relative)))}));
  return {root: content.root, files, coverage: content.coverage};
}
