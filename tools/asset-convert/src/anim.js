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
 * 取 seqStart 之前最后一帧关键值（无则 fallback）。
 * 用于 Morph/Alternate：作者常只在部分 Alternate 段写 Scaling，其余段靠引擎保持上一形态。
 * @param {import('war3-model').AnimVector | undefined} anim
 * @param {number} seqStart
 * @param {Float32Array} fallback
 * @returns {Float32Array}
 */
export function sampleAnimVectorCarryIn(anim, seqStart, fallback) {
  if (!anim?.Keys?.length) return fallback;
  let carry = null;
  for (const key of anim.Keys) {
    if (key.Frame < seqStart) carry = key.Vector;
    else break;
  }
  return carry != null ? carry : fallback;
}

/**
 * Sequence 名是否为变身族（Alternate / Morph）。
 * 例：`Alternate Stand - 1`、`Morph Alternate`、`Attack Slam Alternate`。
 * @param {unknown} raw
 * @returns {boolean}
 */
export function isAlternateOrMorphSequenceName(raw) {
  const n = String(raw ?? "").trim();
  if (!n) return false;
  return /^(alternate|morph)\b/i.test(n) || /\balternate\b/i.test(n);
}

/**
 * Sequence-scoped bone TRS (WC3 runtime semantics).
 * Only Keys with Frame in [seqStart, seqEnd] apply; if none → fallback (bind/default).
 * Before the first in-sequence key → fallback.
 * `opts.carryIn`：无 in-seq key 时用 seqStart 前最后一帧（Morph/Alternate 骨骼缩放保持）。
 * Global Sequence tracks must NOT use this — see {@link sampleAnimVectorOnClock}.
 * @param {import('war3-model').AnimVector | undefined} anim
 * @param {number} frame
 * @param {number} seqStart
 * @param {number} seqEnd
 * @param {Float32Array} fallback
 * @param {{ carryIn?: boolean }} [opts]
 * @returns {Float32Array}
 */
export function sampleAnimVectorInSequence(
  anim,
  frame,
  seqStart,
  seqEnd,
  fallback,
  opts = {},
) {
  if (!anim?.Keys?.length) return fallback;
  const keys = anim.Keys.filter((k) => k.Frame >= seqStart && k.Frame <= seqEnd);
  if (!keys.length) {
    if (opts.carryIn) return sampleAnimVectorCarryIn(anim, seqStart, fallback);
    return fallback;
  }
  if (frame < keys[0].Frame && opts.carryIn) {
    return sampleAnimVectorCarryIn(anim, seqStart, keys[0].Vector);
  }
  return sampleAnimVector({ ...anim, Keys: keys }, frame, fallback);
}

/** @param {Float32Array} a @param {Float32Array} b @param {number} t */
function lerpAnimVector(a, b, t) {
  const n = Math.min(a.length, b.length);
  const out = new Float32Array(n);
  const u = Math.max(0, Math.min(1, t));
  for (let i = 0; i < n; i += 1) {
    out[i] = a[i] + (b[i] - a[i]) * u;
  }
  return out;
}

/**
 * MDX AnimVector.GlobalSeqId：≥0 有效（0 是第一条 Global Sequence）；-1 / 缺省 = 无。
 * @param {import('war3-model').AnimVector | number | undefined | null} anim
 * @returns {number}
 */
export function animGlobalSeqId(anim) {
  if (anim == null || typeof anim !== "object") return -1;
  const raw = /** @type {{ GlobalSeqId?: number | null }} */ (anim).GlobalSeqId;
  // Number(null)===0，会误当成第一条 Global Sequence（主城铃铛冻在 bind）。
  if (raw === undefined || raw === null) return -1;
  const id = Number(raw);
  if (!Number.isFinite(id) || id < 0) return -1;
  return id | 0;
}

/** @param {number} timeMs @param {number} durationMs */
export function wrapGlobalSeqTime(timeMs, durationMs) {
  if (!(durationMs > 0)) return 0;
  const t = timeMs % durationMs;
  return t < 0 ? t + durationMs : t;
}

/**
 * 模型里实际用到的 Global Sequence 最长时长（毫秒）。
 * 旗 ~1.3–1.7s、分针 ~6.7s；时针常 80s——拉长每一条循环 Sequence 会把 .bin 打到上百 MB，
 * 故默认忽略超过 capMs 的时钟类 Global Sequence（仍按 % dur 在段内采样）。
 * @param {import('war3-model').Node[] | undefined} nodes
 * @param {ArrayLike<number> | undefined} globalSequences
 * @param {number} [capMs]
 */
export function maxUsedGlobalSeqDuration(nodes, globalSequences, capMs = 20000) {
  let max = 0;
  const seqs = globalSequences || [];
  for (const node of nodes || []) {
    if (!node) continue;
    for (const track of [node.Translation, node.Rotation, node.Scaling]) {
      const gid = animGlobalSeqId(track);
      if (gid < 0) continue;
      const d = Number(seqs[gid]) || 0;
      if (d > capMs) continue;
      if (d > max) max = d;
    }
  }
  return max;
}

/**
 * 循环 Sequence 必须盖住最长 Global Sequence，否则 Stand（常 333ms）播完就跳回，旗只抖一下。
 * 非循环（Birth/Death）保持原长，用 localTime % globalDur 在段内循环飘。
 * @param {number} seqStart
 * @param {number} seqEnd
 * @param {boolean} looping
 * @param {import('war3-model').Node[] | undefined} nodes
 * @param {ArrayLike<number> | undefined} globalSequences
 */
