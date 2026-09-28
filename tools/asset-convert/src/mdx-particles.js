import path from "node:path";
import { evaluateNodeWorldMatrices } from "./anim.js";
import { wc3ToGltfVec3 } from "./mat4.js";
import { mdxLogicalToPe2, normalizeLogicalPath } from "./paths.js";
import { atomicWriteBytesSync } from "./atomic-write.js";

import { MODEL_SCALE, asVec3 } from "./mdx-values.js";
import { resolveTexturePng } from "./mdx-materials.js";

/**
 * Animated track → [{frame,value}]；静态 number → null。
 * @param {unknown} track
 * @returns {Array<{ frame: number, value: number }> | null}
 */
export function animTrackKeys(track) {
  if (track == null || typeof track === "number") return null;
  const keys = /** @type {{ Keys?: Array<{ Frame: number, Vector: ArrayLike<number> }> }} */ (
    track
  ).Keys;
  if (!keys?.length) return null;
  return keys.map((k) => ({
    frame: Number(k.Frame) || 0,
    value: Number(k.Vector?.[0]) || 0,
    ...(k.InTan ? { in_tan: Number(k.InTan[0]) || 0 } : {}),
    ...(k.OutTan ? { out_tan: Number(k.OutTan[0]) || 0 } : {}),
  }));
}

/**
 * @param {Array<{ frame: number, value: number }> | null} keys
 * @param {number} frame
 * @param {number} seqStart
 * @param {number} seqEnd
 * @param {number} defaultValue 区间内无 key 时的默认（Visibility=1，EmissionRate=0）
 */
export function sampleTrackInSequence(keys, frame, seqStart, seqEnd, defaultValue) {
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
export function emissionRateForAmount(track) {
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
export function activeSequencesForEmitter(pe, sequences) {
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
export function _emitterActiveInSequence(visKeys, rateKeys, staticRate, start, end) {
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
  // vis 轨峰值始终 <0.5（金矿塌陷烟等）：只按 rate 判定，避免 empty active → 运行时误开 Stand。
  const visInert =
    Array.isArray(visKeys) &&
    visKeys.length > 0 &&
    Math.max(0, ...visKeys.map((k) => Number(k.value) || 0)) < 0.5;
  const rateOnly = visInert && hasAnimRate;
  for (const frame of sampleFrames) {
    const vis = sampleTrackInSequence(visKeys, frame, start, end, 1);
    const rate = hasAnimRate
      ? sampleTrackInSequence(rateKeys, frame, start, end, 0)
      : staticRate != null
        ? staticRate
        : sampleTrackInSequence(rateKeys, frame, start, end, 0);
    if (rateOnly) {
      if (rate > 0.01) return true;
    } else if (vis >= 0.5 && rate > 0.01) {
      return true;
    }
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
export function writePe2Sidecar(model, logicalPath, inDir, outDir) {
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
      emission_rate_interpolation: Number(pe.EmissionRate?.LineType) || 0,
      width: typeof pe.Width === "number" ? pe.Width : Number(pe.Width) || 0,
      length: typeof pe.Length === "number" ? pe.Length : Number(pe.Length) || 0,
      filter_mode: Number(pe.FilterMode) || 0,
      rows: Math.max(1, Number(pe.Rows) || 1),
      columns: Math.max(1, Number(pe.Columns) || 1),
      frame_flags: Number(pe.FrameFlags ?? pe.HeadOrTail) || 0,
      tail_length: Number(pe.TailLength) || 0,
      squirt: Boolean(pe.Squirt),
      time_middle: Number(pe.Time ?? 0.5),
      segment_color: [asVec3(seg[0]), asVec3(seg[1]), asVec3(seg[2])],
      alpha: asVec3(pe.Alpha),
      particle_scaling: asVec3(pe.ParticleScaling),
      life_span_uv: asVec3(pe.LifeSpanUVAnim),
      decay_uv: asVec3(pe.DecayUVAnim),
      tail_uv: asVec3(pe.TailUVAnim),
      tail_decay_uv: asVec3(pe.TailDecayUVAnim),
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
export function bakePivotDeltaGltf(childPivot, parentPivot) {
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
export function bakePe2LocalPivot(allNodes, pe) {
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
export function bakePe2PivotsBySequence(allNodes, pe, sequences) {
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
