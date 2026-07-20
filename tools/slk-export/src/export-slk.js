import fs from "node:fs";
import path from "node:path";
import { Minimatch } from "minimatch";
import { parseSlk } from "./parse-slk.js";

/**
 * @param {unknown} value
 */
function csvEscape(value) {
  if (value === null || value === undefined) return "";
  const s = String(value);
  if (/[",\r\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}

/**
 * @param {string[]} headers
 * @param {Record<string, unknown>[]} records
 */
export function toCsv(headers, records) {
  const lines = [headers.map(csvEscape).join(",")];
  for (const rec of records) {
    lines.push(headers.map((h) => csvEscape(rec[h])).join(","));
  }
  return `${lines.join("\n")}\n`;
}

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
 *   formats?: ('json'|'csv')[],
 *   pretty?: boolean,
 * }} opts
 */
export function exportSlkBatch(opts) {
  const inDir = path.resolve(opts.inDir);
  const outDir = path.resolve(opts.outDir);
  const formats = opts.formats?.length ? opts.formats : ["json", "csv"];
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

    const baseOut = path.join(outDir, logical.replace(/\.slk$/i, ""));
    const jsonPath = `${baseOut}.json`;
    const csvPath = `${baseOut}.csv`;
    const needJson = formats.includes("json");
    const needCsv = formats.includes("csv");

    if (
      !force &&
      (!needJson || fs.existsSync(jsonPath)) &&
      (!needCsv || fs.existsSync(csvPath))
    ) {
      skipped += 1;
      continue;
    }

    try {
      const text = fs.readFileSync(abs);
      const table = parseSlk(text);
      fs.mkdirSync(path.dirname(baseOut), { recursive: true });

      if (needJson) {
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
      }
      if (needCsv) {
        fs.writeFileSync(csvPath, toCsv(table.headers, table.records), "utf8");
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
    formats,
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
