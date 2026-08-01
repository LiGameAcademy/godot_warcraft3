#!/usr/bin/env node
/**
 * 扫描 MDX：材质层 FilterMode 为 Additive(3) / AddAlpha(4) 的模型强制重转，
 * 使 GLB 材质名带 `_fm3`/`_fm4`，Godot 加载时改成 BLEND_MODE_ADD（消除黑底光晕牌）。
 *
 * 用法:
 *   node scripts/reconvert-additive-geosets.mjs
 *   node scripts/reconvert-additive-geosets.mjs --include "Doodads/**"
 *   node scripts/reconvert-additive-geosets.mjs --dry-run
 *   node scripts/reconvert-additive-geosets.mjs --list-only
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseMDL, parseMDX } from "war3-model";
import { matchesFilters, resolveFromPackage } from "../src/paths.js";
import { walkFiles } from "../src/walk.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PKG = path.resolve(__dirname, "..");

function parseArgs(argv) {
  const opts = { include: [], dryRun: false, listOnly: false, help: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--dry-run") opts.dryRun = true;
    else if (a === "--list-only") opts.listOnly = true;
    else if (a === "--include" && argv[i + 1]) opts.include.push(argv[++i]);
    else if (a === "-h" || a === "--help") opts.help = true;
  }
  return opts;
}

function hasAdditiveMaterial(model) {
  for (const mat of model.Materials ?? []) {
    for (const layer of mat.Layers ?? []) {
      const fm = layer.FilterMode ?? 0;
      if (fm === 3 || fm === 4) return true;
    }
  }
  return false;
}

function parseModelFile(absPath, logicalPath) {
  const data = fs.readFileSync(absPath);
  if (logicalPath.toLowerCase().endsWith(".mdl")) {
    return parseMDL(data.toString("utf8"));
  }
  const buf = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
  return parseMDX(buf);
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    console.log(`用法: node scripts/reconvert-additive-geosets.mjs [--include glob] [--dry-run] [--list-only]`);
    process.exit(0);
  }

  const inDir = resolveFromPackage("../../.cache/wc3-assets", PKG);
  const include = opts.include.length > 0 ? opts.include : ["Doodads/**"];
  const files = walkFiles(inDir, new Set([".mdx", ".mdl"]), include, []);
  const hits = [];

  console.log(`扫描 ${files.length} 个模型（include: ${include.join(", ")}）…`);
  for (const f of files) {
    if (!matchesFilters(f.logicalPath, include, [])) continue;
    try {
      const model = parseModelFile(f.absPath, f.logicalPath);
      if (hasAdditiveMaterial(model)) hits.push(f.logicalPath);
    } catch (err) {
      console.warn(`  跳过解析失败: ${f.logicalPath}: ${err.message ?? err}`);
    }
  }

  const listPath = path.join(__dirname, "_additive_geoset_hits.json");
  fs.writeFileSync(listPath, `${JSON.stringify(hits, null, 2)}\n`, "utf8");
  console.log(`Additive Geoset 模型: ${hits.length}（列表: ${path.relative(PKG, listPath)}）`);

  if (opts.listOnly || opts.dryRun || hits.length === 0) {
    if (opts.dryRun) console.log("dry-run：不执行转换");
    process.exit(0);
  }

  // 按目录批量 --include，避免一次塞上千个 glob
  const dirs = new Set();
  for (const logical of hits) {
    const n = logical.replace(/\\/g, "/");
    const dir = path.posix.dirname(n);
    dirs.add(`${dir}/**`);
  }
  const includeArgs = [];
  for (const g of [...dirs].sort()) {
    includeArgs.push("--include", g);
  }

  console.log(`强制重转 ${dirs.size} 个目录…`);
  const r = spawnSync(
    process.execPath,
    ["src/cli.js", "--models-only", "--force", ...includeArgs],
    { cwd: PKG, stdio: "inherit" },
  );
  process.exit(r.status ?? 1);
}

main();
