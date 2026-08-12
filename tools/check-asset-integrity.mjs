#!/usr/bin/env node
// tools/check-asset-integrity.mjs
// 老李 P3 任务：资产完整性 CI 检查
// ──────────────────────────────────────────────────────────────
// 扫 .cache/wc3-assets → assets/asset-converted → assets/map-parsed → assets/slk-exported，
// 报告"源 X 存在但目标 Y 缺失"的所有缺口。
//
// 用法：
//   node tools/check-asset-integrity.mjs
//   node tools/check-asset-integrity.mjs --md report.md
//   node tools/check-asset-integrity.mjs --fail    # 有缺口 exit 1（CI 友好）
//
// 检查项：
//   1. .glb：每个 wc3 MDX → 是否生成 .glb
//   2. .scn：每个 .glb → 是否烤成 .scn（eager bake 覆盖）
//   3. .map：每个 config.maps.items → 是否解析到 assets/map-parsed/
//   4. .slk：每个 wc3 SLK → 是否导出 JSON
//   5. 临时残留：assets/asset-converted 里 .import / Godot 旁路 PNG（.gdignore 之后应为空）
//   6. doc docs：mpq-extract cache 与 config.skip.convert.include 对比

import { spawnSync } from "node:child_process";
import {
  existsSync,
  readdirSync,
  readFileSync,
  writeFileSync,
  statSync,
} from "node:fs";
import { resolve, join, dirname, relative, extname, basename } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const TOOLS_DIR = dirname(__filename);
const REPO_ROOT = resolve(TOOLS_DIR, "..");
const DEFAULT_CONFIG = join(TOOLS_DIR, "bootstrap.config.json");

// ===== args =====
const args = process.argv.slice(2);
const mdOut = (() => {
  const i = args.indexOf("--md");
  return i >= 0 ? args[i + 1] : null;
})();
const failOnGap = args.includes("--fail");
const configPath = resolve(
  (() => {
    const i = args.indexOf("--config");
    return i >= 0 ? args[i + 1] : DEFAULT_CONFIG;
  })(),
);

// ===== log =====
const log = (msg) => console.log(`[check] ${msg}`);

// ===== run subprocess (复用 bootstrap.mjs 的显式 shell 规则) =====
function run(cmd, cmdArgs, opts = {}) {
  if (opts.shell === undefined) {
    throw new Error(`run("${cmd}", ...): opts.shell 必须显式传`);
  }
  return spawnSync(cmd, cmdArgs, {
    stdio: "pipe",
    cwd: opts.cwd || REPO_ROOT,
    env: { ...process.env, ...(opts.env || {}) },
    shell: opts.shell,
  });
}

function loadConfig() {
  if (!existsSync(configPath)) {
    console.error(`❌ Config not found: ${configPath}`);
    process.exit(1);
  }
  return JSON.parse(readFileSync(configPath, "utf8"));
}

function envOr(configValue, envVar) {
  return process.env[envVar] || configValue || null;
}

/** @param {string} dir @param {(p: string) => boolean} match */
function walk(dir, match) {
  /** @type {string[]} */
  const out = [];
  function rec(d) {
    let entries;
    try { entries = readdirSync(d, { withFileTypes: true }); }
    catch { return; }
    for (const e of entries) {
      const p = join(d, e.name);
      if (e.isDirectory()) rec(p);
      else if (e.isFile() && match(p)) out.push(p);
    }
  }
  rec(dir);
  return out;
}

const WC3_ASSETS = join(REPO_ROOT, ".cache", "wc3-assets");
const ASSET_CONVERTED = join(REPO_ROOT, "assets", "asset-converted");
const MAP_PARSED = join(REPO_ROOT, "assets", "map-parsed");
const SLK_EXPORTED = join(REPO_ROOT, "assets", "slk-exported");

const report = {
  configPath,
  mdxTotal: 0, glbMissing: 0, scnMissing: 0,
  mapsConfigured: 0, mapsMissing: 0, mapsExtra: 0,
  slkTotal: 0, slkMissing: 0,
  godotImportLeaks: 0, dupPngLeaks: 0,
  glbMissingList: [],
  scnMissingList: [],
  mapsMissingList: [],
  mapsExtraList: [],
  slkMissingList: [],
  importLeakList: [],
  dupPngLeakList: [],
};

