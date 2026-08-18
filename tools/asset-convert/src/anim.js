import {
  mat4FromRotationTranslationScaleOrigin,
  mat4Identity,
  mat4Multiply,
} from "./mat4.js";

const DEFAULT_T = new Float32Array([0, 0, 0]);
const DEFAULT_R = new Float32Array([0, 0, 0, 1]);
const DEFAULT_S = new Float32Array([1, 1, 1]);

/** MDX AnimVector.LineType → 名。0 无插值 / 1 线性 / 2 Hermite / 3 Bezier。 */
export const LINE_TYPE_NAMES = ["DontInterp", "Linear", "Hermite", "Bezier"];

/**
 * WC3 Sequence 名 → glTF / Godot 动画名。
 * 单词之间不加 `_`（驼峰拼接）；变体序号保留 `-`。
 * `"Stand - 2"` → `Stand-2`（避免 `Stand_-_2`）；`"Decay Flesh"` → `DecayFlesh`。
 * @param {unknown} raw
 * @returns {string}
 */
export function wc3SequenceToAnimName(raw) {
  const src = String(raw ?? "").trim();
  if (!src) return "Anim";
  const hyphenNorm = src.replace(/\s*-\s*/g, "-");
  const words = hyphenNorm.split(/\s+/).filter(Boolean);
  if (words.length === 0) return "Anim";
  return words.map(pascalHyphenToken).join("");
}

/** @param {string} token */
function pascalHyphenToken(token) {
  return token
    .split("-")
    .map((seg) => {
      if (!seg) return "";
      if (/^\d+$/.test(seg)) return seg;
      return seg.charAt(0).toUpperCase() + seg.slice(1);
    })
    .join("-");
}

/**
 * Interpolate AnimVector at frame (WC3 millis). Linear between keys; clamp outside.
 * Prefer {@link sampleAnimVectorInSequence} when baking a Sequence — WC3 only
 * honors keys inside the playing interval; outside keys must not clamp in
 * (Barracks Door00 only keys Stand Work → global clamp wrongly opens doors in Stand).
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
 * Sequence-scoped bone TRS (WC3 runtime semantics).
 * Only Keys with Frame in [seqStart, seqEnd] apply; if none → fallback (bind/default).
 * Before the first in-sequence key → fallback.
 * @param {import('war3-model').AnimVector | undefined} anim
 * @param {number} frame
 * @param {number} seqStart
 * @param {number} seqEnd
 * @param {Float32Array} fallback
 * @returns {Float32Array}
 */
export function sampleAnimVectorInSequence(anim, frame, seqStart, seqEnd, fallback) {
  if (!anim?.Keys?.length) return fallback;
  const keys = anim.Keys.filter((k) => k.Frame >= seqStart && k.Frame <= seqEnd);
  if (!keys.length) return fallback;
  return sampleAnimVector({ ...anim, Keys: keys }, frame, fallback);
}

/**
 * Evaluate WC3 node world matrices at frame (same rules as war3-model updateNode, no billboards).
 * When seqStart/seqEnd are provided, bone TRS uses sequence-scoped sampling.
 * @param {import('war3-model').Node[]} nodes
 * @param {number} frame
 * @param {number} [seqStart]
 * @param {number} [seqEnd]
 * @returns {Float32Array[]} world matrices indexed by ObjectId
 */
export function evaluateNodeWorldMatrices(nodes, frame, seqStart, seqEnd) {
  /** @type {Map<number, import('war3-model').Node>} */
  const byId = new Map();
  for (const n of nodes) {
    if (n) byId.set(n.ObjectId, n);
  }

  const scoped =
    typeof seqStart === "number" &&
    typeof seqEnd === "number" &&
    Number.isFinite(seqStart) &&
    Number.isFinite(seqEnd);

  /** @type {Float32Array[]} */
  const worlds = [];
  const visiting = new Set();

  function sampleTrs(anim, fallback) {
    if (scoped) {
      return sampleAnimVectorInSequence(anim, frame, seqStart, seqEnd, fallback);
    }
    return sampleAnimVector(anim, frame, fallback);
  }

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

    const t = sampleTrs(node.Translation, DEFAULT_T);
    const r = sampleTrs(node.Rotation, DEFAULT_R);
    const s = sampleTrs(node.Scaling, DEFAULT_S);
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
 * WC3 GeosetAnim alpha at frame (DontInterp hold across entire timeline).
 * Prefer {@link sampleGeosetAlphaInSequence} when baking a Sequence — WC3 only
 * honors keys inside the playing interval; outside keys do not carry over, and
 * missing keys default to visible (1). Global hold wrongly hides TownHall Stand.
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

/**
 * Sequence-scoped GeosetAnim alpha (WC3 runtime semantics).
 * Only Keys with Frame in [seqStart, seqEnd] drive the curve.
 * - 无 in-sequence keys → 可见 (1)（主城 Stand 主体无轨时依赖此默认）
 * - 首 key 之前 → 用 seqStart 之前的最后一帧全局值（carry-in）；若无则 hold 首 key
 *   （禁止一律 1：否则 Altar Stand_Work 脚手架在仅有结尾 hide key 时会整段闪现）
 * @param {import('war3-model').GeosetAnim[] | undefined} geosetAnims
 * @param {number} geosetId
 * @param {number} frame
 * @param {number} seqStart
 * @param {number} seqEnd
 */
export function sampleGeosetAlphaInSequence(
  geosetAnims,
  geosetId,
  frame,
  seqStart,
  seqEnd,
) {
  const ga = (geosetAnims || []).find((g) => g.GeosetId === geosetId);
  if (!ga || ga.Alpha === undefined || ga.Alpha === null) return 1;
  if (typeof ga.Alpha === "number") return ga.Alpha;
  const allKeys = ga.Alpha.Keys || [];
  if (!allKeys.length) return 1;
  const keys = allKeys.filter((k) => k.Frame >= seqStart && k.Frame <= seqEnd);
  if (!keys.length) return 1;
  if (frame < keys[0].Frame) {
    let carry = null;
    for (const key of allKeys) {
      if (key.Frame < seqStart) carry = key.Vector[0];
      else break;
    }
    if (carry !== null) return carry;
    return keys[0].Vector[0];
  }
  let value = keys[0].Vector[0];
  for (const key of keys) {
    if (key.Frame <= frame) value = key.Vector[0];
    else break;
  }
  return value;
}
