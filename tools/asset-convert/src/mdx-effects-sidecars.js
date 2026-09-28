import path from "node:path";
import { evaluateNodeWorldMatrices } from "./anim.js";
import { wc3ToGltfVec3 } from "./mat4.js";
import { mdxLogicalToCameras, mdxLogicalToCollision, mdxLogicalToPe2, normalizeLogicalPath } from "./paths.js";
import { atomicWriteBytesSync } from "./atomic-write.js";

import { MODEL_SCALE, COLLISION_SHAPE_NAMES, sanitizeMdxText, asVec3, sidecarVec3, numArray, dumpCameraVecTrack, dumpAnimVector } from "./mdx-values.js";
import { animTrackKeys, activeSequencesForEmitter } from "./mdx-particles.js";
import { resolveTexturePng } from "./mdx-materials.js";

/** Ribbon motion is sampled through the full node hierarchy, including helpers. */
export function extractRibbons(model) {
  const sequences = model.Sequences ?? [];
  const nodes = model.Nodes ?? [];
  return (model.RibbonEmitters ?? []).map((ribbon) => {
    const positions = {};
    for (const seq of sequences) {
      const start = Number(seq.Interval[0]);
      const end = Number(seq.Interval[1]);
      const samples = [];
      const frames = new Set([start, end]);
      for (let frame = start; frame < end; frame += 1000 / 30) frames.add(frame);
      const pivot = asVec3(ribbon.PivotPoint);
      for (const frame of [...frames].sort((a, b) => a - b)) {
        const world = evaluateNodeWorldMatrices(nodes, frame, start, end)[ribbon.ObjectId];
        const xyz = world ? [
          world[0]*pivot[0] + world[4]*pivot[1] + world[8]*pivot[2] + world[12],
          world[1]*pivot[0] + world[5]*pivot[1] + world[9]*pivot[2] + world[13],
          world[2]*pivot[0] + world[6]*pivot[1] + world[10]*pivot[2] + world[14],
        ] : pivot;
        samples.push({ t: (frame - start) / 1000, position: wc3ToGltfVec3(...xyz) });
      }
      positions[String(seq.Name)] = samples;
    }
    return {
      name: sanitizeMdxText(ribbon.Name),
      life_span: Number(ribbon.LifeSpan) || 0.1,
      emission_rate: Number(ribbon.EmissionRate) || 0,
      height_above: typeof ribbon.HeightAbove === "number" ? ribbon.HeightAbove : 0,
      height_below: typeof ribbon.HeightBelow === "number" ? ribbon.HeightBelow : 0,
      alpha: typeof ribbon.Alpha === "number" ? ribbon.Alpha : 1,
      color: asVec3(ribbon.Color),
      pivot: wc3ToGltfVec3(...asVec3(ribbon.PivotPoint)),
      visibility_keys: animTrackKeys(ribbon.Visibility) ?? [],
      active_sequences: activeSequencesForEmitter(ribbon, sequences),
      positions_by_sequence: positions,
      material_id: Number(ribbon.MaterialID) || 0,
    };
  });
}

export function writeRibbonSidecar(model, logicalPath, inDir, outDir) {
  const ribbons = extractRibbons(model);
  for (const ribbon of ribbons) {
    const layer = model.Materials?.[ribbon.material_id]?.Layers?.[0];
    const info = model.Textures?.[typeof layer?.TextureID === "number" ? layer.TextureID : 0];
    ribbon.texture = resolveTexturePng(info?.Image ?? "", inDir, outDir, {
      isReplaceable: Boolean(info?.ReplaceableId), replaceableId: info?.ReplaceableId || 0,
    }).pngLogical;
    ribbon.filter_mode = Number(layer?.FilterMode) || 0;
  }
  const destination = path.join(outDir, ...mdxLogicalToPe2(logicalPath).replace(/\.pe2\.json$/i, ".ribbon.json").split("/"));
  atomicWriteBytesSync(destination, JSON.stringify({ version: 1, source: logicalPath,
    sequences: (model.Sequences ?? []).map((seq) => ({ name: sanitizeMdxText(seq.Name), interval: Array.from(seq.Interval) })), ribbons }, null, 2) + "\n");
}

/**
 * MDX Cameras → *.cameras.json（Godot Y-up + MODEL_SCALE）。
 * Portrait 模型通常有一台对准头部的 Camera；背景板仍导出 mesh，由运行时隐藏。
 * @param {object} model
 * @param {string} logicalPath
 * @param {string} outDir
 */