export function sequenceBakeDurationMs(
  seqStart,
  seqEnd,
  looping,
  nodes,
  globalSequences,
) {
  const seqDur = Math.max(0, seqEnd - seqStart);
  if (!looping) return seqDur;
  return Math.max(seqDur, maxUsedGlobalSeqDuration(nodes, globalSequences));
}

/**
 * Global Sequence 时钟采样：keys 在 [0, duration]，与当前 Sequence 区间无关。
 * @param {import('war3-model').AnimVector | undefined} anim
 * @param {number} globalTimeMs
 * @param {number} durationMs
 * @param {Float32Array} fallback
 */
export function sampleAnimVectorOnClock(anim, globalTimeMs, durationMs, fallback) {
  return sampleAnimVector(anim, wrapGlobalSeqTime(globalTimeMs, durationMs), fallback);
}

/**
 * Evaluate WC3 node world matrices at frame (same rules as war3-model updateNode, no billboards).
 * When seqStart/seqEnd are provided, bone TRS uses sequence-scoped sampling,
 * except GlobalSeqId tracks which follow {@link wrapGlobalSeqTime}.
 * @param {import('war3-model').Node[]} nodes
 * @param {number} frame
 * @param {number} [seqStart]
 * @param {number} [seqEnd]
 * @param {ArrayLike<number>} [globalSequences]
 * @param {number} [globalTimeMs]
 * @param {{
 *   carryInScaling?: boolean,
 *   morphScaleLerp?: number | null,
 * }} [opts] carryInScaling：Alternate/Morph 无 Scaling key 时保持上一形态；
 *   morphScaleLerp∈[0,1]：Morph 段从 bind 插到变身后目标缩放（天神下凡变身过渡）。
 * @returns {Float32Array[]} world matrices indexed by ObjectId
 */
export function evaluateNodeWorldMatrices(
  nodes,
  frame,
  seqStart,
  seqEnd,
  globalSequences,
  globalTimeMs,
  opts = {},
) {
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

  const gTime =
    typeof globalTimeMs === "number" && Number.isFinite(globalTimeMs)
      ? globalTimeMs
      : scoped
        ? frame - seqStart
        : frame;

  const carryInScaling = Boolean(opts.carryInScaling);
  const morphLerp =
    typeof opts.morphScaleLerp === "number" && Number.isFinite(opts.morphScaleLerp)
      ? Math.max(0, Math.min(1, opts.morphScaleLerp))
      : null;

  /** @type {Float32Array[]} */
  const worlds = [];
  const visiting = new Set();

  function sampleTrs(anim, fallback, asScaling = false) {
    const gid = animGlobalSeqId(anim);
    const dur = gid >= 0 ? Number(globalSequences?.[gid]) || 0 : 0;
    if (gid >= 0 && dur > 0) {
      return sampleAnimVectorOnClock(anim, gTime, dur, fallback);
    }
    if (asScaling && morphLerp != null && scoped) {
      // Morph：MDX 段内常无 Scaling key；从 bind 过渡到时间轴上的变身目标。
      const target = sampleAnimVector(anim, seqEnd, fallback);
      return lerpAnimVector(fallback, target, morphLerp);
    }
    if (scoped) {
      return sampleAnimVectorInSequence(anim, frame, seqStart, seqEnd, fallback, {
        carryIn: asScaling && carryInScaling,
      });
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

    const t = sampleTrs(node.Translation, DEFAULT_T, false);
    const r = sampleTrs(node.Rotation, DEFAULT_R, false);
    const s = sampleTrs(node.Scaling, DEFAULT_S, true);
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
 * 烘焙时间轴（相对 Sequence 起点，毫秒）。
 * 用 33ms 网格覆盖 bakeDur，另加入 Sequence 原始 keys（铺到循环段）。
 * Global Sequence 不另铺 keys：evaluate 时用 globalTime % dur，33ms 已够捕获旗/钟。
 * @param {import('war3-model').Node[]} nodes
 * @param {number} seqStart
 * @param {number} seqEnd
 * @param {number} bakeDur
 * @param {number} [stepMs]
 * @param {import('war3-model').GeosetAnim[]} [geosetAnims]
 * @param {ArrayLike<number>} [_globalSequences]
 */
export function collectBakeFrames(
  nodes,
  seqStart,
  seqEnd,
  bakeDur,
  stepMs = 33,
  geosetAnims = [],
  _globalSequences = [],
) {
  const seqDur = Math.max(0, seqEnd - seqStart);
  const cap = Math.max(0, bakeDur);
  const times = new Set([0, cap]);
  if (cap <= 0) return [0];
  const step = Math.max(1, stepMs);
  for (let t = 0; t <= cap; t += step) times.add(t);

  const period = collectSampleFrames(
    nodes,
    seqStart,
    seqEnd,
    Math.max(seqDur, 1),
    geosetAnims,
  );
  const stride = seqDur > 0 ? seqDur : cap;
  for (const f of period) {
    const rel = f - seqStart;
    if (rel < 0 || rel > seqDur) continue;
    for (let t = rel; t <= cap + 0.5; t += stride) {
      times.add(Math.min(t, cap));
      if (stride <= 0) break;
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

/** WC3 GeosetAnim Alpha 原始值（0–255 或 0–1）→ 0–1。 */
export function normalizeGeosetAlpha(raw) {
  let a = Number(raw);
  if (!Number.isFinite(a)) a = 0;
  if (a > 1.0) a = a / 255.0;
  return Math.max(0, Math.min(1, Math.round(a * 1000) / 1000));
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
