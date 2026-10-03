import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {blpLogicalToPng} from './paths.js';
import {blpBufferToPng} from './convert-blp.js';
import {ClassicMpqSource, safeLogical} from './classic-mpq-source.mjs';
import {parseModel, convertOneMdx} from './convert-mdx.js';
import {REPLACEABLE_DEFAULTS} from './mdx-materials.js';
import {sha256Bytes, writeModelIr} from './model-ir.js';
import {createBakeTask, writeBakeTask} from './bake-task.js';
import {beginSession} from '../../pipeline-log.mjs';

export function validateRequest(request) {
  if (request?.request_version !== 1 || !Array.isArray(request.models) || !request.models.length) {
    throw new Error('source_request_invalid');
  }
  const models = request.models.map(safeLogical);
  if (models.some(model => !/\.(mdx|mdl)$/i.test(model))
      || new Set(models.map(model => model.replace(/\.(mdx|mdl)$/i, '').toLowerCase())).size !== models.length) {
    throw new Error('source_request_invalid: duplicate identity or unsupported model format');
  }
  return models;
}

/** Source bytes stay outside the release package; only the task manifest is published last. */
export async function prepareSourceImport({gameDir, request, outDir, bundleSignature = '', source}) {
  const models = validateRequest(request);
  if (gameDir) {
    const relative = path.relative(path.resolve(gameDir), path.resolve(outDir));
    if (!relative || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative))) {
      throw new Error('source_output_inside_installation');
    }
  }
  const reader = source || new ClassicMpqSource(gameDir);
  const entries = new Map();
  const remember = logical => {
    const key = logical.toLowerCase();
    if (!entries.has(key)) entries.set(key, reader.read(logical));
    return entries.get(key);
  };
  try {
    for (const logical of models) {
      const entry = remember(logical);
      const model = parseModel(entry.bytes, logical);
      for (const texture of model.Textures || []) {
        const dependency = texture.Image || REPLACEABLE_DEFAULTS[texture.ReplaceableId];
        if (!dependency) throw new Error('texture_identity_missing: ' + logical);
        remember(safeLogical(dependency));
      }
    }
  } finally { if (!source) reader.close(); }
  const provenance = [...entries.values()].map(({bytes, ...entry}) => ({...entry, sha256: sha256Bytes(bytes)}));
  const signature = sha256Bytes(Buffer.from(JSON.stringify({models, provenance, bundleSignature})));
  const generation = path.join(outDir, 'inputs', signature);
  const raw = path.join(generation, 'raw');
  const converted = path.join(generation, 'converted');
  fs.mkdirSync(converted, {recursive: true});
  const log = beginSession('runtime-source-import', {logPath: path.join(outDir, 'adapter.log.md')});
  for (const entry of entries.values()) {
    const filename = path.join(raw, entry.logical_path);
    fs.mkdirSync(path.dirname(filename), {recursive: true});
    fs.writeFileSync(filename, entry.bytes);
    // Regenerate derived textures from original bytes: retries repair corrupted PNGs.
    if (/\.blp$/i.test(entry.logical_path)) {
      const pngPath = path.join(converted, blpLogicalToPng(entry.logical_path));
      fs.mkdirSync(path.dirname(pngPath), {recursive: true});
      fs.writeFileSync(pngPath, blpBufferToPng(entry.bytes));
    }
  }
  const tasks = [];
  for (const logical of models) {
    await convertOneMdx(path.join(raw, logical), logical, raw, converted);
    const stem = logical.replace(/\.(mdx|mdl)$/i, '');
    const irPath = path.join(converted, stem + '.ir.json');
    const ir = JSON.parse(fs.readFileSync(irPath));
    const entry = entries.get(logical.toLowerCase());
    Object.assign(ir.source, {source_package: entry.source_package, overlay_priority: entry.overlay_priority});
    writeModelIr(irPath, ir);
    const task = createBakeTask({asset_id: stem.toLowerCase(), ir_path: irPath,
      geometry_path: path.join(converted, stem + '.gltf'),
      output_scene: path.join(outDir, 'scenes', stem + '.scn'),
      rules_version: 'runtime-source-v1:' + bundleSignature,
      dependencies: [...entries.values()].map(item => path.join(raw, item.logical_path))});
    task.source_path = path.join(raw, logical);
    const taskPath = path.join(generation, stem + '.task.json');
    writeBakeTask(taskPath, task);
    tasks.push(taskPath);
  }
  const manifestPath = path.join(generation, 'manifest.json');
  const manifest = {manifest_version: 1, tasks, source_signature: signature, provenance};
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
  log.endSession({models: models.length, dependencies: provenance.length});
  return {ok: true, manifest_path: manifestPath, source_signature: signature, provenance};
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [gameDir, requestPath, outDir, resultPath] = process.argv.slice(2);
  if (!gameDir || !requestPath || !outDir || !resultPath) throw new Error('Expected game-dir request output result');
  fs.mkdirSync(path.dirname(resultPath), {recursive: true});
  try {
    const bundlePath = fileURLToPath(new URL('../../../runtime-bundle.json', import.meta.url));
    const bundleSignature = fs.existsSync(bundlePath) ? sha256Bytes(fs.readFileSync(bundlePath)) : '';
    const result = await prepareSourceImport({gameDir, request: JSON.parse(fs.readFileSync(requestPath)), outDir, bundleSignature});
    fs.writeFileSync(resultPath, JSON.stringify(result, null, 2));
  } catch (error) {
    fs.writeFileSync(resultPath, JSON.stringify({ok: false, diagnostics: [{code: 'source_import_failed',
      severity: 'error', message: error instanceof Error ? error.message : String(error)}]}, null, 2));
    process.exitCode = 1;
  }
}