export function writeCamerasSidecar(model, logicalPath, outDir) {
  const camsIn = model.Cameras ?? [];
  const cameras = [];
  for (const cam of camsIn) {
    const posWc3 = asVec3(cam.Position);
    const tgtWc3 = asVec3(cam.TargetPosition);
    const posG = wc3ToGltfVec3(posWc3[0], posWc3[1], posWc3[2]);
    const tgtG = wc3ToGltfVec3(tgtWc3[0], tgtWc3[1], tgtWc3[2]);
    // MDX FieldOfView 是弧度（wowdev 默认约 0.95）。Godot Camera3D.fov 是垂直视角（度）。
    const fovRad = Number(cam.FieldOfView);
    const fovDeg =
      Number.isFinite(fovRad) && fovRad > 0
        ? (fovRad * 180) / Math.PI
        : 30;
    cameras.push({
      name: String(cam.Name || `Camera_${cameras.length}`),
      position: [
        posG[0] * MODEL_SCALE,
        posG[1] * MODEL_SCALE,
        posG[2] * MODEL_SCALE,
      ],
      target: [
        tgtG[0] * MODEL_SCALE,
        tgtG[1] * MODEL_SCALE,
        tgtG[2] * MODEL_SCALE,
      ],
      fov_y_deg: fovDeg,
      near: (Number(cam.NearClip) || 1) * MODEL_SCALE,
      far: (Number(cam.FarClip) || 10000) * MODEL_SCALE,
      // Portrait 等 Sequence 会平移/滚转相机；游戏肖像框用这段，不是 bind 的全身远景。
      translation: dumpCameraVecTrack(cam.Translation),
      rotation: dumpAnimVector(cam.Rotation),
      target_translation: dumpCameraVecTrack(cam.TargetTranslation),
    });
  }
  const camLogical = mdxLogicalToCameras(logicalPath);
  const dest = path.join(outDir, ...camLogical.split("/"));
  const payload = {
    version: 1,
    source: normalizeLogicalPath(logicalPath),
    cameras,
  };
  atomicWriteBytesSync(dest, `${JSON.stringify(payload, null, 2)}\n`);
  return dest;
}

export function collisionVerticesSidecar(vertices) {
  const nums = numArray(vertices);
  const pts = [];
  for (let i = 0; i + 2 < nums.length; i += 3) {
    pts.push(sidecarVec3(nums[i], nums[i + 1], nums[i + 2]));
  }
  return pts;
}

export function aabbOfPoints(pts) {
  if (!pts.length) return null;
  const min = [...pts[0]];
  const max = [...pts[0]];
  for (const p of pts) {
    for (let i = 0; i < 3; i += 1) {
      if (p[i] < min[i]) min[i] = p[i];
      if (p[i] > max[i]) max[i] = p[i];
    }
  }
  return { min, max };
}

/**
 * MDX CollisionShapes → *.collision.json（Godot Y-up + MODEL_SCALE）。
 * Footman：2 个球；TownHall：1 个箱（Vertices 两角点）。
 * @param {object} model
 * @param {string} logicalPath
 * @param {string} outDir
 */
export function writeCollisionSidecar(model, logicalPath, outDir) {
  const shapes = [];
  for (const c of model.CollisionShapes ?? []) {
    if (!c) continue;
    const shape = Number(c.Shape) || 0;
    const vertices = collisionVerticesSidecar(c.Vertices);
    const entry = {
      name: String(c.Name || `Collision_${shapes.length}`),
      object_id: c.ObjectId ?? null,
      parent: c.Parent ?? null,
      shape,
      shape_name: COLLISION_SHAPE_NAMES[shape] ?? String(shape),
      vertices,
    };
    const radius = Number(c.BoundsRadius);
    if (Number.isFinite(radius) && radius > 0) {
      entry.radius = radius * MODEL_SCALE;
    }
    if (shape === 2 && vertices[0]) {
      entry.center = vertices[0];
    }
    if (shape === 0) {
      const aabb = aabbOfPoints(vertices);
      if (aabb) {
        entry.min = aabb.min;
        entry.max = aabb.max;
      }
    }
    shapes.push(entry);
  }
  const logical = mdxLogicalToCollision(logicalPath);
  const dest = path.join(outDir, ...logical.split("/"));
  const payload = {
    version: 1,
    source: normalizeLogicalPath(logicalPath),
    note: "Godot Y-up；已 × MODEL_SCALE=0.01。shape: 0=box 1=plane 2=sphere。",
    shapes,
  };
  atomicWriteBytesSync(dest, `${JSON.stringify(payload, null, 2)}\n`);
  return dest;
}
