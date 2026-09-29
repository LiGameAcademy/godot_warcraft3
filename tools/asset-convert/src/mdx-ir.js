import fs from "node:fs";
import path from "node:path";
import { mdxLogicalToAnimKeys, mdxLogicalToAttachments, mdxLogicalToBoneRest, mdxLogicalToModelIr, mdxLogicalToGeosetVis, mdxLogicalToGltf, mdxLogicalToPe2 } from "./paths.js";
import { createModelIr, sha256Bytes, writeModelIr } from "./model-ir.js";
import { resolveTexturePng } from "./mdx-materials.js";
import { billboardPayload, particlePayload } from './mdx-fx-ir.js';
import { ribbonPayload } from './mdx-ribbon-ir.js';



/**
 * Write the first unified Model IR sidecar without changing the legacy GLTF
 * and individual sidecars. This is intentionally a loss-reporting envelope;
 * later compiler stages will tighten feature payloads from these sources.
 * @param {object} model
 * @param {string} logicalPath
 * @param {Buffer} sourceBytes
 * @param {string} outDir
 * @param {string} inDir
 */
export function writeModelIrSidecar(model, logicalPath, sourceBytes, outDir, inDir) {
  const irLogical = mdxLogicalToModelIr(logicalPath);
  const destination = path.join(outDir, ...irLogical.split("/"));
  const gltf = mdxLogicalToGltf(logicalPath);
  const pe2 = mdxLogicalToPe2(logicalPath);
  const attachments = mdxLogicalToAttachments(logicalPath);
  const animkeys = mdxLogicalToAnimKeys(logicalPath);
  const geosetvis = mdxLogicalToGeosetVis(logicalPath);
  const boneRest = mdxLogicalToBoneRest(logicalPath);
  const ribbons = pe2.replace(/\.pe2\.json$/i, ".ribbon.json");
  const nodes = Array.isArray(model.Nodes) ? model.Nodes : Object.values(model.Nodes ?? {});
  const replaceableIds = [...new Set(
    (model.Textures ?? []).map((texture) => Number(texture.ReplaceableId ?? 0)).filter((id) => id > 0),
  )];
  const resolvedTextures = (model.Textures ?? []).map((texture) => {
    const resolved = resolveTexturePng(texture.Image, inDir, outDir, {
      isReplaceable: !!texture.ReplaceableId, replaceableId: texture.ReplaceableId || 0,
    });
    return { ...texture, uri: path.relative(path.dirname(destination), path.join(outDir, resolved.pngLogical)).replaceAll("\\", "/") };
  });
  const ir = createModelIr({
    asset_id: logicalPath.replace(/\.(mdx|mdl)$/i, "").toLowerCase(),
    logical_path: logicalPath,
    source_format: path.extname(logicalPath).slice(1).toLowerCase(),
    source_path: logicalPath,
    source_hash: sha256Bytes(sourceBytes),
    geometry: {
      gltf,
      node_count: nodes.length,
      geoset_count: (model.Geosets ?? []).length,
      vertex_count: (model.Geosets ?? []).reduce((total, geoset) => total + (geoset?.Vertices?.length ?? 0) / 3, 0),
    },
    skeleton: {
      bone_count: (model.Bones ?? []).length,
      helper_count: (model.Helpers ?? []).length,
      bone_rest: boneRest,
      rest_payload: JSON.parse(fs.readFileSync(path.join(outDir, boneRest), "utf8")),
      billboards: billboardPayload(model),
    },
    animations: {
      sequence_count: (model.Sequences ?? []).length,
      animkeys,
      payload: JSON.parse(fs.readFileSync(path.join(outDir, animkeys), "utf8")),
    },
    materials: {
      material_count: (model.Materials ?? []).length,
      replaceable_ids: replaceableIds,
      source_payload: JSON.parse(JSON.stringify(model.Materials ?? [], (_key, value) => ArrayBuffer.isView(value) ? Array.from(value) : value)),
      geoset_bindings: (model.Geosets ?? []).map((geoset, index) => ({node: `Geoset_${index}`, material_id: geoset.MaterialID})),
    },
    textures: { texture_count: resolvedTextures.length, source_payload: resolvedTextures },
    geoset_visibility: { sidecar: geosetvis },
    texture_animations: {
      retained_in_gltf: false,
      status: "diagnostic",
    },
    particles: {
      count: (model.ParticleEmitters2 ?? []).length,
      sidecar: pe2,
      payload: particlePayload(model, JSON.parse(fs.readFileSync(path.join(outDir, pe2), 'utf8')), resolvedTextures),
    },
    ribbons: {
      count: (model.RibbonEmitters ?? []).length,
      sidecar: ribbons,
      payload: ribbonPayload(model, resolvedTextures),
    },
    attachments: {
      count: (model.Attachments ?? []).length,
      sidecar: attachments,
      payload: JSON.parse(fs.readFileSync(path.join(outDir, attachments), "utf8")),
    },
    events: {
      count: (model.EventObjects ?? []).length,
      animkeys,
    },
    dependencies: [gltf, pe2, ribbons, geosetvis, attachments, animkeys, boneRest,
      ...resolvedTextures.map(texture => path.posix.normalize(path.posix.join(path.posix.dirname(irLogical), texture.uri)))],
    diagnostics: resolvedTextures.filter(texture => texture.uri.includes('_placeholders/')).map(texture => ({
      code: 'texture_placeholder', severity: 'warning', message: `Texture fallback: ${texture.Image || texture.ReplaceableId}`,
    })),
    feature_status: {
      geometry: "exported",
      skeleton: "exported",
      animations: "exported",
      materials: "approximated",
      texture_animations: "fallback",
      geoset_visibility: "exported",
      particles: (model.ParticleEmitters2 ?? []).length ? "exported" : "parsed",
      ribbons: (model.RibbonEmitters ?? []).length ? "exported" : "parsed",
      attachments: "exported",
      events: (model.EventObjects ?? []).length ? "exported" : "parsed",
    },
  });
  writeModelIr(destination, ir);
  return destination;
}