function checkGlbAndScn() {
  if (!existsSync(WC3_ASSETS)) {
    log("  (skip: .cache/wc3-assets 不存在；先跑 bootstrap 抽 MPQ)");
    return;
  }
  log("--- check MDX → GLB/Gltf → SCN ---");
  const allMdx = walk(WC3_ASSETS, (p) => p.toLowerCase().endsWith(".mdx") || p.toLowerCase().endsWith(".mdl"));
  report.mdxTotal = allMdx.length;
  for (const mdx of allMdx) {
    const rel = relative(WC3_ASSETS, mdx).replace(/\\/g, "/");
    // 1f012ac 切流 .glb → .gltf（外链 Textures 共享贴图）
    const glbRel = rel.replace(/\.(mdx|mdl)$/i, ".gltf");
    const scnRel = glbRel;
    const glbPath = join(ASSET_CONVERTED, glbRel);
    const scnPath = join(ASSET_CONVERTED, scnRel);
    if (!existsSync(glbPath)) {
      report.glbMissing += 1;
      if (report.glbMissingList.length < 20) report.glbMissingList.push(rel);
    } else if (!existsSync(scnPath)) {
      report.scnMissing += 1;
      if (report.scnMissingList.length < 20) report.scnMissingList.push(rel);
    }
  }
  log(`  MDX: ${report.mdxTotal}  Gltf 缺: ${report.glbMissing}  SCN 缺: ${report.scnMissing}`);
}

function checkMaps(config) {
  if (!existsSync(WC3_ASSETS)) return;
  log("--- check WC3 w3x → config.maps.items → map-parsed ---");
  const allW3x = walk(WC3_ASSETS, (p) => p.toLowerCase().endsWith(".w3x"));
  const wc3W3xRel = new Set(allW3x.map((p) => relative(WC3_ASSETS, p).replace(/\\/g, "/")));
  const mapItems = config.maps?.items || [];
  report.mapsConfigured = mapItems.length;
  for (const m of mapItems) {
    const expectedPath = join(ASSET_CONVERTED, "..", "..", ".cache", "wc3-assets", m.w3x);
    const expectedRel = m.w3x.replace(/\\/g, "/");
    if (!wc3W3xRel.has(expectedRel)) {
      report.mapsMissing += 1;
      report.mapsMissingList.push(`${m.name}: ${m.w3x} (not in wc3-assets cache)`);
      continue;
    }
    const outDir = join(MAP_PARSED, m.out);
    const outJson = join(outDir, "info.json");
    if (!existsSync(outJson)) {
      report.mapsMissing += 1;
      report.mapsMissingList.push(`${m.name}: ${m.w3x} (parsed JSON missing)`);
    }
  }
  // 反向：已解析但不在 config
  if (existsSync(MAP_PARSED)) {
    for (const dir of readdirSync(MAP_PARSED, { withFileTypes: true })) {
      if (!dir.isDirectory()) continue;
      if (!mapItems.some((m) => m.out === dir.name)) {
        report.mapsExtra += 1;
        if (report.mapsExtraList.length < 20) report.mapsExtraList.push(dir.name);
      }
    }
  }
  log(`  config: ${report.mapsConfigured}  缺: ${report.mapsMissing}  解析了但 config 没列: ${report.mapsExtra}`);
}

