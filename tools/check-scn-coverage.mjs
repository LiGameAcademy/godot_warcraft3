#!/usr/bin/env node
// tools/check-scn-coverage.mjs
// 2026-08-10 P-bake-1：检查 .scn 烘焙覆盖度（GLB → bake → 同目录 .scn）
// ──────────────────────────────────────────────────────────────
// 扫 assets/asset-converted/**/*.glb vs 同 stem .scn。
// 报告 glb 总数 / scn 总数 / 哪些 glb 没对应 scn（runtime 走 GLTFDocument 解析 + 临时注入 geosetvis）。
//
// 跑法：
//   node tools/check-scn-coverage.mjs                 # stdout 报告
//   node tools/check-scn-coverage.mjs --md <path>     # 写 markdown 报告
//   node tools/check-scn-coverage.mjs --fail          # 缺漏 > 0 时 exit 1（CI 守门）
//
// 注：
// - .scn 与 .glb 同 stem + 同目录（Foo.glb ↔ Foo.scn）
// - 不算 *.pe2.tscn（粒子 prefab，独立轨道）
// - 缺漏类型：bake 失败 / 增量没跑到 / 复杂骨骼 GLB 解析报错

import {
  existsSync,
  readdirSync,
  statSync,
  writeFileSync,
  readFileSync,
} from "node:fs";
import { resolve, join, relative, basename, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = resolve(__dirname, "..");
const ASSET_CONVERTED = join(REPO_ROOT, "assets", "asset-converted");
const NO_SCN_FILE = join(ASSET_CONVERTED, ".no-scn");

const args = process.argv.slice(2);
const mdOut = (() => {
  const i = args.indexOf("--md");
  return i >= 0 ? args[i + 1] : null;
})();
const failOnGap = args.includes("--fail");
const thresholdArg = (() => {
  const i = args.indexOf("--threshold");
  return i >= 0 ? parseFloat(args[i + 1]) : null;
})();

/** 读 .no-scn 标记文件。返回 Set<posix 路径> */
function readNoScnSet() {
  /** @type {Set<string>} */
  const s = new Set();
  if (!existsSync(NO_SCN_FILE)) return s;
  const text = readFileSync(NO_SCN_FILE, { encoding: "utf8" });
  for (const line of text.split(/\r?\n/)) {
    const t = line.trim();
    if (t && !t.startsWith("#")) s.add(t);
  }
  return s;
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

/** 从 glb 相对路径推断"分类"（Doodads / Buildings / Units / 其他）。 */
function classifyGlb(relPosix) {
  const segs = relPosix.split("/");
  if (segs.length === 0) return "其他";
  const head = segs[0];
  if (head === "Doodads" || head === "Buildings" || head === "Units") return head;
  return "其他";
}

const report = {
  glbTotal: 0,
  scnTotal: 0,
  missingList: [],      // glb 缺 scn
  orphanList: [],       // scn 无对应 glb（一般不会）
  byCategory: {},       // {Doodads: {glb, scn, missing: []}, ...}
};

function main() {
  console.log("[check-scn] === .scn 烘焙覆盖度检查 ===");
  if (!existsSync(ASSET_CONVERTED)) {
    console.error("❌ asset-converted 不存在；先跑 bootstrap");
    process.exit(1);
  }

  // 扫所有 .glb
  const allGlb = walk(ASSET_CONVERTED, (p) => {
    const l = p.toLowerCase();
    return l.endsWith(".gltf") || l.endsWith(".glb");
  });
  report.glbTotal = allGlb.length;
  console.log(`[check-scn] .glb 总数: ${report.glbTotal}`);

  // 扫所有 .scn（不含 *.pe2.tscn 粒子 prefab）
  const allScn = walk(ASSET_CONVERTED, (p) => {
    const n = p.toLowerCase();
    if (!n.endsWith(".scn")) return false;
    if (n.endsWith(".pe2.tscn")) return false;
    return true;
  });
  // scnTotal 在分类 loop 后用 category 汇总（排除已标 GLB 的 scn）
  console.log(`[check-scn] .scn 总数（含已排除）: ${allScn.length}`);  // 读 .no-scn 标记（已标 GLB 排除统计）
  const noScnSet = readNoScnSet();
  report.excluded = noScnSet.size;

  // 按 stem 收集 scn（去掉 .scn 后缀）
  const scnStems = new Set();
  for (const s of allScn) {
    const rel = relative(ASSET_CONVERTED, s).replace(/\\/g, "/");
    const stem = rel.replace(/\.scn$/, "");
    scnStems.add(stem);
  }

  // 找缺漏：glb 有但 scn 无（且未被 .no-scn 标）
  for (const g of allGlb) {
    const rel = relative(ASSET_CONVERTED, g).replace(/\\/g, "/");
    const stem = rel.replace(/\.gltf$/i, "").replace(/\.glb$/i, "");
    const cat = classifyGlb(rel);
    if (!report.byCategory[cat]) {
      report.byCategory[cat] = { glb: 0, scn: 0, missing: [], excluded: 0 };
    }
    report.byCategory[cat].glb++;
    if (noScnSet.has(rel)) {
      report.byCategory[cat].excluded++;
      continue;
    }
    // 未排除：算入 scn 计数（如果该 stem 有 scn）
    if (scnStems.has(stem)) {
      report.byCategory[cat].scn++;
    } else {
      report.missingList.push(rel);
      report.byCategory[cat].missing.push(rel);
    }
  }

  // 找孤儿：scn 有但 glb 无
  const glbStems = new Set();
  for (const g of allGlb) {
    const rel = relative(ASSET_CONVERTED, g).replace(/\\/g, "/");
    glbStems.add(rel.replace(/\.gltf$/i, "").replace(/\.glb$/i, ""));
  }
  for (const s of allScn) {
    const rel = relative(ASSET_CONVERTED, s).replace(/\\/g, "/");
    const stem = rel.replace(/\.scn$/, "");
    if (!glbStems.has(stem)) {
      report.orphanList.push(rel);
    }
  }

  // 汇总有效 scn 数（按 category 排除已标）
  let effectiveScn = 0;
  for (const s of allScn) {
    const rel = relative(ASSET_CONVERTED, s).replace(/\\/g, "/");
    const stem = rel.replace(/\.scn$/, "");
    if (!noScnSet.has(stem + ".gltf") && !noScnSet.has(stem + ".glb")) {
      effectiveScn++;
    }
  }
  report.scnTotal = effectiveScn;

  // 按 category 输出
  const cats = Object.keys(report.byCategory).sort();
  console.log(`[check-scn] === 按分类 ===`);
  for (const c of cats) {
    const s = report.byCategory[c];
    const effective = s.glb - s.excluded;
    const ratio = effective > 0 ? ((s.scn / effective) * 100).toFixed(1) : "100.0";
    console.log(
      `[check-scn] ${c.padEnd(10)} glb=${String(s.glb).padStart(5)} exc=${String(s.excluded).padStart(4)} 有效=${String(effective).padStart(4)} scn=${String(s.scn).padStart(4)} 覆盖=${ratio}% 缺漏=${s.missing.length}`
    );
  }
  console.log(`[check-scn] === 总计 ===`);
  const effectiveTotal = report.glbTotal - report.excluded;
  const totalRatio = effectiveTotal > 0
    ? ((report.scnTotal / effectiveTotal) * 100).toFixed(1)
    : "100.0";
  console.log(
    `[check-scn] glb=${report.glbTotal} exc=${report.excluded} 有效=${effectiveTotal} scn=${report.scnTotal} 覆盖=${totalRatio}% 缺漏=${report.missingList.length} 孤儿=${report.orphanList.length}`
  );

  // 列前 20 个缺漏（太多会刷屏）
  if (report.missingList.length > 0) {
    console.log(`[check-scn] === 缺漏样例（前 20） ===`);
    for (const m of report.missingList.slice(0, 20)) {
      console.log(`  - ${m}`);
    }
    if (report.missingList.length > 20) {
      console.log(`  ... +${report.missingList.length - 20} more (用 --md 导出全量)`);
    }
  }

  if (mdOut) {
    writeMarkdownReport(mdOut);
  }

  // 守门：覆盖 < 阈值则 fail
  //   --fail 等价 --threshold 100（任何缺漏都 fail）
  //   --threshold N 覆盖 < N% 则 fail
  const ratioTotal = report.glbTotal - report.excluded;
  const ratio = ratioTotal > 0
    ? (report.scnTotal / ratioTotal) * 100
    : 100.0;
  const effectiveThreshold = thresholdArg !== null ? thresholdArg : (failOnGap ? 100.0 : null);
  if (effectiveThreshold !== null) {
    if (ratio < effectiveThreshold) {
      console.error(
        `[check-scn] ❌ 覆盖 ${ratio.toFixed(1)}% < 阈值 ${effectiveThreshold}%，CI 失败（缺漏 ${report.missingList.length}）`
      );
      process.exit(1);
    }
    console.log(`[check-scn] ✅ 覆盖 ${ratio.toFixed(1)}% ≥ 阈值 ${effectiveThreshold}%`);
  }
  console.log(`[check-scn] ✅ done`);
}

function writeMarkdownReport(outPath) {
  const lines = [];
  lines.push(`# .scn 烘焙覆盖度报告`);
  lines.push(``);
  lines.push(`> 生成时间：${new Date().toISOString()}`);
  lines.push(`> 仓库：${REPO_ROOT}`);
  lines.push(``);
  lines.push(`## 总览`);
  lines.push(``);
  lines.push(`| 指标 | 数值 |`);
  lines.push(`|------|------|`);
  lines.push(`| .glb 总数 | ${report.glbTotal} |`);
  lines.push(`| 已排除（.no-scn） | ${report.excluded} |`);
  const effectiveTotal = report.glbTotal - report.excluded;
  lines.push(`| 有效 .glb | ${effectiveTotal} |`);
  lines.push(`| .scn 总数 | ${report.scnTotal} |`);
  const totalRatio = effectiveTotal > 0
    ? ((report.scnTotal / effectiveTotal) * 100).toFixed(1)
    : "0.0";
  lines.push(`| 有效覆盖率 | ${totalRatio}% |`);
  lines.push(`| 缺漏（glb 缺 scn） | ${report.missingList.length} |`);
  lines.push(`| 孤儿（scn 无 glb） | ${report.orphanList.length} |`);
  lines.push(``);
  lines.push(`## 按分类`);
  lines.push(``);
  lines.push(`| 分类 | .glb | 已排除 | 有效 | .scn | 有效覆盖率 | 缺漏 |`);
  lines.push(`|------|------|-------|------|------|-----------|------|`);
  const cats = Object.keys(report.byCategory).sort();
  for (const c of cats) {
    const s = report.byCategory[c];
    const eff = s.glb - s.excluded;
    const ratio = eff > 0 ? ((s.scn / eff) * 100).toFixed(1) + "%" : "100.0%";
    lines.push(`| ${c} | ${s.glb} | ${s.excluded} | ${eff} | ${s.scn} | ${ratio} | ${s.missing.length} |`);
  }
  lines.push(``);
  if (report.missingList.length > 0) {
    lines.push(`## 缺漏清单（${report.missingList.length} 个）`);
    lines.push(``);
    lines.push(`> 这些 glb 缺同 stem .scn；runtime 走 GLTFDocument 解析 + 临时注入 geosetvis。`);
    lines.push(`> 全 bake 命令：\`npm run bake:scn -- --force\``);
    lines.push(``);
    // 按 category 分组列
    for (const c of cats) {
      const s = report.byCategory[c];
      if (s.missing.length === 0) continue;
      lines.push(`### ${c}（${s.missing.length}）`);
      lines.push(``);
      for (const m of s.missing) {
        lines.push(`- \`${m}\``);
      }
      lines.push(``);
    }
  }
  if (report.orphanList.length > 0) {
    lines.push(`## 孤儿（scn 无 glb，${report.orphanList.length} 个）`);
    lines.push(``);
    for (const o of report.orphanList) {
      lines.push(`- \`${o}\``);
    }
    lines.push(``);
  }
  writeFileSync(outPath, lines.join("\n"), { encoding: "utf8" });
  console.log(`[check-scn] 📝 markdown 报告已写：${outPath}`);
}

main();
