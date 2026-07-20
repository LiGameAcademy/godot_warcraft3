import {
  mat4FromRotationTranslationScaleOrigin,
  mat4Identity,
  mat4Multiply,
} from "./mat4.js";

const DEFAULT_T = new Float32Array([0, 0, 0]);
const DEFAULT_R = new Float32Array([0, 0, 0, 1]);
const DEFAULT_S = new Float32Array([1, 1, 1]);

/**
 * Interpolate AnimVector at frame (WC3 millis). Linear between keys; clamp outside.
 * @param {import('war3-model').AnimVector | undefined} anim
 * @param {number} frame
 * @param {Float32Array} fallback
 * @returns {Float32Array}
 */
export function sampleAnimVector(anim, frame, fallback) {
  if (!anim?.Keys?.length) return fallback;
  const keys = anim.Keys;
  if (frame <= keys[0].Frame) return keys[0].Vector;
  if (frame >= keys[keys.length - 1].Frame) return keys[keys.length - 1].Vector;

  let i = 1;
  while (i < keys.length && keys[i].Frame < frame) i += 1;
  const a = keys[i - 1];
  const b = keys[i];
  const span = b.Frame - a.Frame || 1;
  const t = (frame - a.Frame) / span;

  const out = new Float32Array(a.Vector.length);
  // Quaternions: nlerp (good enough for export)
  if (a.Vector.length === 4) {
    let ax = a.Vector[0], ay = a.Vector[1], az = a.Vector[2], aw = a.Vector[3];
    let bx = b.Vector[0], by = b.Vector[1], bz = b.Vector[2], bw = b.Vector[3];
    if (ax * bx + ay * by + az * bz + aw * bw < 0) {
      bx = -bx; by = -by; bz = -bz; bw = -bw;
    }
    out[0] = ax + (bx - ax) * t;
    out[1] = ay + (by - ay) * t;
    out[2] = az + (bz - az) * t;
    out[3] = aw + (bw - aw) * t;
    const len = Math.hypot(out[0], out[1], out[2], out[3]) || 1;
    out[0] /= len; out[1] /= len; out[2] /= len; out[3] /= len;
    return out;
  }

  for (let c = 0; c < a.Vector.length; c += 1) {
    out[c] = a.Vector[c] + (b.Vector[c] - a.Vector[c]) * t;
  }
  return out;
}

/**
 * Evaluate WC3 node world matrices at frame (same rules as war3-model updateNode, no billboards).
 * @param {import('war3-model').Node[]} nodes
 * @param {number} frame
 * @returns {Float32Array[]} world matrices indexed by ObjectId
 */
export function evaluateNodeWorldMatrices(nodes, frame) {
  /** @type {Map<number, import('war3-model').Node>} */
  const byId = new Map();
  for (const n of nodes) {
    if (n) byId.set(n.ObjectId, n);
  }

  /** @type {Float32Array[]} */
  const worlds = [];
  const visiting = new Set();

  function evalNode(id) {
    if (worlds[id]) return worlds[id];
    if (visiting.has(id)) {
      worlds[id] = mat4Identity();
      return worlds[id];
    }
    visiting.add(id);
    const node = byId.get(id);
    if (!node) {
      worlds[id] = mat4Identity();
      return worlds[id];
    }

    const t = sampleAnimVector(node.Translation, frame, DEFAULT_T);
    const r = sampleAnimVector(node.Rotation, frame, DEFAULT_R);
    const s = sampleAnimVector(node.Scaling, frame, DEFAULT_S);
    const pivot = node.PivotPoint || DEFAULT_T;

    const local = mat4FromRotationTranslationScaleOrigin(
      new Float32Array(16),
      r,
      t,
      s,
      pivot,
    );

    if (node.Parent !== null && node.Parent !== undefined) {
      const parent = evalNode(node.Parent);
      worlds[id] = mat4Multiply(new Float32Array(16), parent, local);
    } else {
      worlds[id] = local;
    }
    visiting.delete(id);
    return worlds[id];
  }

  for (const n of nodes) {
    if (n) evalNode(n.ObjectId);
  }
  return worlds;
}

/**
 * Collect keyframe times for a sequence interval.
 * @param {import('war3-model').Node[]} nodes
 * @param {number} start
 * @param {number} end
 * @param {number} stepMs
 * @param {import('war3-model').GeosetAnim[]} [geosetAnims]
 */
export function collectSampleFrames(nodes, start, end, stepMs = 33, geosetAnims = []) {
  const times = new Set();
  times.add(start);
  times.add(end);
  for (let f = start; f <= end; f += stepMs) times.add(f);

  for (const node of nodes) {
    if (!node) continue;
    for (const track of [node.Translation, node.Rotation, node.Scaling]) {
      if (!track?.Keys) continue;
      for (const key of track.Keys) {
        if (key.Frame >= start && key.Frame <= end) times.add(key.Frame);
      }
    }
  }

  for (const ga of geosetAnims) {
    const keys = ga?.Alpha?.Keys;
    if (!keys) continue;
    for (const key of keys) {
      if (key.Frame >= start && key.Frame <= end) times.add(key.Frame);
    }
  }

  return [...times].sort((a, b) => a - b);
}

/**
 * WC3 GeosetAnim alpha at frame (DontInterp hold). Default visible (1) if no anim.
 * @param {import('war3-model').GeosetAnim[] | undefined} geosetAnims
 * @param {number} geosetId
 * @param {number} frame
 */
export function sampleGeosetAlpha(geosetAnims, geosetId, frame) {
  const ga = (geosetAnims || []).find((g) => g.GeosetId === geosetId);
  if (!ga || ga.Alpha === undefined || ga.Alpha === null) return 1;
  if (typeof ga.Alpha === "number") return ga.Alpha;
  const keys = ga.Alpha.Keys || [];
  if (!keys.length) return 1;
  // Before first key: use first key value (WC3 geosets often start hidden with alpha 0).
  if (frame < keys[0].Frame) return keys[0].Vector[0];
  let value = keys[0].Vector[0];
  for (const key of keys) {
    if (key.Frame <= frame) value = key.Vector[0];
    else break;
  }
  return value;
}
