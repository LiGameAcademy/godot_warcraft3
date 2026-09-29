import { layerPolicy, definitionRoots } from './definition-layers.js';
import fs from 'node:fs';
import path from 'node:path';
import { inventory, hash, modelKey } from './asset-audit.js';
import { parseModel } from './convert-mdx.js';
import { REPLACEABLE_DEFAULTS } from './mdx-materials.js';
import { collectDevelopmentReferences } from './development-references.js';

export function assessCompilation(asset, results) {
  if (!asset.available || asset.diagnostics.some(row => row.code === 'source_parse_failed')) return {technical: asset.available ? 'source_invalid' : 'source_missing', support: 'unknown', visual: 'unverified', game: 'unverified'};
  const evidence = results.filter(row => row.asset_id === modelKey(asset.logical_path));
  if (!evidence.length) return {technical: 'uncompiled', support: 'unknown', visual: 'unverified', game: 'unverified'};
  const matching = evidence.filter(row => row.source_sha256 === asset.source_sha256);
  if (!matching.length) return {technical: 'stale_or_unverifiable', support: 'unknown', visual: 'unverified', game: 'unverified'};
  // Ambiguous competing evidence must not select a passing run accidentally.
  if (matching.length !== 1) return {technical: 'ambiguous_evidence', support: 'unknown', visual: 'unverified', game: 'unverified'};
  const result = matching[0];
  const diagnostics = result.diagnostics ?? [];
  let validOutput = false;
  try {
    validOutput = !!(result.ok && result.output_sha256 && fs.statSync(result.output_scene).isFile()
      && hash(fs.readFileSync(result.output_scene)) === result.output_sha256);
  } catch { /* Missing/unreadable outputs cannot serve as passing evidence. */ }
  return {
    technical: !result.ok ? 'failed' : validOutput ? 'compiled_partial' : 'stale_or_unverifiable',
    support: validOutput ? 'partial' : 'unknown',
    fallback: diagnostics.some(row => /pending|fallback|missing/.test(row.code ?? '')),
    visual: 'unverified', game: 'unverified', deliverable: false,
    compiler_version: 'unchecked', dependency_versions: 'unchecked', diagnostics, evidence: result.evidence_path,
    components: Object.fromEntries(Object.entries(result).filter(([key]) => key.endsWith('_compile'))),
    output_scene: result.output_scene,
  };
}

export function buildDevelopmentManifest(options) {
  if (!fs.existsSync(options.source)) throw new Error(`Source directory does not exist: ${options.source}`);
  const collected = collectDevelopmentReferences(options);
  const index = new Map(inventory(options.source).map(file => [file.toLowerCase(), file]));
  const records = new Map();
  const queue = [...collected.refs];
  const results = (options.results ?? []).map(file => {
    const result = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (result.result_version !== 1 || typeof result.asset_id !== 'string' || typeof result.ok !== 'boolean' || !Array.isArray(result.diagnostics)) throw new Error(`Invalid worker result: ${file}`);
    return {...result, evidence_path: path.resolve(file)};
  });
  function resolve(logical) {
    const clean = String(logical).replaceAll('\\', '/');
    if (clean.startsWith('/') || /^[A-Za-z]:/.test(clean) || clean.split('/').includes('..')) return '';
    const candidates = /\.(mdx|mdl)$/i.test(clean) ? [clean.replace(/\.(mdx|mdl)$/i, '.mdx'), clean.replace(/\.(mdx|mdl)$/i, '.mdl')] : [clean];
    return candidates.map(value => index.get(value.toLowerCase())).find(Boolean) ?? '';
  }
  for (let cursor = 0; cursor < queue.length; cursor++) {
    const ref = queue[cursor];
    const reason = {...ref.reason, requested_path: ref.logical, candidates: ref.candidates ?? [ref.logical]};
    const resolved = (ref.candidates ?? [ref.logical]).map(resolve).find(Boolean) ?? '';
    const logical = resolved || ref.logical.replaceAll('\\', '/');
    const id = /\.(mdl|mdx)$/i.test(logical) ? modelKey(logical) : logical.toLowerCase();
    if (records.has(id)) {
      records.get(id).reasons.push(reason);
      continue;
    }
    const row = {id, logical_path: logical, kind: /\.(mdx|mdl)$/i.test(logical) ? 'model' : 'texture', source_path: resolved,
      available: !!resolved, source_sha256: '', reasons: [reason], dependencies: [], diagnostics: []};
    records.set(id, row);
    if (!resolved) { row.diagnostics.push({code: 'source_missing'}); continue; }
    const bytes = fs.readFileSync(path.join(options.source, resolved));
    row.source_sha256 = hash(bytes);
    if (row.kind !== 'model') continue;
    try {
      const model = parseModel(bytes, resolved);
      const dependencies = (model.Textures ?? []).map(texture => texture.Image || REPLACEABLE_DEFAULTS[texture.ReplaceableId]).filter(Boolean);
      for (const emitter of model.ParticleEmitters ?? []) if (emitter.Path) dependencies.push(emitter.Path);
      for (const dependency of [...new Set(dependencies)]) {
        row.dependencies.push(dependency.replaceAll('\\', '/'));
        queue.push({logical: dependency, reason: {model: logical, field: 'source_dependency'}});
      }
      for (const texture of model.Textures ?? []) {
        if (texture.ReplaceableId && !texture.Image && !REPLACEABLE_DEFAULTS[texture.ReplaceableId]) row.diagnostics.push({code: 'replaceable_unresolved', replaceable_id: texture.ReplaceableId});
      }
    } catch (error) { row.diagnostics.push({code: 'source_parse_failed', message: error.message}); }
  }
  const assets = [...records.values()].sort((a,b) => a.id.localeCompare(b.id));
  for (const asset of assets) {
    asset.reasons = [...new Map(asset.reasons.map(reason => [JSON.stringify(reason), reason])).values()];
    asset.assessment = asset.kind === 'model' ? assessCompilation(asset, results) : {technical: asset.available ? 'source_only' : 'source_missing', visual: 'unverified'};
  }
  return {
    schema_version: 1, map: path.resolve(options.map), source_root: path.resolve(options.source),
    configuration: {bootstrap_ids: options.seeds ?? [], definitions: path.resolve(options.definitions), edition: 'tft', definition_profile: options.definitionProfile ?? layerPolicy.default_profile,
      definition_roots: definitionRoots(options.definitionProfile)},
    missing_definitions: collected.missingDefinitions, definition_conflicts: collected.definitionConflicts,
    coverage: {complete: false, scope: 'placed_objects_and_table_candidate_models_textures', gaps: [
      'Runtime object overrides and Func overlay precedence are not yet unified.',
      'Dynamic script spawns, random drop tables and custom map objects require runtime tracing.',
      'Terrain, UI atlases, sound, portraits and all player-color variants are not a complete dependency closure.',
      'Model version candidates currently follow TFT priority; configured edition must be reconciled with runtime.',
    ]},
    inputs: collected.inputs, objects: collected.objects, unresolved_references: collected.unresolved,
    summary: {objects: collected.objects.length, models: assets.filter(row => row.kind === 'model').length,
      textures: assets.filter(row => row.kind === 'texture').length, missing_sources: assets.filter(row => !row.available).length,
      unresolved_references: collected.unresolved.length, missing_definitions: collected.missingDefinitions.length,
      definition_conflicts: collected.definitionConflicts.length},
    assets,
  };
}
