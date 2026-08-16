#!/usr/bin/env node
// tools/check-pe2-coverage.mjs
// 老李 P2-7：检查 PE2 预制覆盖度
// 扫 .glb 旁路 .pe2.json（m2g 输出）vs assets/pe2-prefabs/*.pe2.tscn（export_pe2_scenes 烘焙）。
// 报告 .pe2.json 总数 / .tscn 总数 / 哪些 .pe2.json 没对应 .tscn（runtime 走 JSON fallback）。

import {
  existsSync,
  readdirSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const TOOLS_DIR = path.dirname(__filename);
const REPO_ROOT = path.resolve(TOOLS_DIR, "..");
const ASSET_CONVERTED = path.join(REPO_ROOT, "assets", "asset-converted");
const PE2_PREFABS = path.join(REPO_ROOT, "assets", "pe2-prefabs");

const args = process.argv.slice(2);
const mdOut = (() => {
  const i = args.indexOf("--md");
  return i >= 0 ? args[i + 1] : null;
})();
const failOnGap = args.includes("--fail");

/** @param {string} dir @param {(p: string) => boolean} match */
function walk(dir, match) {
  /** @type {string[]} */
  const out = [];
  function rec(d) {
    let entries;
    try { entries = readdirSync(d, { withFileTypes: true }); }
    catch { return; }
    for (const e of entries) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) rec(p);
      else if (e.isFile() && match(p)) out.push(p);
    }
  }
  rec(dir);
  return out;
}

const report = {
  pe2JsonTotal: 0,
  pe2TscnTotal: 0,
  jsonMissingTscnList: [],
  tscnOrphanList: [],
  byThemeStats: {},
};

function main() {
  console.log("[check-pe2] === PE2 预制覆盖度检查 ===");
  if (!existsSync(ASSET_CONVERTED)) {
    console.error("asset-converted 不存在；先跑 bootstrap");
    process.exit(1);
  }
  if (!existsSync(PE2_PREFABS)) {
    console.warn("pe2-prefabs 不存在；可能还没跑 export_pe2_scenes");
  }

  const allJson = walk(ASSET_CONVERTED, (p) => p.endsWith(".pe2.json"));
  report.pe2JsonTotal = allJson.length;
  console.log(`[check-pe2] .pe2.json 总数: ${report.pe2JsonTotal}`);

  const allTscn = existsSync(PE2_PREFABS) ? walk(PE2_PREFABS, (p) => p.endsWith(".pe2.tscn")) : [];
  report.pe2TscnTotal = allTscn.length;
  console.log(`[check-pe2] .pe2.tscn 总数: ${report.pe2TscnTotal}`);

  const tscnStems = new Set();
  for (const t of allTscn) {
    const rel = path.relative(PE2_PREFABS, t).replace(/\\/g, "/");
    const stem = rel.replace(/\.pe2\.tscn$/, "");
    tscnStems.add(stem);
  }

  for (const j of allJson) {
    const rel = path.relative(ASSET_CONVERTED, j).replace(/\\/g, "/");
    const stem = rel.replace(/\.pe2\.json$/, "");
    if (!tscnStems.has(stem)) {
      report.jsonMissingTscnList.push(rel);
      const theme = rel.split("/").slice(0, 2).join("/");
      report.byThemeStats[theme] = (report.byThemeStats[theme] || 0) + 1;
    }
  }

  const jsonStems = new Set();
  for (const j of allJson) {
    const rel = path.relative(ASSET_CONVERTED, j).replace(/\\/g, "/");
    jsonStems.add(rel.replace(/\.pe2\.json$/, ""));
  }
  for (const stem of tscnStems) {
    if (!jsonStems.has(stem)) {
      report.tscnOrphanList.push(stem + ".pe2.tscn");
    }
  }

  console.log(`[check-pe2] .pe2.json 缺 .pe2.tscn: ${report.jsonMissingTscnList.length}`);
  console.log(`[check-pe2] .pe2.tscn 找不到对应 .pe2.json: ${report.tscnOrphanList.length}`);

  const lines = [];
  lines.push("# PE2 预制覆盖度检查");
  lines.push("");
  lines.push(`- 检查时间：${new Date().toISOString()}`);
  lines.push(`- .pe2.json 总数: **${report.pe2JsonTotal}** (m2g 输出，GLB 旁路)`);
  lines.push(`- .pe2.tscn 总数: **${report.pe2TscnTotal}** (pe2-prefabs 可编辑预制)`);
  lines.push(`- .pe2.json 缺 .pe2.tscn: **${report.jsonMissingTscnList.length}** (runtime 走 JSON fallback)`);
  if (report.jsonMissingTscnList.length) {
    lines.push(`  按主题分布：`);
    for (const [theme, n] of Object.entries(report.byThemeStats)) {
      lines.push(`  - ${theme}: ${n}`);
    }
    lines.push(`  前 20 个缺漏：`);
    report.jsonMissingTscnList.slice(0, 20).forEach((p) => lines.push(`  - ${p}`));
  }
  lines.push(`- .pe2.tscn 找不到对应 .pe2.json: **${report.tscnOrphanList.length}**`);
  if (report.tscnOrphanList.length) {
    lines.push(`  列表：`);
    report.tscnOrphanList.slice(0, 20).forEach((p) => lines.push(`  - ${p}`));
  }
  lines.push("");
  if (report.jsonMissingTscnList.length === 0) {
    lines.push("- 100% 覆盖");
  } else {
    lines.push("- 修复：跑 `godot --headless -s res://scripts/tool/export_pe2_scenes.gd -- --include <theme>`");
  }
  const md = lines.join("\n");
  if (mdOut) {
    writeFileSync(mdOut, md, "utf8");
    console.log(`[check-pe2] 报告写入: ${mdOut}`);
  } else {
    console.log("\n" + md);
  }
  if (failOnGap && report.jsonMissingTscnList.length > 0) {
    console.error(`\n${report.jsonMissingTscnList.length} 个缺口（--fail 触发 exit 1）`);
    process.exit(1);
  }
  process.exit(0);
}

main();
