import fs from "node:fs";
import path from "node:path";
import { matchesFilters, normalizeLogicalPath } from "./paths.js";

/**
 * Recursively collect files under root with given extensions.
 * @param {string} root
 * @param {Set<string>} extensions lowercase with dot, e.g. '.blp'
 * @param {string[]} include
 * @param {string[]} exclude
 * @returns {{ absPath: string, logicalPath: string }[]}
 */
export function walkFiles(root, extensions, include = [], exclude = []) {
  /** @type {{ absPath: string, logicalPath: string }[]} */
  const out = [];

  function walk(dir, logicalDir) {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const abs = path.join(dir, entry.name);
      const logical = normalizeLogicalPath(
        logicalDir ? `${logicalDir}/${entry.name}` : entry.name,
      );
      if (entry.isDirectory()) {
        walk(abs, logical);
        continue;
      }
      if (!entry.isFile()) continue;
      const ext = path.extname(entry.name).toLowerCase();
      if (!extensions.has(ext)) continue;
      if (!matchesFilters(logical, include, exclude)) continue;
      out.push({ absPath: abs, logicalPath: logical });
    }
  }

  walk(root, "");
  return out;
}
