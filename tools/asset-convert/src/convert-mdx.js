import fs from "node:fs";
import path from "node:path";
import { Document, NodeIO } from "@gltf-transform/core";
import { parseMDL, parseMDX } from "war3-model";
import {
  collectBakeFrames,
  collectSampleFrames,
  evaluateNodeWorldMatrices,
  isAlternateOrMorphSequenceName,
  LINE_TYPE_NAMES,
  normalizeGeosetAlpha,
  sampleGeosetAlphaInSequence,
  sequenceBakeDurationMs,
  wc3SequenceToAnimName,
} from "./anim.js";
import { blpBufferToPng, writePlaceholderPng } from "./convert-blp.js";
import {
  mat4DecomposeTRS,
  mat4Identity,
  mat4Invert,
  mat4Multiply,
  wc3ToGltfQuat,
  wc3ToGltfVec3,
} from "./mat4.js";
import {
  blpLogicalToPng,
  mdxLogicalToAnimKeys,
  mdxLogicalToAttachments,
  mdxLogicalToBoneRest,
  mdxLogicalToCameras,
  mdxLogicalToCollision,
  mdxLogicalToGeosetVis,
  mdxLogicalToGltf,
  mdxLogicalToPe2,
  normalizeLogicalPath,
  uriFromModelToPng,
} from "./paths.js";
import { walkFiles } from "./walk.js";
import { atomicWriteSync, atomicWriteBytesSync } from "./atomic-write.js";
import { getLog } from "../../pipeline-log.mjs";

const MODEL_SCALE = 0.01;

/** MDX 定长名字常带 \\0 填充；写入 glTF/JSON 前必须剥掉，否则 Godot 报 Unexpected NUL。 */
function sanitizeMdxText(s) {
	if (s == null) return "";
	return String(s).replace(/\0/g, "").trim();
}

/** MDX CollisionShapes.Shape：0=box，1=plane，2=sphere（部分资源还有 3=cylinder）。 */
const COLLISION_SHAPE_NAMES = ["box", "plane", "sphere", "cylinder"];

/** 合法 .gltf：JSON 且含 asset.version（方案 B 外链贴图）。 */
function isValidGltfOnDisk(absPath) {
  let fd;
  try {
    fd = fs.openSync(absPath, "r");
  } catch {
    return false;
  }
  try {
    const stat = fs.fstatSync(fd);
    if (stat.size < 32) return false;
    const n = Math.min(stat.size, 256);
    const buf = Buffer.alloc(n);
    fs.readSync(fd, buf, 0, n, 0);
    const head = buf.toString("utf8").trimStart();
    if (!head.startsWith("{")) return false;
    return /"asset"\s*:/.test(head);
  } finally {
    try {
      fs.closeSync(fd);
    } catch {
      /* ignore */
    }
  }
}

function unlinkQuiet(p) {
  try {
    fs.unlinkSync(p);
  } catch {
    /* ignore */
  }
}

/** @param {unknown} v */
function asVec3(v) {
  if (v == null) return [0, 0, 0];
  if (Array.isArray(v) || ArrayBuffer.isView(v)) {
    return [Number(v[0]) || 0, Number(v[1]) || 0, Number(v[2]) || 0];
  }
  const o = /** @type {Record<string, number>} */ (v);
  return [Number(o[0] ?? o["0"]) || 0, Number(o[1] ?? o["1"]) || 0, Number(o[2] ?? o["2"]) || 0];
}

/**
 * Animated track → [{frame,value}]；静态 number → null。
 * @param {unknown} track
 * @returns {Array<{ frame: number, value: number }> | null}
 */
function animTrackKeys(track) {
  if (track == null || typeof track === "number") return null;
  const keys = /** @type {{ Keys?: Array<{ Frame: number, Vector: ArrayLike<number> }> }} */ (
    track
  ).Keys;
  if (!keys?.length) return null;
  return keys.map((k) => ({
    frame: Number(k.Frame) || 0,
    value: Number(k.Vector?.[0]) || 0,
  }));
}

/**
 * @param {Array<{ frame: number, value: number }> | null} keys
 * @param {number} frame
 * @param {number} seqStart
 * @param {number} seqEnd
 * @param {number} defaultValue 区间内无 key 时的默认（Visibility=1，EmissionRate=0）
 */
function sampleTrackInSequence(keys, frame, seqStart, seqEnd, defaultValue) {
  if (!keys?.length) return defaultValue;
  const sk = keys.filter((k) => k.frame >= seqStart && k.frame <= seqEnd);
  if (!sk.length) return defaultValue;
  if (frame < sk[0].frame) return defaultValue;
  let value = sk[0].value;
  for (const k of sk) {
    if (k.frame <= frame) value = k.value;
    else break;
  }
  return value;
}

/** @param {unknown} track */
function emissionRateForAmount(track) {
  if (typeof track === "number") return track;
  const keys = animTrackKeys(track);
  if (!keys?.length) return 0;
  return Math.max(0, ...keys.map((k) => k.value));
}

/**
 * 该发射器在哪些 Sequence 中应发光（vis≥0.5 且 rate>0）。
 * 返回 null = 全程开启（装饰物火盆等：无 Visibility 轨 + 静态 rate>0）。
 * 死亡爆发等脉冲 rate：只要区间内任一关键帧 rate>0 且当时可见即计入（勿只采中点）。
 * @param {object} pe
 * @param {Array<{ Name?: string, Interval: ArrayLike<number> }>} sequences
 * @returns {string[] | null}
 */
function activeSequencesForEmitter(pe, sequences) {
  const visKeys = animTrackKeys(pe.Visibility);
  const rateKeys = animTrackKeys(pe.EmissionRate);
  const staticRate = typeof pe.EmissionRate === "number" ? pe.EmissionRate : null;
  if (visKeys == null && staticRate != null && staticRate > 0) {
    return null;
  }
  const out = [];
  for (const s of sequences || []) {
    const start = Number(s.Interval?.[0]) || 0;
    const end = Number(s.Interval?.[1]) || start;
    if (_emitterActiveInSequence(visKeys, rateKeys, staticRate, start, end)) {
      out.push(String(s.Name || "").trim());
    }
  }
  return out;
}

/**
 * @param {Array<{ frame: number, value: number }> | null} visKeys
 * @param {Array<{ frame: number, value: number }> | null} rateKeys
 * @param {number | null} staticRate
 * @param {number} start
 * @param {number} end
 */
function _emitterActiveInSequence(visKeys, rateKeys, staticRate, start, end) {
  const mid = Math.floor((start + end) / 2);
  // 必须采 vis/rate 关键帧：火枪 Flame 等脉冲只亮几十帧，采中点会漏（active=[]）。
  const sampleFrames = new Set([mid, start, end]);
  for (const k of rateKeys || []) {
    if (k.frame >= start && k.frame <= end) sampleFrames.add(k.frame);
  }
  for (const k of visKeys || []) {
    if (k.frame >= start && k.frame <= end) sampleFrames.add(k.frame);
  }
  const hasAnimRate = Array.isArray(rateKeys) && rateKeys.length > 0;
  for (const frame of sampleFrames) {
    const vis = sampleTrackInSequence(visKeys, frame, start, end, 1);
    const rate = hasAnimRate
      ? sampleTrackInSequence(rateKeys, frame, start, end, 0)
      : staticRate != null
        ? staticRate
        : sampleTrackInSequence(rateKeys, frame, start, end, 0);
    if (vis >= 0.5 && rate > 0.01) return true;
  }
  return false;
}

/**
 * Serialize ParticleEmitters2 (+ ensure textures on disk) next to the GLB.
 * @param {object} model
 * @param {string} logicalPath
 * @param {string} inDir
 * @param {string} outDir
 */
