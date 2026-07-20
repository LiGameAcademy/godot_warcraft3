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

/** Map WC3 model path to converted GLB logical path. */
export function mdxLogicalToGlb(logicalPath) {
  const n = normalizeLogicalPath(logicalPath);
  if (n.toLowerCase().endsWith(".mdx")) {
    return `${n.slice(0, -4)}.glb`;
  }
  if (n.toLowerCase().endsWith(".mdl")) {
    return `${n.slice(0, -4)}.glb`;
  }
  return `${n}.glb`;
}
