import path from "node:path";
import { minimatch } from "minimatch";

export function normalizeLogicalPath(p) {
  return String(p)
    .replace(/\\/g, "/")
    .replace(/^\/+/, "")
    .trim();
}

export function resolveFromPackage(p, packageRoot) {
  return path.isAbsolute(p) ? path.normalize(p) : path.resolve(packageRoot, p);
}

/**
 * @param {string} logicalPath
 * @param {string[]} include
 * @param {string[]} exclude
 */
export function matchesFilters(logicalPath, include, exclude) {
  const opts = { nocase: true, dot: true };
  if (include.length > 0 && !include.some((g) => minimatch(logicalPath, g, opts))) {
    return false;
  }
  if (exclude.some((g) => minimatch(logicalPath, g, opts))) {
    return false;
  }
  return true;
}

/** Map WC3 texture path to converted PNG logical path. */
export function blpLogicalToPng(logicalPath) {
  const n = normalizeLogicalPath(logicalPath);
  if (n.toLowerCase().endsWith(".blp")) {
    return `${n.slice(0, -4)}.png`;
  }
  return `${n}.png`;
}

/** Map WC3 model path to converted GLB logical path.
 *  GLB 写到 raw/ 子目录，避免 Godot 编辑器 auto-import（同名 .scn/PNG 副产物冲突）。
 *  .scn/.pe2.json/.png 仍在原目录，FileSystem 可见。
 */
export function mdxLogicalToGlb(logicalPath) {
  const n = normalizeLogicalPath(logicalPath);
  const base = stripExt(n);
  return `${base}/raw/${baseExt(n, ".glb")}`;
}

function baseExt(p, ext) {
  return `${stripExt(p)}${ext}`;
}

function stripExt(p) {
  const i = p.lastIndexOf(".");
  return i > 0 ? p.slice(0, i) : p;
}

/** Map WC3 model path to ParticleEmitter2 sidecar JSON (next to .scn, NOT inside raw/). */
export function mdxLogicalToPe2(logicalPath) {
  const n = normalizeLogicalPath(logicalPath);
  return `${stripExt(n)}.pe2.json`;
}

/** Map WC3 model path to Geoset visibility sidecar (Godot bake injects AnimationPlayer tracks). */
export function mdxLogicalToGeosetVis(logicalPath) {
  const n = normalizeLogicalPath(logicalPath);
  return `${stripExt(n)}.geosetvis.json`;
}