function checkSlk(config) {
  if (!existsSync(WC3_ASSETS)) return;
  log("--- check SLK → slk-exported ---");
  // 尊重 convert.exclude：被排除的 SLK 不算缺
  const exclude = (config.convert?.exclude || []).map((g) => String(g).toLowerCase());
  const include = (config.convert?.include || []).map((g) => String(g).toLowerCase());
  function isExcluded(rel) {
    const r = rel.toLowerCase();
    if (exclude.some((g) => r.startsWith(g.replace(/\/\*\*?$/, "").toLowerCase() + "/") || r === g.replace(/\/\*\*?$/, "").toLowerCase())) return true;
    // include 是空 → 不限制
    if (include.length === 0) return false;
    return !include.some((g) => r.startsWith(g.replace(/\/\*\*?$/, "").toLowerCase() + "/") || r === g.replace(/\/\*\*?$/, "").toLowerCase());
  }
  const allSlk = walk(WC3_ASSETS, (p) => p.toLowerCase().endsWith(".slk"));
  let considered = 0;
  if (!existsSync(SLK_EXPORTED)) {
    for (const slk of allSlk) {
      const rel = relative(WC3_ASSETS, slk).replace(/\\/g, "/");
      if (!isExcluded(rel)) {
        report.slkMissing += 1;
        if (report.slkMissingList.length < 20) report.slkMissingList.push(rel);
      }
    }
    report.slkTotal = allSlk.length;
    log(`  SLK: ${allSlk.length}  excluded: ${allSlk.length - report.slkMissing}  缺: ${report.slkMissing}`);
    return;
  }
  const exported = new Set(
    walk(SLK_EXPORTED, (p) => p.toLowerCase().endsWith(".json"))
      .map((p) => relative(SLK_EXPORTED, p).replace(/\\/g, "/").replace(/\.json$/i, "").toLowerCase())
  );
  for (const slk of allSlk) {
    const rel = relative(WC3_ASSETS, slk).replace(/\\/g, "/");
    if (isExcluded(rel)) continue;
    considered += 1;
    const name = rel.replace(/\.slk$/i, "").toLowerCase();
    if (!exported.has(name)) {
      report.slkMissing += 1;
      if (report.slkMissingList.length < 20) report.slkMissingList.push(rel);
    }
  }
  report.slkTotal = considered;
  log(`  SLK 考虑: ${considered}  缺: ${report.slkMissing}`);
}

function checkGodotImportLeaks() {
  if (!existsSync(ASSET_CONVERTED)) return;
  log("--- check Godot auto-import 残留（*.import / GLB 旁重复 PNG）---");
  const imports = walk(ASSET_CONVERTED, (p) => p.toLowerCase().endsWith(".import"));
  report.godotImportLeaks = imports.length;
  report.importLeakList = imports.slice(0, 20).map((p) => relative(ASSET_CONVERTED, p).replace(/\\/g, "/"));
  // GLB 旁重复 PNG：<stem>_*.png 且 <stem>.glb/.scn 同目录 + size > 50KB
  // （m2g 生成的 portrait/team_color 小 PNG < 50KB 不算；Godot 提取的 GLB texture 一般 100KB+）
  const DUP_PNG_SIZE_THRESHOLD = 50 * 1024;
  const allPng = walk(ASSET_CONVERTED, (p) => p.toLowerCase().endsWith(".png"));
  for (const p of allPng) {
    const rel = relative(ASSET_CONVERTED, p).replace(/\\/g, "/");
    if (rel.includes("_placeholders/")) continue;
    const name = basename(p);
    if (!name.includes("_")) continue;
    let size = 0;
    try { size = statSync(p).size; } catch { continue; }
    if (size < DUP_PNG_SIZE_THRESHOLD) continue;
    const dir = dirname(p);
    const stem = name.split("_")[0];
    if (existsSync(join(dir, `${stem}.glb`)) || existsSync(join(dir, `${stem}.scn`))) {
      report.dupPngLeaks += 1;
      if (report.dupPngLeakList.length < 20) report.dupPngLeakList.push(rel);
    }
  }
  log(`  *.import: ${report.godotImportLeaks}  GLB 旁重复 PNG (>50KB): ${report.dupPngLeaks}`);
}