function writePe2Sidecar(model, logicalPath, inDir, outDir) {
  const emittersIn = model.ParticleEmitters2 ?? [];
  const textures = model.Textures ?? [];
  const sequences = model.Sequences ?? [];
  const allNodes = model.Nodes ?? [];
  const emitters = [];
  const boneIdToName = (() => {
    /** @type {Map<number, string>} */
    const m = new Map();
    for (const b of model.Bones ?? []) {
      if (b?.ObjectId != null) m.set(b.ObjectId, String(b.Name || ""));
    }
    for (const h of model.Helpers ?? []) {
      if (h?.ObjectId != null && !m.has(h.ObjectId)) {
        m.set(h.ObjectId, String(h.Name || ""));
      }
    }
    for (const n of allNodes) {
      if (n?.ObjectId != null && !m.has(n.ObjectId)) {
        m.set(n.ObjectId, String(n.Name || ""));
      }
    }
    return m;
  })();

  for (const pe of emittersIn) {
    const tid = typeof pe.TextureID === "number" ? pe.TextureID : 0;
    const texInfo = textures[tid];
    const resolved = resolveTexturePng(texInfo?.Image ?? "", inDir, outDir, {
      isReplaceable: Boolean(texInfo?.ReplaceableId),
      replaceableId: texInfo?.ReplaceableId || 0,
    });
    const pivotWc3 = asVec3(pe.PivotPoint);
    const pivot = wc3ToGltfVec3(pivotWc3[0], pivotWc3[1], pivotWc3[2]);
    const seg = Array.isArray(pe.SegmentColor) ? pe.SegmentColor : [];
    const visKeys = animTrackKeys(pe.Visibility);
    const rateKeys = animTrackKeys(pe.EmissionRate);
    const active = activeSequencesForEmitter(pe, sequences);
    const parentId = pe.Parent ?? null;
    const boneName =
      parentId != null && boneIdToName.has(parentId)
        ? boneIdToName.get(parentId) || null
        : null;
    const entry = {
      name: String(pe.Name || `PE2_${pe.ObjectId ?? emitters.length}`),
      object_id: pe.ObjectId ?? -1,
      parent: parentId,
      bone: boneName,
      flags: pe.Flags ?? 0,
      speed: typeof pe.Speed === "number" ? pe.Speed : Number(pe.Speed) || 0,
      variation: typeof pe.Variation === "number" ? pe.Variation : Number(pe.Variation) || 0,
      latitude: typeof pe.Latitude === "number" ? pe.Latitude : Number(pe.Latitude) || 0,
      gravity: typeof pe.Gravity === "number" ? pe.Gravity : Number(pe.Gravity) || 0,
      life_span: typeof pe.LifeSpan === "number" ? pe.LifeSpan : Number(pe.LifeSpan) || 0.1,
      emission_rate: emissionRateForAmount(pe.EmissionRate),
      width: typeof pe.Width === "number" ? pe.Width : Number(pe.Width) || 0,
      length: typeof pe.Length === "number" ? pe.Length : Number(pe.Length) || 0,
      filter_mode: Number(pe.FilterMode) || 0,
      rows: Math.max(1, Number(pe.Rows) || 1),
      columns: Math.max(1, Number(pe.Columns) || 1),
      frame_flags: Number(pe.FrameFlags ?? pe.HeadOrTail) || 0,
      tail_length: Number(pe.TailLength) || 0,
      squirt: Boolean(pe.Squirt),
      time_middle: Number(pe.Time) || 0.5,
      segment_color: [asVec3(seg[0]), asVec3(seg[1]), asVec3(seg[2])],
      alpha: asVec3(pe.Alpha),
      particle_scaling: asVec3(pe.ParticleScaling),
      life_span_uv: asVec3(pe.LifeSpanUVAnim),
      decay_uv: asVec3(pe.DecayUVAnim),
      texture: resolved.pngLogical,
      priority_plane: Number(pe.PriorityPlane) || 0,
      pivot,
      // null = 全程发射（火盆等）；数组 = 仅这些 Sequence 名下发射
      active_sequences: active,
    };
    if (visKeys) entry.visibility_keys = visKeys;
    if (rateKeys) entry.emission_rate_keys = rateKeys;
    const localPivot = bakePe2LocalPivot(allNodes, pe);
    if (localPivot) entry.local_pivot = localPivot;
    // 发射器节点常有 Translation/Rotation（兵营门光在 Stand Work 才挪到门口）。
    // 按 Sequence 烤 W*pivot → glTF，供运行时/编辑器切动画时改 position。
    // 已绑骨时跟骨走，不再用世界空间 pivot_by_sequence。
    if (!boneName) {
      const pivotsBySeq = bakePe2PivotsBySequence(allNodes, pe, sequences);
      if (pivotsBySeq && Object.keys(pivotsBySeq).length > 0) {
        entry.pivot_by_sequence = pivotsBySeq;
      }
    }
    emitters.push(entry);
  }

  const pe2Logical = mdxLogicalToPe2(logicalPath);
  const dest = path.join(outDir, ...pe2Logical.split("/"));
  const payload = {
    version: 2,
    source: normalizeLogicalPath(logicalPath),
    sequences: sequences.map((s) => ({
      name: String(s.Name || ""),
      interval: [Number(s.Interval?.[0]) || 0, Number(s.Interval?.[1]) || 0],
    })),
    emitters,
  };
  // P3-10：原子写盘（.tmp → rename）—— 中途崩溃不留半成品 .pe2.json
  atomicWriteBytesSync(dest, `${JSON.stringify(payload, null, 2)}\n`);
  return dest;
}

/**
 * 子 Pivot 相对父 Pivot → glTF 轴（与 SkinMesh 顶点同一空间）。
 * 根节点已 setScale(MODEL_SCALE)，此处不再 ×0.01，否则骨骼/挂点会再缩 100 倍挤到原点。
 * MDX 无 Translation 时子节点 world≈父 world；挂点/杖尖靠 Pivot 差。
 * @param {unknown} childPivot
 * @param {unknown} parentPivot
 * @returns {number[]}
 */
function bakePivotDeltaGltf(childPivot, parentPivot) {
  const c = asVec3(childPivot);
  const p = asVec3(parentPivot);
  return wc3ToGltfVec3(c[0] - p[0], c[1] - p[1], c[2] - p[2]);
}

/**
 * 发射器相对父骨的局部平移（与 SkinMesh 顶点同空间，根节点再 × MODEL_SCALE）。
 * 绑 BoneAttachment 后作 position。勿用 frame0 的 inv(P)*E：sampleAnimVector
 * 会钳到第一帧 Translation（ArchMage Attack 轨 ≈ -126），把杖尖烤成握柄附近。
 * @param {import('war3-model').Node[]} allNodes
 * @param {object} pe
 * @returns {number[] | null}
 */
function bakePe2LocalPivot(allNodes, pe) {
  const parentId = pe.Parent;
  if (typeof parentId !== "number" || parentId < 0) return null;
  const parent = (allNodes || []).find((n) => n && n.ObjectId === parentId);
  if (!parent) return null;
  return bakePivotDeltaGltf(pe.PivotPoint, parent.PivotPoint);
}

/**
 * 每个 Sequence 中点：发射器节点 worldMatrix * PivotPoint → glTF。
 * @param {import('war3-model').Node[]} allNodes
 * @param {object} pe
 * @param {Array<{ Name?: string, Interval: ArrayLike<number> }>} sequences
 * @returns {Record<string, number[]> | null}
 */
