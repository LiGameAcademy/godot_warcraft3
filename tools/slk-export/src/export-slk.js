import fs from "node:fs";
import path from "node:path";
import { Minimatch } from "minimatch";
import { parseSlk } from "./parse-slk.js";

/**
 * @param {string} dir
 * @returns {string[]}
 */
function walkSlkFiles(dir) {
  /** @type {string[]} */
  const out = [];
  if (!fs.existsSync(dir)) return out;

  /** @param {string} current */
  function walk(current) {
    for (const ent of fs.readdirSync(current, { withFileTypes: true })) {
      const full = path.join(current, ent.name);
      if (ent.isDirectory()) walk(full);
      else if (ent.isFile() && /\.slk$/i.test(ent.name)) out.push(full);
    }
  }
  walk(dir);
  return out;
}

/**
 * @param {string} logicalPath
 * @param {Minimatch[]} include
 * @param {Minimatch[]} exclude
 */
function matchPath(logicalPath, include, exclude) {
  const norm = logicalPath.replace(/\\/g, "/");
  if (exclude.some((m) => m.match(norm))) return false;
  if (include.length === 0) return true;
  return include.some((m) => m.match(norm));
}

/**
 * @param {{
 *   inDir: string,
 *   outDir: string,
 *   force?: boolean,
 *   include?: string[],
 *   exclude?: string[],
 *   pretty?: boolean,
 * }} opts
 */
export function exportSlkBatch(opts) {
  const inDir = path.resolve(opts.inDir);
  const outDir = path.resolve(opts.outDir);
  const force = opts.force === true;
  const pretty = opts.pretty !== false;

  const include = (opts.include ?? []).map(
    (g) => new Minimatch(g.replace(/\\/g, "/"), { dot: true, nocase: true }),
  );
  const exclude = (opts.exclude ?? []).map(
    (g) => new Minimatch(g.replace(/\\/g, "/"), { dot: true, nocase: true }),
  );

  const files = walkSlkFiles(inDir);
  let converted = 0;
  let skipped = 0;
  let errors = 0;
  /** @type {{ path: string, records: number, columns: number }[]} */
  const done = [];

  for (const abs of files) {
    const logical = path.relative(inDir, abs).replace(/\\/g, "/");
    if (!matchPath(logical, include, exclude)) {
      skipped += 1;
      continue;
    }

    const jsonPath = path.join(outDir, logical.replace(/\.slk$/i, ".json"));
    if (!force && fs.existsSync(jsonPath)) {
      skipped += 1;
      continue;
    }

    try {
      const text = fs.readFileSync(abs);
      const table = parseSlk(text);
      fs.mkdirSync(path.dirname(jsonPath), { recursive: true });

      const payload = {
        source: logical,
        columns: table.columns,
        rows: table.rows,
        headers: table.headers,
        recordCount: table.records.length,
        records: table.records,
      };
      fs.writeFileSync(
        jsonPath,
        `${JSON.stringify(payload, null, pretty ? 2 : 0)}\n`,
        "utf8",
      );

      // 清理历史 CSV 副产物（已弃用）
      const csvPath = jsonPath.replace(/\.json$/i, ".csv");
      if (fs.existsSync(csvPath)) {
        fs.unlinkSync(csvPath);
      }

      converted += 1;
      done.push({
        path: logical,
        records: table.records.length,
        columns: table.headers.length,
      });
      console.log(
        `OK  ${logical}  →  ${table.records.length} rows × ${table.headers.length} cols`,
      );
    } catch (e) {
      errors += 1;
      console.error(`ERR ${logical}: ${e instanceof Error ? e.message : e}`);
    }
  }

  const index = {
    version: 1,
    exportedAt: new Date().toISOString(),
    inDir,
    outDir,
    format: "json",
    fileCount: done.length,
    files: done,
  };
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(
    path.join(outDir, "index.json"),
    `${JSON.stringify(index, null, 2)}\n`,
    "utf8",
  );

  return { converted, skipped, errors, done };
}
