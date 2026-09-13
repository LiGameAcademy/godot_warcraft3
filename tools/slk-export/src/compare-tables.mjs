import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { parseSlk } from "./parse-slk.js";

export function readTable(file) {
  return path.extname(file).toLowerCase() === ".slk"
    ? parseSlk(fs.readFileSync(file))
    : JSON.parse(fs.readFileSync(file, "utf8"));
}

export function compareTables(before, after, key = before.headers?.[0]) {
  if (!key || !Array.isArray(before.records) || !Array.isArray(after.records)) {
    throw new Error("Expected tables with a primary key and records arrays");
  }
  const index = (records) => {
    const out = new Map();
    for (const row of records) {
      const id = row[key];
      if (id === undefined || id === null || id === "" || out.has(id)) {
        throw new Error(`Missing or duplicate primary key: ${String(id)}`);
      }
      out.set(id, row);
    }
    return out;
  };
  const old = index(before.records);
  const next = index(after.records);
  const added = [];
  const removed = [];
  const changed = [];
  for (const [id, row] of next) {
    if (!old.has(id)) { added.push(id); continue; }
    const previous = old.get(id);
    const fields = [];
    for (const field of new Set([...Object.keys(previous), ...Object.keys(row)])) {
      const had = Object.hasOwn(previous, field);
      const has = Object.hasOwn(row, field);
      if (had === has && JSON.stringify(previous[field]) === JSON.stringify(row[field])) continue;
      fields.push({
        field, kind: !had ? "added" : !has ? "removed" : "changed",
        before: had ? previous[field] : null, after: has ? row[field] : null,
      });
    }
    if (fields.length) changed.push({ id, fields });
  }
  for (const id of old.keys()) if (!next.has(id)) removed.push(id);
  return {
    key, beforeCount: old.size, afterCount: next.size,
    added, removed, changed,
    existingValueChanges: changed.filter(row => row.fields.some(field => field.kind === "changed")).length,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const [beforeFile, afterFile, outputFile, key] = process.argv.slice(2);
  if (!beforeFile || !afterFile || !outputFile) {
    console.error("Usage: node compare-tables.mjs before.json after.slk report.json [primary-key]");
    process.exitCode = 1;
  } else {
    const report = compareTables(readTable(beforeFile), readTable(afterFile), key);
    fs.writeFileSync(outputFile, JSON.stringify({ beforeFile, afterFile, ...report }, null, 2) + "\n");
    console.log(JSON.stringify({ beforeCount: report.beforeCount, afterCount: report.afterCount,
      added: report.added.length, removed: report.removed.length, changed: report.changed.length,
      existingValueChanges: report.existingValueChanges }));
  }
}