function bakePe2PivotsBySequence(allNodes, pe, sequences) {
  const objectId = pe.ObjectId;
  if (typeof objectId !== "number" || objectId < 0) return null;
  const node = (allNodes || []).find((n) => n && n.ObjectId === objectId);
  if (!node) return null;
  const hasAnim =
    Boolean(node.Translation?.Keys?.length) ||
    Boolean(node.Rotation?.Keys?.length) ||
    Boolean(node.Scaling?.Keys?.length);
  if (!hasAnim) return null;
  const pivot = node.PivotPoint || pe.PivotPoint || [0, 0, 0];
  /** @type {Record<string, number[]>} */
  const out = {};
  for (const seq of sequences || []) {
    const name = String(seq.Name || "").trim();
    if (!name) continue;
    const start = Number(seq.Interval?.[0]) || 0;
    const end = Number(seq.Interval?.[1]) || 0;
    const frame = start + (end - start) * 0.5;
    const worlds = evaluateNodeWorldMatrices(allNodes, frame, start, end);
    const m = worlds[objectId];
    if (!m) continue;
    const wx =
      m[0] * pivot[0] + m[4] * pivot[1] + m[8] * pivot[2] + m[12];
    const wy =
      m[1] * pivot[0] + m[5] * pivot[1] + m[9] * pivot[2] + m[13];
    const wz =
      m[2] * pivot[0] + m[6] * pivot[1] + m[10] * pivot[2] + m[14];
    out[name] = wc3ToGltfVec3(wx, wy, wz);
  }
  return out;
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

/** WC3 vec3 → glTF Y-up，再 × MODEL_SCALE（与 cameras.json 一致）. */
function sidecarVec3(x, y, z) {
  const g = wc3ToGltfVec3(Number(x) || 0, Number(y) || 0, Number(z) || 0);
  return [g[0] * MODEL_SCALE, g[1] * MODEL_SCALE, g[2] * MODEL_SCALE];
}

function collisionVerticesSidecar(vertices) {
  const nums = numArray(vertices);
  const pts = [];
  for (let i = 0; i + 2 < nums.length; i += 3) {
    pts.push(sidecarVec3(nums[i], nums[i + 1], nums[i + 2]));
  }
  return pts;
}

function aabbOfPoints(pts) {
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
function writeCollisionSidecar(model, logicalPath, outDir) {
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

/**
 * Sidecar for Godot: GLTFDocument drops scale tracks on skinned Geoset / empty
 * GeosetVis parents. Bake injects `:visible` onto Skeleton3D/Geoset_* meshes.
 *
 * @param {ReturnType<typeof parseMDX>} model
 * @param {string} logicalPath
 * @param {string} outDir
 * @param {Iterable<number>} geosetIds
 */
function writeGeosetVisSidecar(model, logicalPath, outDir, geosetIds) {
  const ids = [...geosetIds];
  const sequencesOut = [];
  for (const seq of model.Sequences ?? []) {
    const start = Number(seq.Interval?.[0]) || 0;
    const end = Number(seq.Interval?.[1]) || 0;
    if (end <= start) continue;
    const animName = wc3SequenceToAnimName(seq.Name || "Anim");
    const frames = collectSampleFrames(
      model.Nodes || [],
      start,
      end,
      33,
      model.GeosetAnims || [],
    );
    /** @type {Record<string, Array<{ t: number, alpha: number, v: number }>>} */
    const geosets = {};
    for (const gi of ids) {
      /** @type {Array<{ t: number, alpha: number, v: number }>} */
      const keys = [];
      let lastAlpha = /** @type {number | null} */ (null);
      for (const frame of frames) {
        const timeSec = (frame - start) / 1000;
        const alphaRaw = sampleGeosetAlphaInSequence(
          model.GeosetAnims,
          gi,
          frame,
          start,
          end,
        );
        const alpha = normalizeGeosetAlpha(alphaRaw);
        const v = alpha >= 0.5 ? 1 : 0;
        if (lastAlpha === null || Math.abs(lastAlpha - alpha) > 0.0005) {
          keys.push({
            t: Math.round(timeSec * 1000) / 1000,
            alpha,
            v,
          });
          lastAlpha = alpha;
        }
      }
      geosets[String(gi)] = keys;
    }
    sequencesOut.push({
      name: animName,
      duration: Math.round(((end - start) / 1000) * 1000) / 1000,
      geosets,
    });
  }

  const visLogical = mdxLogicalToGeosetVis(logicalPath);
  const dest = path.join(outDir, ...visLogical.split("/"));
  const payload = {
    version: 2,
    source: normalizeLogicalPath(logicalPath),
    sequences: sequencesOut,
  };
  // P3-10：原子写盘
  atomicWriteBytesSync(dest, `${JSON.stringify(payload, null, 2)}\n`);
  return dest;
}

/** @param {ArrayLike<number> | Record<string, number> | undefined | null} v */
function numArray(v) {
  if (v == null) return [];
  if (typeof v === "number") return [Number(v) || 0];
  if (typeof v !== "object") return [];
  if (typeof v.length === "number") {
    return Array.from(v, (n) => Number(n) || 0);
  }
  const keys = Object.keys(v)
    .map((k) => Number(k))
    .filter((n) => Number.isInteger(n) && n >= 0)
    .sort((a, b) => a - b);
  return keys.map((k) => Number(v[k]) || 0);
}

/**
 * MDX AnimVector → JSON（保留原始 Frame / Vector / InTan / OutTan / LineType）。
 * @param {import('war3-model').AnimVector | number | undefined | null} anim
 */
/** Camera Translation / TargetTranslation：每 key 已 Y-up × MODEL_SCALE。 */
function dumpCameraVecTrack(anim) {
  const d = dumpAnimVector(anim);
  if (!d?.keys?.length) return d;
  return {
    ...d,
    keys: d.keys.map((k) => {
      const v = k.vector || [];
      return {
        ...k,
        vector: sidecarVec3(v[0] || 0, v[1] || 0, v[2] || 0),
      };
    }),
  };
}

function dumpAnimVector(anim) {
  if (anim == null) return null;
  if (typeof anim === "number") return { static: anim };
  if (ArrayBuffer.isView(anim) || Array.isArray(anim)) {
    return { static: numArray(anim) };
  }
  const keys = anim.Keys;
  if (!keys?.length) return null;
  const line = Number(anim.LineType) || 0;
  return {
    line_type: line,
    line_type_name: LINE_TYPE_NAMES[line] ?? String(line),
    global_seq_id:
      anim.GlobalSeqId === undefined || anim.GlobalSeqId === null || anim.GlobalSeqId < 0
        ? null
        : Number(anim.GlobalSeqId),
    keys: keys.map((k) => {
      /** @type {{ frame: number, vector: number[], in_tan?: number[], out_tan?: number[] }} */
      const e = { frame: Number(k.Frame) || 0, vector: numArray(k.Vector) };
      if (k.InTan) e.in_tan = numArray(k.InTan);
      if (k.OutTan) e.out_tan = numArray(k.OutTan);
      return e;
    }),
  };
}

/** Attachment 显隐：只看 Visibility 轨。Flags&0x4 是 DontInherit Scaling，不是隐藏。 */
function attachmentVisibleByDefault(a) {
  const vis = dumpAnimVector(a?.Visibility);
  if (!vis) return true;
  if (typeof vis.static === "number") return vis.static >= 0.5;
  if (Array.isArray(vis.static)) return Number(vis.static[0]) >= 0.5;
  const k0 = vis.keys?.[0]?.vector?.[0];
  if (k0 != null) return Number(k0) >= 0.5;
  return true;
}

/** @param {import('war3-model').AnimVector | undefined | null} anim */
function countKeysInInterval(anim, start, end) {
  if (!anim?.Keys?.length) return 0;
  let n = 0;
  for (const k of anim.Keys) {
    const f = Number(k.Frame) || 0;
    if (f >= start && f <= end) n += 1;
  }
  return n;
}

/**
 * 旁路：尽量导出 MDX 原始动画关键帧（毫秒全局时间轴，非 glTF 重采样）。
 * glTF 仍按 Sequence 烤世界矩阵；本文件供对照 Hermite/Bezier 与 Interval。
 *
 * @param {ReturnType<typeof parseMDX>} model
 * @param {string} logicalPath
 * @param {string} outDir
 */
function writeAnimKeysSidecar(model, logicalPath, outDir) {
  const sequences = [];
  for (const seq of model.Sequences ?? []) {
    const start = Number(seq.Interval?.[0]) || 0;
    const end = Number(seq.Interval?.[1]) || 0;
    if (end <= start) continue;
    const mdxName = String(seq.Name || "");
    let tKeys = 0;
    let rKeys = 0;
    let sKeys = 0;
    for (const node of model.Nodes ?? []) {
      if (!node) continue;
      tKeys += countKeysInInterval(node.Translation, start, end);
      rKeys += countKeysInInterval(node.Rotation, start, end);
      sKeys += countKeysInInterval(node.Scaling, start, end);
    }
    let alphaKeys = 0;
    for (const ga of model.GeosetAnims ?? []) {
      if (ga?.Alpha && typeof ga.Alpha !== "number") {
        alphaKeys += countKeysInInterval(ga.Alpha, start, end);
      }
    }
    sequences.push({
      name: wc3SequenceToAnimName(mdxName || "Anim"),
      mdx_name: mdxName,
      interval: [start, end],
      duration_ms: end - start,
      duration_sec: Math.round(((end - start) / 1000) * 1000) / 1000,
      looping: !seq.NonLooping,
      move_speed: Number(seq.MoveSpeed) || 0,
      rarity: Number(seq.Rarity) || 0,
      key_count: {
        translation: tKeys,
        rotation: rKeys,
        scaling: sKeys,
        geoset_alpha: alphaKeys,
      },
    });
  }

  const nodes = [];
  for (const node of model.Nodes ?? []) {
    if (!node) continue;
    const translation = dumpAnimVector(node.Translation);
    const rotation = dumpAnimVector(node.Rotation);
    const scaling = dumpAnimVector(node.Scaling);
    if (!translation && !rotation && !scaling) continue;
    nodes.push({
      name: String(node.Name || ""),
      object_id: node.ObjectId,
      parent: node.Parent ?? null,
      flags: Number(node.Flags) || 0,
      billboarded: ((Number(node.Flags) || 0) & 0x8) !== 0,
      translation,
      rotation,
      scaling,
    });
  }

  const geosetAnims = [];
  for (const ga of model.GeosetAnims ?? []) {
    if (!ga) continue;
    const alpha = dumpAnimVector(ga.Alpha);
    const color = dumpAnimVector(ga.Color);
    geosetAnims.push({
      geoset_id: ga.GeosetId,
      flags: ga.Flags ?? 0,
      alpha,
      color,
    });
  }

  const textureAnims = [];
  for (const ta of model.TextureAnims ?? []) {
    if (!ta) continue;
    const translation = dumpAnimVector(ta.Translation);
    const rotation = dumpAnimVector(ta.Rotation);
    const scaling = dumpAnimVector(ta.Scaling);
    if (!translation && !rotation && !scaling) continue;
    textureAnims.push({ translation, rotation, scaling });
  }

  const events = [];
  for (const ev of model.EventObjects ?? []) {
    if (!ev) continue;
    const frames = numArray(ev.EventTrack);
    if (!frames.length) continue;
    events.push({
      name: String(ev.Name || ""),
      object_id: ev.ObjectId,
      parent: ev.Parent ?? null,
      frames,
    });
  }

  const dest = path.join(outDir, ...mdxLogicalToAnimKeys(logicalPath).split("/"));
  const payload = {
    version: 1,
    source: normalizeLogicalPath(logicalPath),
    time_unit: "ms",
    note: "MDX 全局毫秒时间轴；Sequences.interval 为片段范围。GlobalSeqId≥0 的轨按 GlobalSequences 时钟循环，不跟 Sequence 区间走。glTF 动画已按 Sequence 归零并重采样（循环段会拉长到最长 Global Sequence）。原始 Keys 在此。",
    global_sequences: (model.GlobalSequences ?? []).map((d) => Number(d) || 0),
    sequences,
    nodes,
    geoset_anims: geosetAnims,
    texture_anims: textureAnims,
    events,
  };
  atomicWriteBytesSync(dest, `${JSON.stringify(payload, null, 2)}\n`);
  return dest;
}


/**
 * 把 MDX 里没被 m2g 写进 .gltf 的"附加元素"导出成 sidecar JSON。
 * 包含 2 部分：
 * 1. attachments[]：4 类辅助元素（Attachment / ParticleEmitter2 / Light / RibbonEmitter）
 * 2. geoset_expansions[]：每个 geoset 按 VertexGroup 拆分成 group
 *    （每个 group 1 个 mesh 节点 + BoneAttachment3D，烘焙时由 Godot 端拼装）
 *
 * @param {object} model
 * @param {string} logicalPath
 * @returns {object} attachments sidecar
 */
export function extractAttachments(model, logicalPath) {
	const boneNames = (model.Bones ?? []).map((b) => b.Name);

	// 查 ObjectId → bone name 映射。
	// 修：war3-model 库只把 mesh-related bone (flag=256) 放进 model.Bones，
	// 真正的骨架 bone（Bone_Root / Bone_Pelvis / Bone_Foot_L 等 flag=0 Helper）
	// 只在 model.Nodes 里。attachment.Parent 可能引用任一边。
	// 例：Footman attachment "Foot Left Ref" Parent=29 → Bone_Foot_L (Helper, in Nodes)
	const _boneIdToName = (() => {
		const m = new Map();
		for (const b of model.Bones ?? []) {
			if (b.ObjectId != null) m.set(b.ObjectId, b.Name);
		}
		for (const id of Object.keys(model.Nodes ?? {})) {
			const n = model.Nodes[id];
			if (!m.has(n.ObjectId)) m.set(n.ObjectId, n.Name);
		}
		return m;
	})();

	function boneNameById(id) {
		if (id == null) return null;
		const n = _boneIdToName.get(id) ?? null;
		return n == null ? null : sanitizeMdxText(n);
	}

	const out = {
		version: 1,
		model: logicalPath,
		skeleton_bone_count: boneNames.length,
		skeleton_helper_count: (model.Helpers ?? []).length,
		attachments: [],
		geoset_expansions: [],
	};

	function nodeByObjectId(id) {
		if (id == null) return null;
		for (const n of model.Nodes ?? []) {
			if (n && n.ObjectId === id) return n;
		}
		return null;
	}

	// 4 类辅助 attachment
	for (const a of model.Attachments ?? []) {
		const parentNode = nodeByObjectId(a.Parent);
		const entry = {
			name: sanitizeMdxText(a.Name),
			type: "attachment",
			bone: boneNameById(a.Parent),
			source: `attachment_${a.AttachmentID ?? 0}`,
			object_id: a.ObjectId ?? null,
			path: String(a.Path || ""),
			// Flags 0x4 = DontInherit Scaling，不是显隐。无 KATV 则插座保持可见。
			visibility_default: attachmentVisibleByDefault(a),
			// 世界/场景根挂点：已 × MODEL_SCALE
			pivot: sidecarVec3(
				asVec3(a.PivotPoint)[0],
				asVec3(a.PivotPoint)[1],
				asVec3(a.PivotPoint)[2],
			),
		};
		// 绑骨：相对父骨 Pivot 的局部偏移（与 SkinMesh 顶点同空间；根节点再 × MODEL_SCALE）
		if (parentNode && boneNameById(a.Parent)) {
			entry.pivot_delta = bakePivotDeltaGltf(a.PivotPoint, parentNode.PivotPoint);
		}
		const vis = dumpAnimVector(a.Visibility);
		if (vis) entry.visibility = vis;
		out.attachments.push(entry);
	}
	for (const p of model.ParticleEmitters2 ?? []) {
		out.attachments.push({
			name: sanitizeMdxText(p.Name),
			type: "particle",
			bone: boneNameById(p.Parent),
			source: `pe2:${sanitizeMdxText(p.Name)}`,
		});
	}
	for (const l of model.Lights ?? []) {
		const pivot = asVec3(l.PivotPoint);
		const color = asVec3(l.Color);
		const vis = dumpAnimVector(l.Visibility);
		const vis0 = vis?.keys?.[0]?.vector?.[0];
		const visStatic = vis?.static;
		let visibilityDefault = false;
		if (typeof visStatic === "number") {
			visibilityDefault = visStatic >= 0.5;
		} else if (Array.isArray(visStatic)) {
			visibilityDefault = Number(visStatic[0]) >= 0.5;
		} else if (vis0 != null) {
			visibilityDefault = Number(vis0) >= 0.5;
		}
		const entry = {
			name: sanitizeMdxText(l.Name),
			type: "light",
			bone: boneNameById(l.Parent),
			source: Number(l.LightType) === 0 ? "OmniLight" : "DirectionalLight",
			object_id: l.ObjectId ?? null,
			light_type: Number(l.LightType) || 0,
			attenuation_start: (Number(l.AttenuationStart) || 0) * MODEL_SCALE,
			attenuation_end: (Number(l.AttenuationEnd) || 0) * MODEL_SCALE,
			intensity: Number(l.Intensity) || 0,
			color: [color[0], color[1], color[2]],
			visibility_default: visibilityDefault,
			pivot: sidecarVec3(pivot[0], pivot[1], pivot[2]),
		};
		if (vis) entry.visibility = vis;
		out.attachments.push(entry);
	}
	for (const r of model.RibbonEmitters ?? []) {
		out.attachments.push({
			name: sanitizeMdxText(r.Name),
			type: "ribbon",
			bone: boneNameById(r.Parent),
			source: "ribbon_emitter",
		});
	}

	// geoset 顶点按 VertexGroup 拆分（每 group = 1 个 mesh 节点 + BoneAttachment3D）
	// 同时识别 geoset_kind（normal / teamcolor / glow）— 用于 D-3 export_model_scenes 替换为 ShaderMaterial
	// 识别逻辑：geoset.MaterialId → Materials[mid].Layers[] → 找 TextureId=1 (teamcolor) / 2 (team_glow)
	function classifyGeosetKind(geoset) {
		const matId = geoset.MaterialId;
		if (matId == null) return "normal";
		const mat = model.Materials?.[matId];
		if (!mat || !mat.Layers) return "normal";
		let has_teamcolor = false;
		let has_teamglow = false;
		for (const layer of mat.Layers) {
			const tid = layer.TextureId;
			if (tid === 1) has_teamcolor = true;
			if (tid === 2) has_teamglow = true;
		}
		if (has_teamglow) return "glow";
		if (has_teamcolor) return "teamcolor";
		return "normal";
	}
	for (let gi = 0; gi < (model.Geosets ?? []).length; gi += 1) {
		const g = model.Geosets[gi];
		const vg = g.VertexGroup;
		const kind = classifyGeosetKind(g);
		if (!vg || vg.length === 0) {
			out.geoset_expansions.push({
				geoset_index: gi,
				geoset_name: `Geoset_${gi}`,
				kind: kind,
				groups: [],
			});
			continue;
		}
		// 按 group index 分组顶点
		const groupMap = new Map(); // groupIdx -> [vertIdx]
		for (let i = 0; i < vg.length; i += 1) {
			const groupIdx = vg[i];
			if (!groupMap.has(groupIdx)) groupMap.set(groupIdx, []);
			groupMap.get(groupIdx).push(i);
		}
		const groups = [];
		for (const [groupIdx, vertIdx] of groupMap) {
			const boneIds = g.Groups?.[groupIdx] ?? [];
			const bones = boneIds
				.map((id) => boneNameById(id))
				.filter((n) => n != null);
			groups.push({
				group_index: groupIdx,
				bones: bones,
				vertex_count: vertIdx.length,
				vertex_indices: vertIdx, // 全部 vertex indices（烘焙时 subset 顶点）
			});
		}
		out.geoset_expansions.push({
			geoset_index: gi,
			geoset_name: `Geoset_${gi}`,
			kind: kind,
			groups: groups,
		});
	}

	// rep_materials[]：列出所有 model 级别的 replaceable texture 用法（TextureId=0/1/2）
	// D-3 export_model_scenes 用此决定哪些 geoset 替换为 ShaderMaterial
	const rep_materials = [];
	for (let mi = 0; mi < (model.Materials ?? []).length; mi += 1) {
		const mat = model.Materials[mi];
		if (!mat || !mat.Layers) continue;
		for (let li = 0; li < mat.Layers.length; li += 1) {
			const layer = mat.Layers[li];
			const tid = layer.TextureId;
			if (tid == null || tid === 0) continue;
			const kind = tid === 1 ? "teamcolor" : tid === 2 ? "teamglow" : `rep${tid}`;
			rep_materials.push({
				material_index: mi,
				layer_index: li,
				replaceable_id: tid,
				kind: kind,
			});
		}
	}
	out.rep_materials = rep_materials;

	return out;
}


/**
 * 写 attachments JSON sidecar 到 <model>.attachments.json
 * @param {object} model
 * @param {string} logicalPath
 * @param {string} outDir
 * @returns {string} 写出路径
 */
export function writeAttachmentsSidecar(model, logicalPath, outDir) {
	const att = extractAttachments(model, logicalPath);
	const logical = mdxLogicalToAttachments(logicalPath);
	const dest = path.join(outDir, ...logical.split("/"));
	fs.mkdirSync(path.dirname(dest), { recursive: true });
	atomicWriteBytesSync(dest, `${JSON.stringify(att, null, 2)}\n`);
	return dest;
}

/**
 * 写 Stand 绑定姿态的 glTF TRS（平铺骨骼 rest）。马网格已是绑定外形 rest≈I；
 * 骑士是 T-pose 顶点，rest=Stand 世界阵才能坐上马。IBM 保持单位阵。
 * @param {Array<{ObjectId: number, Name?: string}>} skinAnimNodes
 * @param {Float32Array[]} bindWorlds
 * @param {Array<{getName(): string}>} jointList
 * @param {string} logicalPath
 * @param {string} outDir
 */
function writeBoneRestSidecar(skinAnimNodes, bindWorlds, jointList, logicalPath, outDir) {
  const bones = [];
  for (let i = 0; i < jointList.length; i += 1) {
    const src = skinAnimNodes[i];
    const { t, r, s } = transformMat4Wc3ToGltf(bindWorlds[src.ObjectId] || mat4Identity());
    bones.push({
      name: jointList[i].getName(),
      translation: t,
      rotation: r,
      scale: s,
    });
  }
  const logical = mdxLogicalToBoneRest(logicalPath);
  const dest = path.join(outDir, ...logical.split("/"));
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  atomicWriteBytesSync(dest, `${JSON.stringify({ version: 2, bones }, null, 2)}\n`);
  if (globalThis.__WC3_DEBUG_JOINT) console.log("[bone_rest] wrote", dest, "bones=", bones.length);
  return dest;
}

/**
 * Helpers 里真正的骨架骨（Bone_Root / Bone_Foot_L 等）不在 model.Bones。
 * 追加进 Skin 时必须排在 Bones 之后，以免改 JOINTS_0 下标。
 * @param {object} model
 * @param {Array<{ ObjectId?: number }>} boneNodes
 */
function extraHelperNodes(model, boneNodes) {
  const seen = new Set((boneNodes ?? []).map((b) => b.ObjectId));
  const extras = [];
  for (const h of model.Helpers ?? []) {
    if (!h || h.ObjectId == null || seen.has(h.ObjectId)) continue;
    seen.add(h.ObjectId);
    extras.push(h);
  }
  return extras;
}

function uniqueJointName(src, used) {
  const base =
    sanitizeMdxText(src?.Name || `Bone_${src?.ObjectId}`) || `Bone_${src?.ObjectId}`;
  if (!used.has(base)) {
    used.add(base);
    return base;
  }
  const alt = `${base}_${src.ObjectId}`;
  used.add(alt);
  return alt;
}

/**
 * @param {ArrayBuffer | Buffer} data
 * @param {string} logicalPath
 */
export function parseModel(data, logicalPath) {
  const buf =
    data instanceof ArrayBuffer
      ? data
      : data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
  if (logicalPath.toLowerCase().endsWith(".mdl")) {
    return parseMDL(Buffer.from(buf).toString("utf8"));
  }
  return parseMDX(buf);
}

/** Classic WC3 replaceable texture IDs → default BLP (used when Image is empty). */
const REPLACEABLE_DEFAULTS = {
	// 默认队伍色：导出时直接嵌 TeamColor00（红/玩家1）；运行时仍可按 owner 重染
	1: "ReplaceableTextures/TeamColor/TeamColor00.blp",
	// 英雄脚底/武器光晕：软圆 TeamGlow；运行时按队伍色乘 albedo
	2: "ReplaceableTextures/TeamGlow/TeamGlow00.blp",
	11: "ReplaceableTextures/Cliff/Cliff0.blp",
	31: "ReplaceableTextures/LordaeronTree/LordaeronSnowTree.blp",
	// Icecrown / Lost Temple uses Ice_Tree on AshenTree models (ITtw).
	32: "ReplaceableTextures/AshenvaleTree/Ice_Tree.blp",
	33: "ReplaceableTextures/BarrensTree/BarrensTree.blp",
	34: "ReplaceableTextures/NorthrendTree/NorthTree.blp",
	35: "ReplaceableTextures/Mushroom/MushroomTree.blp",
	36: "ReplaceableTextures/RuinsTree/RuinsTree.blp",
	37: "ReplaceableTextures/UndergroundTree/UnderTree.blp",
};

/** ReplaceableId → 占位 PNG（仅当默认 BLP/PNG 也找不到时） */
const REPLACEABLE_PLACEHOLDERS = {
	// 对齐 TeamColor00 红，避免再出现整片占位蓝
	1: { pngLogical: "_placeholders/team_color.png", rgba: [220, 40, 40, 255] },
	// 半透明白：加法混合时才像光晕；误当成不透明时也不至于整块实心蓝
	2: { pngLogical: "_placeholders/team_glow.png", rgba: [255, 255, 255, 96] },
};

/**
 * @param {string} logical
 * @param {string} inDir
 */
function findBlpOnDisk(logical, inDir) {
  const parts = normalizeLogicalPath(logical).split("/");
  let cur = inDir;
  for (const part of parts) {
    if (!fs.existsSync(cur)) return null;
    const names = fs.readdirSync(cur);
    const hit = names.find((n) => n.toLowerCase() === part.toLowerCase());
    if (!hit) return null;
    cur = path.join(cur, hit);
  }
  return fs.existsSync(cur) ? cur : null;
}

function resolveTexturePng(
	imagePath,
	inDir,
	outDir,
	{ isReplaceable = false, replaceableId = 0 } = {},
) {
	let raw = normalizeLogicalPath(imagePath || "");
	if (!raw && replaceableId) {
		const def = REPLACEABLE_DEFAULTS[replaceableId];
		if (def) raw = def;
	}
	if (!raw) {
		const ph =
			REPLACEABLE_PLACEHOLDERS[replaceableId] ||
			REPLACEABLE_PLACEHOLDERS[1];
		const pngLogical = ph.pngLogical;
		const dest = path.join(outDir, ...pngLogical.split("/"));
		if (!fs.existsSync(dest)) writePlaceholderPng(dest, ph.rgba);
		return {
			pngLogical,
			pngBytes: fs.readFileSync(dest),
			isReplaceable: true,
			replaceableId: replaceableId || 1,
		};
	}

	const pngLogical = blpLogicalToPng(raw);
	const pngDest = path.join(outDir, ...pngLogical.split("/"));
	if (fs.existsSync(pngDest)) {
		return {
			pngLogical,
			pngBytes: fs.readFileSync(pngDest),
			isReplaceable,
			replaceableId: replaceableId || 0,
		};
	}

	const blpSrc = findBlpOnDisk(raw, inDir);
	if (!blpSrc) {
		getLog().warnOnce(
			`miss-tex:${raw}`,
			`缺少贴图: ${raw} → 占位`,
			`BLP not found under extract root; using _placeholders/missing.png`,
		);
		const pngLogicalPh = "_placeholders/missing.png";
		const dest = path.join(outDir, ...pngLogicalPh.split("/"));
		if (!fs.existsSync(dest)) writePlaceholderPng(dest, [255, 0, 0, 255]);
		return {
			pngLogical: pngLogicalPh,
			pngBytes: fs.readFileSync(dest),
			isReplaceable,
			replaceableId: replaceableId || 0,
		};
	}

	const pngBytes = blpBufferToPng(fs.readFileSync(blpSrc));
	fs.mkdirSync(path.dirname(pngDest), { recursive: true });
	fs.writeFileSync(pngDest, pngBytes);
	return {
		pngLogical,
		pngBytes,
		isReplaceable,
		replaceableId: replaceableId || 0,
	};
}

function textureIdOfLayer(layer) {
	const tid = layer?.TextureID;
	return typeof tid === "number" ? tid : 0;
}

/**
 * Pick the best diffuse layer: prefer a layer with a real Image path.
 * Fixes team-color-first materials (Layer0=Replaceable, Layer1=Footman.blp).
 */
function pickDiffuseLayer(matDef, textures) {
	const layers = matDef?.Layers ?? [];
	for (const layer of layers) {
		const tid = textureIdOfLayer(layer);
		const tex = textures?.[tid];
		if (tex?.Image) {
			return { layer, textureId: tid, replaceableId: tex.ReplaceableId || 0 };
		}
	}
	const layer = layers[0] ?? {};
	const tid = textureIdOfLayer(layer);
	const tex = textures?.[tid];
	return { layer, textureId: tid, replaceableId: tex?.ReplaceableId || 0 };
}

/**
 * WC3 常见：Layer0=ReplaceableId1（队色）+ Layer1=漫反射 Blend。
 * 队色从透明处透出；convert 取漫反射层时仍须标 rep1，供 Godot 垫底混合。
 */
function materialHasTeamColorUnderlay(matDef, textures) {
	const layers = matDef?.Layers ?? [];
	let hasRep1 = false;
	let hasImage = false;
	for (const layer of layers) {
		const tex = textures?.[textureIdOfLayer(layer)];
		if (!tex) continue;
		const rid = tex.ReplaceableId || 0;
		if (rid === 1 && !tex.Image) hasRep1 = true;
		if (tex.Image) hasImage = true;
	}
	return hasRep1 && hasImage;
}

function alphaModeForFilter(filterMode) {
  // WC3: 0 None, 1 Transparent, 2 Blend, 3 Additive, 4 AddAlpha, 5 Modulate, 6 Modulate2x
  // Godot 里 BLEND 会进透明队列导致建筑透视；仍导出 BLEND，由 MapModelCache 改 DEPTH_PRE_PASS。
  // Additive 无 glTF 对应：BLEND + 材质名 _fm3/_fm4，Godot 再改 ADD。
  if (filterMode === 0) return "OPAQUE";
  if (filterMode === 1) return "MASK";
  return "BLEND";
}

function alphaCutoffForFilter(filterMode) {
  // Match war3-model discard threshold for Transparent layers (~0.75).
  return filterMode === 1 ? 0.75 : 0.5;
}

/** @param {number} filterMode */
function isAdditiveFilter(filterMode) {
  return filterMode === 3 || filterMode === 4;
}

/** MDX Layer.Shading bit 4 (16) = TwoSided；勿默认双面，否则屋顶背面透出来发黑。
 *  FilterMode Transparent(1) 例外：袍/披风多为单面壳，强制双面（否则 Godot cull_back 前胸镂空）。 */
function isTwoSidedLayer(layer) {
  const filterMode = Number(layer?.FilterMode) || 0;
  if (filterMode === 1) return true;
  const shading = Number(layer?.Shading ?? layer?.Flags ?? 0) || 0;
  return (shading & 16) !== 0;
}

function transformMat4Wc3ToGltf(m) {
  // Apply basis change B * M * B^-1 for column-major M, B:(x,y,z)->(x,z,-y)
  // Faster: transform translation and rebuild from decomposed TRS.
  const { t, r, s } = mat4DecomposeTRS(m);
  const tg = wc3ToGltfVec3(t[0], t[1], t[2]);
  const rg = wc3ToGltfQuat(r[0], r[1], r[2], r[3]);
  // Scale axes permute with basis: (sx,sy,sz)_wc3 -> (sx,sz,sy)
  const sg = [s[0], s[2], s[1]];
  return { t: tg, r: rg, s: sg };
}

function quatNearlyEqual(a, b) {
  const dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
  return Math.abs(Math.abs(dot) - 1) < 2e-3;
}

/** 循环段拉长后，静止骨骼不必每 33ms 写一帧。 */
function collapseConstantTrsTrack(track) {
  const n = track.times.length;
  if (n <= 2) return track;
  const t0 = [track.t[0], track.t[1], track.t[2]];
  const r0 = [track.r[0], track.r[1], track.r[2], track.r[3]];
  const s0 = [track.s[0], track.s[1], track.s[2]];
  for (let i = 1; i < n; i += 1) {
    const ri = [track.r[i * 4], track.r[i * 4 + 1], track.r[i * 4 + 2], track.r[i * 4 + 3]];
    if (
      Math.abs(track.t[i * 3] - t0[0]) > 0.05 ||
      Math.abs(track.t[i * 3 + 1] - t0[1]) > 0.05 ||
      Math.abs(track.t[i * 3 + 2] - t0[2]) > 0.05 ||
      !quatNearlyEqual(r0, ri) ||
      Math.abs(track.s[i * 3] - s0[0]) > 1e-3 ||
      Math.abs(track.s[i * 3 + 1] - s0[1]) > 1e-3 ||
      Math.abs(track.s[i * 3 + 2] - s0[2]) > 1e-3
    ) {
      return track;
    }
  }
  const last = n - 1;
  return {
    times: [track.times[0], track.times[last]],
    t: [t0[0], t0[1], t0[2], track.t[last * 3], track.t[last * 3 + 1], track.t[last * 3 + 2]],
    r: [...r0, track.r[last * 4], track.r[last * 4 + 1], track.r[last * 4 + 2], track.r[last * 4 + 3]],
    s: [s0[0], s0[1], s0[2], track.s[last * 3], track.s[last * 3 + 1], track.s[last * 3 + 2]],
  };
}

function collapseConstantScaleTrack(track) {
  const n = track.times.length;
  if (n <= 2) return track;
  const s0 = track.s[0];
  for (let i = 1; i < n; i += 1) {
    if (Math.abs(track.s[i * 3] - s0) > 1e-6) return track;
  }
  const last = n - 1;
  return {
    times: [track.times[0], track.times[last]],
    s: [
      track.s[0],
      track.s[1],
      track.s[2],
      track.s[last * 3],
      track.s[last * 3 + 1],
      track.s[last * 3 + 2],
    ],
  };
}

/**
 * @param {string} absPath
 * @param {string} logicalPath
 * @param {string} inDir
 * @param {string} outDir
 */
export async function convertOneMdx(absPath, logicalPath, inDir, outDir) {
  const model = parseModel(fs.readFileSync(absPath), logicalPath);
  const document = new Document();
  const buffer = document.createBuffer();

  const rootName = path.basename(logicalPath, path.extname(logicalPath));
  const root = document.createNode(rootName).setScale([MODEL_SCALE, MODEL_SCALE, MODEL_SCALE]);
  const scene = document.createScene(logicalPath).addChild(root);

  /** @type {Map<number, import('@gltf-transform/core').Texture>} */
  const textureCache = new Map();
  /** @type {Map<number, import('@gltf-transform/core').Material>} */
  const materialCache = new Map();

  // 方案 B：.gltf + 外部 URI 指向 assets/asset-converted/Textures|… 下唯一 PNG。
  // 不再 setImage embed（GLB 规范强制内嵌，无法跨模型共享）。
  const gltfLogical = mdxLogicalToGltf(logicalPath);

  function getTexture(textureId) {
    if (textureCache.has(textureId)) return textureCache.get(textureId);
    const texInfo = model.Textures?.[textureId];
    const resolved = resolveTexturePng(texInfo?.Image ?? "", inDir, outDir, {
      isReplaceable: Boolean(texInfo?.ReplaceableId),
      replaceableId: texInfo?.ReplaceableId || 0,
    });
    const uri = uriFromModelToPng(gltfLogical, resolved.pngLogical);
    // 必须同时 setImage + setURI：仅 URI 会被 writer 丢弃；
    // 有二者时 .gltf writer 把图写到 uri 路径（canonical 已在 Textures/ 则覆盖同文件）。
    const texture = document
      .createTexture(resolved.pngLogical)
      .setMimeType("image/png")
      .setImage(resolved.pngBytes)
      .setURI(uri);
    textureCache.set(textureId, texture);
    return texture;
  }

	function getMaterial(materialId) {
		if (materialCache.has(materialId)) return materialCache.get(materialId);
		const matDef = model.Materials?.[materialId];
		const picked = pickDiffuseLayer(matDef, model.Textures);
		let filterMode = picked.layer?.FilterMode ?? 0;
		const teamUnderlay = materialHasTeamColorUnderlay(matDef, model.Textures);
		// 双层队色垫底：漫反射层本身 Rep=0，仍标 rep1 供运行时混合
		let replaceableId = picked.replaceableId || 0;
		if (teamUnderlay) {
			replaceableId = 1;
		}
		// Team Glow 在 MDX 里几乎总是 Additive；若数据异常也强制按光晕处理
		if (replaceableId === 2 && !isAdditiveFilter(filterMode)) {
			filterMode = 3;
		}
		// 名称带 _fmN / _repN，供 Godot 识别 Additive 与队伍色/光晕
		const material = document
			.createMaterial(`Material_${materialId}_fm${filterMode}_rep${replaceableId}`)
			.setDoubleSided(isTwoSidedLayer(picked.layer))
			.setAlphaMode(alphaModeForFilter(filterMode))
			.setAlphaCutoff(alphaCutoffForFilter(filterMode))
			.setMetallicFactor(0)
			.setRoughnessFactor(1);
		material.setExtras({
			wc3FilterMode: filterMode,
			wc3Additive: isAdditiveFilter(filterMode),
			wc3ReplaceableId: replaceableId,
			wc3TeamGlow: replaceableId === 2,
			wc3TeamColorUnderlay: teamUnderlay,
			wc3TwoSided: isTwoSidedLayer(picked.layer),
		});
		material.setBaseColorTexture(getTexture(picked.textureId));
		if (isAdditiveFilter(filterMode)) {
			// 略提亮，逼近 WC3 Additive 光晕
			material.setEmissiveFactor([0.15, 0.15, 0.1]);
		}
		materialCache.set(materialId, material);
		return material;
	}

  // --- Skeleton (flat under Armature; IBM = I to match WC3 model-space skinning) ---
  // Bones 必须先入 joint 列表，保持已有 JOINTS_0 下标 0..Bones-1；Helpers 去重后追加。
  const boneNodes = model.Bones ?? [];
  const allNodes = model.Nodes ?? [];
  const helperJoints = extraHelperNodes(model, boneNodes);
  const skinAnimNodes = [...boneNodes, ...helperJoints];
  const armature = document.createNode("Armature");
  root.addChild(armature);

  /** @type {Map<number, import('@gltf-transform/core').Node>} */
  const jointByObjectId = new Map();
  /** @type {import('@gltf-transform/core').Node[]} */
  const jointList = [];
  const usedJointNames = new Set();

  // WC3 PivotPoint 是「旋转原点」。每个 joint 在父坐标系里的偏移 = 父 Pivot − 子 Pivot。
  // glTF joint node.translation 在 skin 场景下不被保留（IBM 才携带 chain 信息），
  // 我们把 chain 累计的 translation 写进 IBM：vertex_final = vertex_model × jointTRS × IBM，
  // IBM = inv(globalJointT) ⇒ vertex_final = vertex_model × jointTRS / globalJointT，
  // 即 jointTRS 应用到 joint-local vertex。
  const nodeByObjectId = (id) => {
    if (id == null) return null;
    for (const n of allNodes ?? []) {
      if (n && n.ObjectId === id) return n;
    }
    return null;
  };
  const jointLocalT = new Map(); // ObjectId → gltf vec3（与顶点同空间，不含根 scale）
  const jointParent = new Map(); // ObjectId → parent ObjectId
  const DBG_JOINT = globalThis.__WC3_DEBUG_JOINT === true;
  for (const src of skinAnimNodes) {
    const parentId = src.Parent;
    jointParent.set(src.ObjectId, parentId);
    const gp = parentId != null ? nodeByObjectId(parentId) : null;
    const t = bakePivotDeltaGltf(src.PivotPoint, gp?.PivotPoint ?? [0, 0, 0]);
    jointLocalT.set(src.ObjectId, t);
  }
  if (DBG_JOINT) {
    for (const src of skinAnimNodes.slice(0, 5)) {
      const t = jointLocalT.get(src.ObjectId);
      console.log("[joint]", src.Name || src.ObjectId, "t=", t);
    }
    console.log("[joint] total skinAnimNodes=", skinAnimNodes.length, "jointLocalT size=", jointLocalT.size);
  }

  for (const src of skinAnimNodes) {
    const joint = document.createNode(uniqueJointName(src, usedJointNames));
    // 不要 setTranslation：Godot 若把它收成 bone rest，而顶点已是 model space、IBM=I，
    // 蒙皮会再加一遍局部平移，骑士叠进马身。joint 保持原点，绑定网格即 MDX 外形。
    jointByObjectId.set(src.ObjectId, joint);
    jointList.push(joint);
    armature.addChild(joint);
  }

  const skin =
    jointList.length > 0
      ? document.createSkin("Skin").setSkeleton(armature)
      : null;

  /** @type {Map<number, Float32Array>} */
  const globalJointT = new Map();
  /** @param {number} oid @returns {Float32Array} */
  const computeGlobal = (oid) => {
    const cached = globalJointT.get(oid);
    if (cached) return cached;
    const t = jointLocalT.get(oid) ?? [0, 0, 0];
    const pid = jointParent.get(oid);
    const parGlobal = pid != null ? computeGlobal(pid) : null;
    const out = new Float32Array(16);
    if (parGlobal) {
      out.set(parGlobal);
      out[12] = parGlobal[0] * t[0] + parGlobal[4] * t[1] + parGlobal[8] * t[2] + parGlobal[12];
      out[13] = parGlobal[1] * t[0] + parGlobal[5] * t[1] + parGlobal[9] * t[2] + parGlobal[13];
      out[14] = parGlobal[2] * t[0] + parGlobal[6] * t[1] + parGlobal[10] * t[2] + parGlobal[14];
    } else {
      out[0] = 1; out[5] = 1; out[10] = 1; out[15] = 1;
      out[12] = t[0]; out[13] = t[1]; out[14] = t[2];
    }
    globalJointT.set(oid, out);
    return out;
  };
  for (const src of skinAnimNodes) computeGlobal(src.ObjectId);

  if (skin) {
    // Godot 导入 skinned mesh 时 joint rest=I。IBM 必须是单位阵，否则
    // pose=I、IBM=inv(bind) 会把绑定姿态顶点减回原点（网格堆成一团）。
    const ibmData = new Float32Array(jointList.length * 16);
    for (let i = 0; i < jointList.length; i += 1) {
      ibmData.set(mat4Identity(), i * 16);
      skin.addJoint(jointList[i]);
    }
    skin.setInverseBindMatrices(
      document
        .createAccessor("IBM")
        .setType("MAT4")
        .setArray(ibmData)
        .setBuffer(buffer),
    );
  }

  const objectIdToJointIndex = new Map();
  skinAnimNodes.forEach((b, i) => objectIdToJointIndex.set(b.ObjectId, i));

  // --- Geosets ---
  // Godot GLTFDocument drops TRS on skinned mesh nodes; visibility for Godot is
  // written to *.geosetvis.json and injected as :visible during load/bake.
  // GLB still carries Geoset_* scale channels for non-Godot glTF consumers.
  const geosets = model.Geosets ?? [];
  /** @type {Map<number, import('@gltf-transform/core').Node>} */
  const geosetMeshNodes = new Map();
  const restSeq = model.Sequences?.[0];
  const restStart = restSeq?.Interval?.[0] ?? 0;
  const restEnd = restSeq?.Interval?.[1] ?? restStart;
  const restFrame = restStart;

	for (let gi = 0; gi < geosets.length; gi += 1) {
		const g = geosets[gi];
		const vertCount = (g.Vertices?.length ?? 0) / 3;
		if (!vertCount || !g.Faces?.length) continue;

		const positions = new Float32Array(vertCount * 3);
    const normals = new Float32Array(vertCount * 3);
    const uvs = new Float32Array(vertCount * 2);
    const joints = new Uint16Array(vertCount * 4);
    const weights = new Float32Array(vertCount * 4);

    for (let i = 0; i < vertCount; i += 1) {
      const x = g.Vertices[i * 3];
      const y = g.Vertices[i * 3 + 1];
      const z = g.Vertices[i * 3 + 2];
      const p = wc3ToGltfVec3(x, y, z);
      // 顶点保持 model space。Godot rest=I + IBM=I 时视觉即绑定姿态。
      positions[i * 3] = p[0];
      positions[i * 3 + 1] = p[1];
      positions[i * 3 + 2] = p[2];
      const group = g.Groups?.[g.VertexGroup?.[i] ?? 0] ?? [];

      if (g.Normals?.length >= (i + 1) * 3) {
        const n = wc3ToGltfVec3(g.Normals[i * 3], g.Normals[i * 3 + 1], g.Normals[i * 3 + 2]);
        normals[i * 3] = n[0];
        normals[i * 3 + 1] = n[1];
        normals[i * 3 + 2] = n[2];
      } else {
        normals[i * 3 + 1] = 1;
      }

      const tv = g.TVertices?.[0];
      if (tv && tv.length >= (i + 1) * 2) {
        // Do NOT flip V — war3-model uploads raw TVertices to WebGL/glTF-like V=0 bottom space.
        uvs[i * 2] = tv[i * 2];
        uvs[i * 2 + 1] = tv[i * 2 + 1];
      }

      // Skin weights from matrix groups (equal weight, up to 4).
      const usable = group
        .map((objectId) => objectIdToJointIndex.get(objectId))
        .filter((idx) => idx !== undefined);
      const count = Math.min(4, usable.length || 0);
      const w = count > 0 ? 1 / count : 1;
      for (let k = 0; k < 4; k += 1) {
        joints[i * 4 + k] = count > 0 && k < count ? usable[k] : 0;
        weights[i * 4 + k] = count > 0 && k < count ? w : k === 0 ? 1 : 0;
      }
    }

    // Keep original winding — with (x,z,-y) this matches WC3 front faces in practice for most units.
    const indices = Uint32Array.from(g.Faces);

    const prim = document
      .createPrimitive()
      .setAttribute(
        "POSITION",
        document.createAccessor().setType("VEC3").setArray(positions).setBuffer(buffer),
      )
      .setAttribute(
        "NORMAL",
        document.createAccessor().setType("VEC3").setArray(normals).setBuffer(buffer),
      )
      .setAttribute(
        "TEXCOORD_0",
        document.createAccessor().setType("VEC2").setArray(uvs).setBuffer(buffer),
      )
      .setIndices(
        document.createAccessor().setType("SCALAR").setArray(indices).setBuffer(buffer),
      )
      .setMaterial(getMaterial(g.MaterialID ?? 0));

    if (skin && jointList.length > 0) {
      prim
        .setAttribute(
          "JOINTS_0",
          document.createAccessor().setType("VEC4").setArray(joints).setBuffer(buffer),
        )
        .setAttribute(
          "WEIGHTS_0",
          document.createAccessor().setType("VEC4").setArray(weights).setBuffer(buffer),
        );
    }

    const mesh = document.createMesh(`Geoset_${gi}`).addPrimitive(prim);
    const meshNode = document.createNode(`Geoset_${gi}`).setMesh(mesh);
    if (skin) meshNode.setSkin(skin);

    // Hide geosets that WC3 keeps invisible at rest (sequence-scoped).
    const restAlpha = sampleGeosetAlphaInSequence(
      model.GeosetAnims,
      gi,
      restFrame,
      restStart,
      restEnd,
    );
    if (restAlpha < 0.5) {
      meshNode.setScale([0, 0, 0]);
    }
    geosetMeshNodes.set(gi, meshNode);
    root.addChild(meshNode);
  }

  // --- Animations (one glTF animation per WC3 Sequence) ---
  // Global Sequence（旗/钟）不跟 Sequence 区间走：循环段烘焙时长拉到最长 GlobalSeq，
  // 段内骨骼 % seqDur，GlobalSeq 骨骼 % globalDur。MDX Billboard 位（0x8）原样保留，
  // 不在烘焙时改朝向（RTS 固定机位；旗布也不是 TwoSided）。
  const globalSequences = (model.GlobalSequences ?? []).map((d) => Number(d) || 0);
  const bindSeq =
    (model.Sequences ?? []).find((s) => /^stand/i.test(String(s.Name || "").trim())) || restSeq;
  const bindStart = bindSeq?.Interval?.[0] ?? restStart;
  const bindEnd = bindSeq?.Interval?.[1] ?? restEnd;
  const bindWorlds = evaluateNodeWorldMatrices(
    allNodes,
    bindStart,
    bindStart,
    bindEnd,
    globalSequences,
    0,
  );
  if (model.Sequences?.length) {
    for (const seq of model.Sequences) {
      const start = seq.Interval[0];
      const end = seq.Interval[1];
      if (end <= start) continue;
      const seqDur = end - start;
      const looping = !seq.NonLooping;
      const bakeDur = sequenceBakeDurationMs(
        start,
        end,
        looping,
        allNodes,
        globalSequences,
      );

      const animName = wc3SequenceToAnimName(seq.Name || "Anim");
      const animation = document.createAnimation(animName);
      const frames = collectBakeFrames(
        allNodes,
        start,
        end,
        bakeDur,
        33,
        model.GeosetAnims || [],
        globalSequences,
      );

      /** @type {Map<number, { times: number[], t: number[], r: number[], s: number[] }>} */
      const tracks = new Map();
      for (const bone of skinAnimNodes) {
        tracks.set(bone.ObjectId, { times: [], t: [], r: [], s: [] });
      }

      /** @type {Map<number, { times: number[], s: number[] }>} */
      const geosetScaleTracks = new Map();
      for (const gi of geosetMeshNodes.keys()) {
        geosetScaleTracks.set(gi, { times: [], s: [] });
      }

      const seqNameRaw = String(seq.Name || "");
      const morphFamily = isAlternateOrMorphSequenceName(seqNameRaw);
      const isMorphSeq = /^\s*morph\b/i.test(seqNameRaw.trim());

      for (const tMs of frames) {
        const seqFrame =
          looping && seqDur > 0 ? start + (tMs % seqDur) : start + tMs;
        const morphLerp =
          isMorphSeq && seqDur > 0
            ? Math.min(1, Math.max(0, (seqFrame - start) / seqDur))
            : null;
        const worlds = evaluateNodeWorldMatrices(
          allNodes,
          seqFrame,
          start,
          end,
          globalSequences,
          tMs,
          {
            carryInScaling: morphFamily && !isMorphSeq,
            morphScaleLerp: morphLerp,
          },
        );
        const timeSec = tMs / 1000;
        for (const bone of skinAnimNodes) {
          const world = worlds[bone.ObjectId] || mat4Identity();
          // Godot 4.6 平铺骨骼：global_pose≈pose（rest 不参与蒙皮）。
          // pose 必须写 WC3 世界阵；相对 Stand 的 delta 会在播动画时把骑士打回 T-pose。
          const { t, r, s } = transformMat4Wc3ToGltf(world);
          const track = tracks.get(bone.ObjectId);
          track.times.push(timeSec);
          track.t.push(t[0], t[1], t[2]);
          track.r.push(r[0], r[1], r[2], r[3]);
          track.s.push(s[0], s[1], s[2]);
        }

        for (const gi of geosetMeshNodes.keys()) {
          const alphaRaw = sampleGeosetAlphaInSequence(
            model.GeosetAnims,
            gi,
            seqFrame,
            start,
            end,
          );
          const alphaNorm = normalizeGeosetAlpha(alphaRaw);
          const gTrack = geosetScaleTracks.get(gi);
          gTrack.times.push(timeSec);
          gTrack.s.push(alphaNorm, alphaNorm, alphaNorm);
        }
      }

      for (const bone of skinAnimNodes) {
        const joint = jointByObjectId.get(bone.ObjectId);
        let track = tracks.get(bone.ObjectId);
        if (!joint || !track?.times.length) continue;
        track = collapseConstantTrsTrack(track);

        const input = document
          .createAccessor(`${animName}_${bone.ObjectId}_time`)
          .setType("SCALAR")
          .setArray(new Float32Array(track.times))
          .setBuffer(buffer);

        const tOut = document
          .createAccessor(`${animName}_${bone.ObjectId}_t`)
          .setType("VEC3")
          .setArray(new Float32Array(track.t))
          .setBuffer(buffer);
        const rOut = document
          .createAccessor(`${animName}_${bone.ObjectId}_r`)
          .setType("VEC4")
          .setArray(new Float32Array(track.r))
          .setBuffer(buffer);
        const sOut = document
          .createAccessor(`${animName}_${bone.ObjectId}_s`)
          .setType("VEC3")
          .setArray(new Float32Array(track.s))
          .setBuffer(buffer);

        // glTF-Transform requires samplers to be attached to the Animation
        // via addSampler(); otherwise channels are written without sampler
        // indices and Godot rejects the GLB.
        const tSampler = document
          .createAnimationSampler()
          .setInterpolation("LINEAR")
          .setInput(input)
          .setOutput(tOut);
        const rSampler = document
          .createAnimationSampler()
          .setInterpolation("LINEAR")
          .setInput(input)
          .setOutput(rOut);
        const sSampler = document
          .createAnimationSampler()
          .setInterpolation("LINEAR")
          .setInput(input)
          .setOutput(sOut);

        animation.addSampler(tSampler).addSampler(rSampler).addSampler(sSampler);
        animation
          .addChannel(
            document
              .createAnimationChannel()
              .setTargetNode(joint)
              .setTargetPath("translation")
              .setSampler(tSampler),
          )
          .addChannel(
            document
              .createAnimationChannel()
              .setTargetNode(joint)
              .setTargetPath("rotation")
              .setSampler(rSampler),
          )
          .addChannel(
            document
              .createAnimationChannel()
              .setTargetNode(joint)
              .setTargetPath("scale")
              .setSampler(sSampler),
          );
      }

      // Drive geoset visibility (WC3 GeosetAnim alpha) via node scale.
      // Godot drops these on skinned meshes — see writeGeosetVisSidecar.
      for (const [gi, meshNode] of geosetMeshNodes) {
        let gTrack = geosetScaleTracks.get(gi);
        if (!gTrack?.times.length) continue;
        gTrack = collapseConstantScaleTrack(gTrack);
        const input = document
          .createAccessor(`${animName}_geoset${gi}_time`)
          .setType("SCALAR")
          .setArray(new Float32Array(gTrack.times))
          .setBuffer(buffer);
        const sOut = document
          .createAccessor(`${animName}_geoset${gi}_s`)
          .setType("VEC3")
          .setArray(new Float32Array(gTrack.s))
          .setBuffer(buffer);
        const sSampler = document
          .createAnimationSampler()
          .setInterpolation("STEP")
          .setInput(input)
          .setOutput(sOut);
        animation.addSampler(sSampler);
        animation.addChannel(
          document
            .createAnimationChannel()
            .setTargetNode(meshNode)
            .setTargetPath("scale")
            .setSampler(sSampler),
        );
      }
    }
  }

  document.getRoot().setDefaultScene(scene);

  const dest = path.join(outDir, ...gltfLogical.split("/"));
  const destBin = dest.replace(/\.gltf$/i, ".bin");
  const pe2Dest = path.join(outDir, ...mdxLogicalToPe2(logicalPath).split("/"));
  const geosetVisDest = path.join(
    outDir,
    ...mdxLogicalToGeosetVis(logicalPath).split("/"),
  );
  const attDest = path.join(
    outDir,
    ...mdxLogicalToAttachments(logicalPath).split("/"),
  );
  const camDest = path.join(
    outDir,
    ...mdxLogicalToCameras(logicalPath).split("/"),
  );
  const animKeysDest = path.join(
    outDir,
    ...mdxLogicalToAnimKeys(logicalPath).split("/"),
  );
  const collisionDest = path.join(
    outDir,
    ...mdxLogicalToCollision(logicalPath).split("/"),
  );
  const boneRestDest = path.join(
    outDir,
    ...mdxLogicalToBoneRest(logicalPath).split("/"),
  );
  fs.mkdirSync(path.dirname(dest), { recursive: true });

  // 直接写最终路径（避免 .partial.bin 写进 buffers[].uri）。
  // sidecar 先写；gltf/bin 后写。中途失败清掉本模型产物。
  try {
    writePe2Sidecar(model, logicalPath, inDir, outDir);
    writeGeosetVisSidecar(model, logicalPath, outDir, geosetMeshNodes.keys());
    writeAttachmentsSidecar(model, logicalPath, outDir);
    writeCamerasSidecar(model, logicalPath, outDir);
    writeAnimKeysSidecar(model, logicalPath, outDir);
    writeCollisionSidecar(model, logicalPath, outDir);
    writeBoneRestSidecar(skinAnimNodes, bindWorlds, jointList, logicalPath, outDir);
    await new NodeIO().write(dest, document);
    unlinkQuiet(dest.replace(/\.gltf$/i, ".glb"));
  } catch (err) {
    unlinkQuiet(dest);
    unlinkQuiet(destBin);
    unlinkQuiet(pe2Dest);
    unlinkQuiet(geosetVisDest);
    unlinkQuiet(attDest);
    unlinkQuiet(camDest);
    unlinkQuiet(animKeysDest);
    unlinkQuiet(collisionDest);
    unlinkQuiet(boneRestDest);
    throw err;
  }
  return dest;
}

export async function convertMdxBatch(options) {
  const { inDir, outDir, force, include, exclude } = options;
  const files = walkFiles(inDir, new Set([".mdx", ".mdl"]), include, exclude);

  let converted = 0;
  let skipped = 0;
  let errors = 0;

  const log = getLog();
  log.info(`\n[models] 发现 ${files.length} 个 .mdx/.mdl`);

  const t0 = Date.now();
  let processed = 0;
  for (const file of files) {
    const gltfLogical = mdxLogicalToGltf(file.logicalPath);
    const dest = path.join(outDir, ...gltfLogical.split("/"));
    const pe2Dest = path.join(outDir, ...mdxLogicalToPe2(file.logicalPath).split("/"));
    const geosetVisDest = path.join(
      outDir,
      ...mdxLogicalToGeosetVis(file.logicalPath).split("/"),
    );
    const camDest = path.join(
      outDir,
      ...mdxLogicalToCameras(file.logicalPath).split("/"),
    );
    const collisionDest = path.join(
      outDir,
      ...mdxLogicalToCollision(file.logicalPath).split("/"),
    );

    if (
      !force &&
      fs.existsSync(dest) &&
      fs.existsSync(pe2Dest) &&
      fs.existsSync(geosetVisDest) &&
      fs.existsSync(camDest) &&
      fs.existsSync(collisionDest)
    ) {
      const srcStat = fs.statSync(file.absPath);
      const dstStat = fs.statSync(dest);
      const pe2Stat = fs.statSync(pe2Dest);
      const visStat = fs.statSync(geosetVisDest);
      const camStat = fs.statSync(camDest);
      const collisionStat = fs.statSync(collisionDest);
      const valid = isValidGltfOnDisk(dest);
      if (
        dstStat.mtimeMs >= srcStat.mtimeMs &&
        dstStat.size > 0 &&
        valid &&
        pe2Stat.mtimeMs >= srcStat.mtimeMs &&
        visStat.mtimeMs >= srcStat.mtimeMs &&
        camStat.mtimeMs >= srcStat.mtimeMs &&
        collisionStat.mtimeMs >= srcStat.mtimeMs
      ) {
        skipped += 1;
        processed += 1;
        if (processed % 50 === 0 || processed === files.length) {
          const sec = ((Date.now() - t0) / 1000).toFixed(1);
          log.progress(
            `[models] progress ${processed}/${files.length} converted=${converted} skipped=${skipped} errors=${errors} (${sec}s)`,
          );
        }
        continue;
      }
      if (!valid && dstStat.size > 0) {
        unlinkQuiet(dest);
        unlinkQuiet(dest.replace(/\.gltf$/i, ".bin"));
      }
    }

    try {
      await convertOneMdx(file.absPath, file.logicalPath, inDir, outDir);
      converted += 1;
    } catch (err) {
      const brief = `失败 ${file.logicalPath}: ${err instanceof Error ? err.message : err}`;
      log.error(brief, err);
      errors += 1;
    }
    processed += 1;
    if (processed % 50 === 0 || processed === files.length) {
      const sec = ((Date.now() - t0) / 1000).toFixed(1);
      log.progress(
        `[models] progress ${processed}/${files.length} converted=${converted} skipped=${skipped} errors=${errors} (${sec}s)`,
      );
    }
  }

  log.info(`[models] 完成: 转换 ${converted}, 跳过 ${skipped}, 错误 ${errors}`);
  return { converted, skipped, errors, fileCount: files.length };
}
