import path from "node:path";
import { minimatch } from "minimatch";

/** Internal MPQ metadata files that should never be written to the asset cache. */
export const INTERNAL_MPQ_FILES = new Set([
  "(listfile)",
  "(attributes)",
  "(signature)",
  "(user data)",
]);

/**
 * Normalize a WC3 logical path: backslash → slash, strip leading slashes.
 * @param {string} name
 * @returns {string}
 */
export function normalizeLogicalPath(name) {
  return String(name)
    .replace(/\\/g, "/")
    .replace(/^\/+/, "")
    .trim();
}

/**
 * @param {string} logicalPath
 * @returns {boolean}
 */
export function isInternalMpqFile(logicalPath) {
  const base = logicalPath.split("/").pop()?.toLowerCase() ?? "";
  if (base.startsWith("(") && base.endsWith(")")) {
    return true;
  }
  return INTERNAL_MPQ_FILES.has(logicalPath.toLowerCase());
}

/**
 * @param {string} logicalPath
 * @param {string[]} include
 * @param {string[]} exclude
 * @returns {boolean}
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

/**
 * Resolve a path relative to the tools/mpq-extract package root when not absolute.
 * @param {string} p
 * @param {string} packageRoot
 * @returns {string}
 */
export function resolveFromPackage(p, packageRoot) {
  return path.isAbsolute(p) ? path.normalize(p) : path.resolve(packageRoot, p);
}
