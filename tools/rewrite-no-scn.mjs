#!/usr/bin/env node
// 一次性改写 assets/asset-converted/.no-scn：
// 每行路径加上 /raw/ 段（GLB 现位于 raw/ 子目录）。
// 例：Buildings/Orc/GreatHall/GreatHall.glb -> Buildings/Orc/GreatHall/raw/GreatHall.glb

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = resolve(__dirname, "..");
const NO_SCN = join(REPO_ROOT, "assets/asset-converted/.no-scn");

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");

if (!existsSync(NO_SCN)) {
  console.error(`[rewrite-no-scn] not found: ${NO_SCN}`);
  process.exit(2);
}

const text = readFileSync(NO_SCN, { encoding: "utf8" });
const lines = text.split(/\r?\n/);
let changed = 0;
const newLines = lines.map((line) => {
  const t = line.trim();
  if (!t || t.startsWith("#")) return line;
  // 已经是 raw/ 路径就跳过
  if (t.includes("/raw/")) return line;
  // 匹配 ".../<dir>/<file>.glb"：在 dir 后插 raw/
  const m = t.match(/^(.*\/)([^/]+\.glb)$/);
  if (!m) return line;
  changed += 1;
  const newPath = `${m[1]}raw/${m[2]}`;
  // 保留原缩进（如有）
  const indent = line.match(/^\s*/)[0];
  return `${indent}${newPath}`;
});

console.log(`[rewrite-no-scn] lines=${lines.length} changed=${changed} dry_run=${dryRun}`);
if (dryRun) {
  console.log("[rewrite-no-scn] dry-run; re-run without --dry-run to apply.");
} else {
  writeFileSync(NO_SCN, newLines.join("\n"), { encoding: "utf8" });
}