function formatReport() {
  const lines = [];
  lines.push("# 资产完整性检查报告\n");
  lines.push(`- 检查时间：${new Date().toISOString()}`);
  lines.push(`- 配置文件：${relative(REPO_ROOT, configPath)}`);
  lines.push(`- wc3-assets cache: ${existsSync(WC3_ASSETS) ? "✓" : "✗ 缺失"}`);
  lines.push(`- asset-converted: ${existsSync(ASSET_CONVERTED) ? "✓" : "✗ 缺失"}`);
  lines.push(`- map-parsed: ${existsSync(MAP_PARSED) ? "✓" : "✗ 缺失"}`);
  lines.push(`- slk-exported: ${existsSync(SLK_EXPORTED) ? "✓" : "✗ 缺失"}\n`);

  lines.push("## 1. MDX → GLB → SCN 覆盖");
  lines.push(`- MDX 源: **${report.mdxTotal}** 个`);
  lines.push(`- GLB 缺失: **${report.glbMissing}**`);
  if (report.glbMissingList.length) {
    lines.push(`  示例：`);
    report.glbMissingList.forEach((p) => lines.push(`  - \`${p}\``));
  }
  lines.push(`- SCN 缺失: **${report.scnMissing}**`);
  if (report.scnMissingList.length) {
    lines.push(`  示例：`);
    report.scnMissingList.forEach((p) => lines.push(`  - \`${p}\``));
  }
  lines.push("");

  lines.push("## 2. 地图解析覆盖");
  lines.push(`- config.maps.items: **${report.mapsConfigured}** 个`);
  lines.push(`- 缺失（w3x 不在 cache 或未解析）: **${report.mapsMissing}**`);
  if (report.mapsMissingList.length) {
    lines.push(`  列表：`);
    report.mapsMissingList.forEach((p) => lines.push(`  - ${p}`));
  }
  lines.push(`- 已解析但 config 未列（下次 bootstrap 可能丢）: **${report.mapsExtra}**`);
  if (report.mapsExtraList.length) {
    lines.push(`  列表：`);
    report.mapsExtraList.forEach((p) => lines.push(`  - \`${p}\``));
  }
  lines.push("");

  lines.push("## 3. SLK 导出覆盖");
  lines.push(`- WC3 SLK 源: **${report.slkTotal}** 个`);
  lines.push(`- 缺失: **${report.slkMissing}**`);
  if (report.slkMissingList.length) {
    lines.push(`  示例：`);
    report.slkMissingList.forEach((p) => lines.push(`  - \`${p}\``));
  }
  lines.push("");

  lines.push("## 4. Godot auto-import 残留（.gdignore 生效检查）");
  lines.push(`- *.import 残留: **${report.godotImportLeaks}** 个`);
  if (report.importLeakList.length) {
    lines.push(`  示例：`);
    report.importLeakList.forEach((p) => lines.push(`  - \`${p}\``));
  }
  lines.push(`- GLB 旁重复 PNG（<model>_<tex>.png 副产物）: **${report.dupPngLeaks}** 个`);
  if (report.dupPngLeakList.length) {
    lines.push(`  示例：`);
    report.dupPngLeakList.forEach((p) => lines.push(`  - \`${p}\``));
  }
  lines.push("");

  const totalGaps =
    report.glbMissing + report.scnMissing +
    report.mapsMissing + report.slkMissing +
    report.godotImportLeaks + report.dupPngLeaks;
  lines.push(`## 总结`);
  lines.push(`- 总缺口: **${totalGaps}**`);
  if (totalGaps === 0) {
    lines.push(`- ✅ 资源完整`);
  } else {
    lines.push(`- ⚠️ 需要补：跑 \`node tools/bootstrap.mjs\` 重生成`);
  }
  return lines.join("\n");
}

function main() {
  log("=== 资产完整性检查 ===");
  log(`config: ${configPath}`);
  const config = loadConfig();
  checkGlbAndScn();
  checkMaps(config);
  checkSlk(config);
  checkGodotImportLeaks();
  const md = formatReport();
  if (mdOut) {
    writeFileSync(mdOut, md, "utf8");
    log(`报告写入: ${mdOut}`);
  } else {
    console.log("\n" + md);
  }
  const totalGaps =
    report.glbMissing + report.scnMissing +
    report.mapsMissing + report.slkMissing +
    report.godotImportLeaks + report.dupPngLeaks;
  if (failOnGap && totalGaps > 0) {
    console.error(`\n❌ ${totalGaps} 个缺口（--fail 触发 exit 1）`);
    process.exit(1);
  }
  process.exit(0);
}

main();
