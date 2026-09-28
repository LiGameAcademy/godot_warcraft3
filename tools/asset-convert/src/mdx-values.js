import { LINE_TYPE_NAMES } from "./anim.js";
import { wc3ToGltfVec3 } from "./mat4.js";



export const MODEL_SCALE = 0.01;

export const COLLISION_SHAPE_NAMES = ["box", "plane", "sphere", "cylinder"];

/** MDX 定长名字常带 \\0 填充；写入 glTF/JSON 前必须剥掉，否则 Godot 报 Unexpected NUL。 */
export function sanitizeMdxText(s) {
	if (s == null) return "";
	return String(s).replace(/\0/g, "").trim();
}

/** @param {unknown} v */
export function asVec3(v) {
  if (v == null) return [0, 0, 0];
  if (Array.isArray(v) || ArrayBuffer.isView(v)) {
    return [Number(v[0]) || 0, Number(v[1]) || 0, Number(v[2]) || 0];
  }
  const o = /** @type {Record<string, number>} */ (v);
  return [Number(o[0] ?? o["0"]) || 0, Number(o[1] ?? o["1"]) || 0, Number(o[2] ?? o["2"]) || 0];
}

/** WC3 vec3 → glTF Y-up，再 × MODEL_SCALE（与 cameras.json 一致）. */
export function sidecarVec3(x, y, z) {
  const g = wc3ToGltfVec3(Number(x) || 0, Number(y) || 0, Number(z) || 0);
  return [g[0] * MODEL_SCALE, g[1] * MODEL_SCALE, g[2] * MODEL_SCALE];
}

/** @param {ArrayLike<number> | Record<string, number> | undefined | null} v */
export function numArray(v) {
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

/** Camera Translation / TargetTranslation：每 key 已 Y-up × MODEL_SCALE。 */
export function dumpCameraVecTrack(anim) {
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

export function dumpAnimVector(anim) {
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
export function attachmentVisibleByDefault(a) {
  const vis = dumpAnimVector(a?.Visibility);
  if (!vis) return true;
  if (typeof vis.static === "number") return vis.static >= 0.5;
  if (Array.isArray(vis.static)) return Number(vis.static[0]) >= 0.5;
  const k0 = vis.keys?.[0]?.vector?.[0];
  if (k0 != null) return Number(k0) >= 0.5;
  return true;
}

/** @param {import('war3-model').AnimVector | undefined | null} anim */
export function countKeysInInterval(anim, start, end) {
  if (!anim?.Keys?.length) return 0;
  let n = 0;
  for (const k of anim.Keys) {
    const f = Number(k.Frame) || 0;
    if (f >= start && f <= end) n += 1;
  }
  return n;
}
