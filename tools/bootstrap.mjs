#!/usr/bin/env node
// tools/bootstrap.mjs
// 一键启动 godot_warcraft3：git clone → 装 WC3 → 跑本入口 → 资源就绪
// 老李 D3 决策 (2026-08-08)：任何 wc3 资源不入 git；本入口负责本地生成
//
// 流程：
//   1. 检查 node / godot / WC3
//   2. ensure .gdignore（asset-converted/ — 阻止 Godot auto-import 生成重复贴图）
//   3. npm install（5 个子工具 workspaces）
//   4. mpq-extract   （按 config.skip.extract 跳过）
//   5. asset-convert （按 config.skip.convert 跳过；默认含 eager bake 见下）
//   6. map-parse     （按 config.maps.items 列表）
//   7. slk-export    （按 config.skip.slk 跳过）
//   8. sync-data-assets（UnitFunc/UI → slk-exported；PathTextures → converted）
//   9. 打印 "✅ 资源就绪"
//
// 关于 "asset-convert 是否含 bake"：m2g cli 默认 doScn=true（modelsOnly 模式下也跑 bake），
// 所以 asset-convert 阶段已经 = MDX → GLB → SCN 一条龙（eager bake）。
// --no-bake / config.skip.bake=true 时给 m2g 加 --skip-scn，asset-convert 只产 GLB。
//
// 用法：
//   node tools/bootstrap.mjs [options]
//     --no-extract      跳过 mpq-extract
//     --no-convert      跳过 m2g convert
//     --no-bake         asset-convert 阶段跳过 .scn bake（m2g 加 --skip-scn）
//     --no-parse        跳过 map-parse
//     --no-slk          跳过 slk-export
//     --clean           清掉本地缓存再跑（保留 .gdignore）
//     --clean-imports   只清 Godot auto-import 残留（*.import + GLB 旁重复 PNG）
//                       不会影响 GLB / .scn / canonical PNG
//     --verbose         详细日志（每个子命令完整 stdout）
//     --config <path>   配置文件（默认 tools/bootstrap.config.json）
//
// 配置：tools/bootstrap.config.json（详见 docs/tools/ASSET_LAYOUT.md §3）

import { spawnSync } from "node:child_process";
import {
  existsSync,
  readFileSync,
  rmSync,
  mkdirSync,
  writeFileSync,
} from "node:fs";
import { resolve, join, dirname, isAbsolute } from "node:path";
import { fileURLToPath } from "node:url";
import { beginSession } from "./pipeline-log.mjs";
import { PROGRESS_LOG } from "./pipeline-paths.mjs";

const __filename = fileURLToPath(import.meta.url);
const TOOLS_DIR = dirname(__filename);
const REPO_ROOT = resolve(TOOLS_DIR, "..");
const DEFAULT_CONFIG = join(TOOLS_DIR, "bootstrap.config.json");

// ===== args =====
const args = process.argv.slice(2);
const getArg = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : fallback;
};
const hasFlag = (name) => args.includes(`--${name}`);
const verbose = hasFlag("verbose");
const clean = hasFlag("clean");
const configPath = resolve(getArg("config", DEFAULT_CONFIG));

// ===== log =====
/** @type {import("./pipeline-log.mjs").PipelineLog | null} */
let plog = null;
const log = (msg) => {
  const line = `[bootstrap] ${msg}`;
  if (plog) plog.info(line);
  else console.log(line);
};
const vlog = (msg) => {
  if (!verbose) return;
  if (plog) plog.info(`  ${msg}`);
  else console.log(`  ${msg}`);
};

function fmtSec(ms) {
  const s = ms / 1000;
  if (s < 60) return `${s.toFixed(1)}s`;
  const m = Math.floor(s / 60);
  const r = Math.round(s - m * 60);
  return `${m}m${String(r).padStart(2, "0")}s`;
}

// ===== run subprocess =====
/** @param {{shell?: boolean, cwd?: string, env?: Record<string, string>, live?: boolean}} [opts] */
//   opts.shell: 必须显式传；不靠推断。
//     true  → 走 cmd.exe（用于 npm 这类 .ps1 脚本）
//     false → 直接 exec（用于 node 这类真 .exe；避开 cmd.exe 对路径空格/括号的转义）
//   opts.live: true → 实时透出子进程输出（长阶段默认开，不必加 --verbose）
function run(cmd, cmdArgs, opts = {}) {
  const label = `${cmd} ${cmdArgs.join(" ")}`;
  vlog(`$ ${label}`);
  if (opts.shell === undefined) {
    throw new Error(`run("${cmd}", ...): opts.shell 必须显式传（true/false）`);
  }
  const live = Boolean(opts.live) || verbose;
  const t0 = Date.now();
  const result = spawnSync(cmd, cmdArgs, {
    stdio: live ? "inherit" : "pipe",
    cwd: opts.cwd || REPO_ROOT,
    env: { ...process.env, ...(opts.env || {}) },
    shell: opts.shell,
  });
  const elapsed = fmtSec(Date.now() - t0);
  if (result.status !== 0) {
    const brief = `${label} failed (exit ${result.status ?? "null"}) after ${elapsed}`;
    if (plog) plog.fatal(brief);
    else console.error(`❌ ${brief}`);
    if (!live) {
      const detailParts = [];
      if (result.stderr?.length) detailParts.push(result.stderr.toString());
      if (result.stdout?.length) {
        const out = result.stdout.toString().trim();
        if (out) detailParts.push(out.slice(-4000));
      }
      if (detailParts.length) {
        if (plog) plog.error("subprocess output (tail)", detailParts.join("\n"));
        else {
          for (const p of detailParts) console.error(p);
        }
      }
    }
    if (plog) plog.endSession({ exit: result.status || 1 });
    process.exit(result.status || 1);
  }
  log(`  ✓ 完成（${elapsed}）`);
}

// ===== checks =====
function checkNodeMin(minMajor) {
  const major = parseInt(process.versions.node.split(".")[0], 10);
  if (Number.isNaN(major) || major < minMajor) {
    const brief = `Node ${process.versions.node}, need >= ${minMajor}`;
    if (plog) {
      plog.fatal(brief);
      plog.endSession({ exit: 1 });
    } else console.error(`❌ ${brief}`);
    process.exit(1);
  }
}

function checkDep() {
  throw new Error("checkDep 已废弃：用 main() 内的 spawnSync 显式调用");
}

function loadConfig() {
  if (!existsSync(configPath)) {
    console.error(`❌ Config not found: ${configPath}`);
    console.error(`   Copy from git or run: node tools/bootstrap.mjs --help`);
    process.exit(1);
  }
  return JSON.parse(readFileSync(configPath, "utf8"));
}

function envOr(configValue, envVar) {
  return process.env[envVar] || configValue || null;
}

const HELP_TEXT = `godot_warcraft3 bootstrap

用法：
  node tools/bootstrap.mjs [options]
    --no-extract      跳过 mpq-extract
    --no-convert      跳过 m2g convert
    --no-bake         asset-convert 阶段不烤 .scn（m2g 加 --skip-scn）
    --no-parse        跳过 map-parse
    --no-slk          跳过 slk-export
    --keep-staging    结束后保留 assets/.staging（默认删除）
    --clean           清掉本地缓存再跑（保留 .gdignore）
    --clean-imports   只清 Godot auto-import / GLB 残留（convert --clean-only）
    --verbose         详细日志（每个子命令完整 stdout）
    --config <path>   配置文件（默认 tools/bootstrap.config.json）
    -h, --help        显示本帮助

流程：MPQ → assets/.staging/wc3-assets → convert(转+复制+清理) → 删 staging → 只留 assets/ 三车道
`;

const CLEAN_TARGETS = [
  "assets/asset-converted",
  "assets/.staging",
  "assets/model-scenes",
  "assets/pe2-prefabs",
  "assets/visuals",
  "assets/map-parsed",
  "assets/slk-exported",
  ".cache",
  "tools/asset-convert/tmp",
  "tools/map-parse/tmp",
  "tools/mpq-extract/tmp",
  "tools/asset-convert/scripts/_additive_geoset_hits.json",
];

const GDIGNORE_REL = "assets/asset-converted/.gdignore";
const GDIGNORE_BODY = `## Godot: 忽略本目录，避免 auto-import .gltf/.png 生成 .import / baseColor 副产物。
## 运行时走 RuntimeAssets 磁盘路径；方案 B 外链贴图后仍建议保留本文件以免扫几千模型卡顿。
`;

function ensureGdignore() {
  const target = join(REPO_ROOT, GDIGNORE_REL);
  if (!existsSync(target)) {
    log(`ensure ${GDIGNORE_REL}`);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, GDIGNORE_BODY);
  }
}

function cleanLocal() {
  // 先备份 .gdignore，clean 完恢复
  const gdignore = join(REPO_ROOT, GDIGNORE_REL);
  const hadGdignore = existsSync(gdignore);
  let saved = null;
  if (hadGdignore) {
    saved = readFileSync(gdignore, "utf8");
  }
  for (const t of CLEAN_TARGETS) {
    const full = join(REPO_ROOT, t);
    if (existsSync(full)) {
      log(`clean ${t}`);
      rmSync(full, { recursive: true, force: true });
    }
  }
  ensureGdignore();
  if (hadGdignore && saved !== null) writeFileSync(gdignore, saved);
}

/** 委托 convert --clean-only（清 baseColor / .import / 旁路 PNG / 旧 glb）。 */
function cleanImports() {
  run("node", ["tools/asset-convert/src/cli.js", "--clean-only"], {
    shell: false,
    live: true,
  });
}

// ===== main =====
function main() {
  // --help（不写进度文档）
  if (hasFlag("help") || hasFlag("h")) {
    console.log(HELP_TEXT);
    process.exit(0);
  }

  plog = beginSession("bootstrap", { logPath: PROGRESS_LOG });
  process.env.PIPELINE_LOG = plog.logPath;

  log("=== godot_warcraft3 bootstrap ===");
  log(`node ${process.versions.node}`);
  checkNodeMin(18);

  const config = loadConfig();
  log(`config: ${configPath}`);

  const wc3Path = envOr(config.wc3?.path, "WC3_PATH");
  const godotPath =
    envOr(config.godot?.path, "GODOT_BIN") ||
    envOr(config.godot?.path, "GODOT");
  const skip = config.skip || {};
  const doClean = clean || skip.clean;
  // --no-bake 走 CLI flag；config.skip.bake 走配置文件
  const skipBake = hasFlag("no-bake") || skip.bake;

  // --- 1. check deps ---
  log("--- checking dependencies ---");
  // godot 是 .exe → shell:false 避免 cmd.exe 转义路径
  // （"godot" 走 PATH 解析；具体路径走 .exe 直 exec）
  const godotBin = godotPath || "godot";
  const godotIsExe = /\.exe$/i.test(godotBin);
  log(`godot: ${godotBin}`);
  {
    const r = spawnSync(godotBin, ["--version"], { shell: !godotIsExe });
    if (r.status !== 0) {
      if (plog) plog.fatal("Missing dependency: godot", "See docs/tools/ASSET_LAYOUT.md §6");
      else {
        console.error(`❌ Missing dependency: godot`);
        console.error(`   See docs/tools/ASSET_LAYOUT.md §6`);
      }
      plog?.endSession({ exit: 1 });
      process.exit(1);
    }
  }
  if (wc3Path) {
    log(`WC3: ${wc3Path}`);
    if (!existsSync(join(wc3Path, "war3.mpq"))) {
      plog?.fatal(`war3.mpq not found in ${wc3Path}`);
      plog?.endSession({ exit: 1 });
      process.exit(1);
    }
  } else {
    log(`WC3: (set WC3_PATH or config.wc3.path)`);
  }

  // --- 2. ensure .gdignore（防 Godot auto-import 在 GLB 旁生成重复 PNG） ---
  ensureGdignore();

  // --- 3. clean (optional) ---
  if (doClean) {
    log("--- cleaning local cache ---");
    cleanLocal();
  } else if (hasFlag("clean-imports")) {
    log("--- cleaning Godot auto-import residuals ---");
    cleanImports();
    // 纯清理操作：跑完直接退出，不再继续 npm install / 资源生成
    log("=== ✅ 清理完成（请重跑 `node tools/bootstrap.mjs` 重新生成资源）===");
    plog.endSession({ mode: "clean-imports" });
    process.exit(0);
  }

  // --- 4. npm install (workspaces) ---
  // npm 是 npm.ps1，shell:true 让 Windows 能 exec
  log("--- npm install (workspaces) ---");
  run("npm", ["install", "--workspaces", "--include-workspace-root"], {
    shell: true,
    live: true,
  });

  // --- 5/6/7/8. 工具调用全部直跑 node（避开 cmd.exe wrap 路径转义） ---
  // node 是真 .exe，shell:false 也能 exec；不走 npm run 意味着路径里的空格/括号不会被 cmd.exe 转义
  // CLI 入口约定：tools/<name>/src/cli.js（与 package.json scripts: "<name>": "node src/cli.js" 对应）
  //
  // 阶段跳过：--no-XXX CLI flag **OR** config.skip.XXX=true。两者一致，避免之前 --no-parse 装饰品 bug。
  const skipExtract = hasFlag("no-extract") || skip.extract;
  const skipConvert = hasFlag("no-convert") || skip.convert;
  const skipParse   = hasFlag("no-parse")   || skip.parse;
  const skipSlk     = hasFlag("no-slk")     || skip.slk;

  // --- 5. mpq-extract → assets/.staging/wc3-assets ---
  const stagingRoot = join(REPO_ROOT, "assets/.staging/wc3-assets");
  const stagingManifest = join(REPO_ROOT, "assets/.staging/manifest.json");
  if (!skipExtract && wc3Path) {
    log("--- mpq-extract → assets/.staging ---");
    log("  （解包 MPQ，通常数分钟；下方为子进程实时输出）");
    mkdirSync(join(REPO_ROOT, "assets/.staging"), { recursive: true });
    run("node", [
      "tools/mpq-extract/src/cli.js",
      "--game-dir", wc3Path,
      "--out", stagingRoot,
      "--manifest", stagingManifest,
    ], { shell: false, live: true });
  } else {
    log("--- skip mpq-extract ---");
  }

  // --- 6. asset-convert（清理 + BLP/MDX + passthrough + bake） ---
  if (!skipConvert) {
    if (skipBake) {
      log("--- asset-convert (含 clean/passthrough, --skip-scn) ---");
    } else {
      log("--- asset-convert (含 clean/passthrough + eager bake .scn) ---");
    }
    log("  （本阶段最久：贴图→模型→烘焙；下方会刷 [textures]/[models]/export_model_scenes 进度）");
    const include = (config.convert?.include || []).flatMap((g) => ["--include", g]);
    const exclude = (config.convert?.exclude || []).flatMap((g) => ["--exclude", g]);
    const skipScnFlag = skipBake ? ["--skip-scn"] : [];
    run("node", [
      "tools/asset-convert/src/cli.js",
      "--in", stagingRoot,
      ...include, ...exclude,
      ...skipScnFlag,
    ], { shell: false, live: true });
  } else {
    log("--- skip asset-convert ---");
  }

  // --- 7. map-parse（地图从 staging 读） ---
  if (!skipParse) {
    log("--- map-parse ---");
    const items = config.maps?.items || [];
    const cacheMapsRoot = existsSync(stagingRoot)
      ? stagingRoot
      : join(REPO_ROOT, ".cache", "wc3-assets");
    if (items.length === 0) {
      log("  (no maps in config.maps.items, skip)");
    } else {
      for (const m of items) {
        const absMap = isAbsolute(m.w3x)
          ? m.w3x
          : join(cacheMapsRoot, m.w3x);
        if (!existsSync(absMap)) {
          plog.fatal(`map not found: ${absMap}`, `config.maps item: ${m.name} / ${m.w3x}`);
          plog.endSession({ exit: 1 });
          process.exit(1);
        }
        log(`  parsing ${m.name} (${absMap})`);
        const parseArgs = [
          "tools/map-parse/src/cli.js",
          "--map", absMap,
          "--force",
        ];
        run("node", parseArgs, { shell: false, live: true });
      }
    }
  } else {
    log("--- skip map-parse ---");
  }

  // --- 8. slk-export（默认读 staging） ---
  if (!skipSlk) {
    log("--- slk-export ---");
    const slkArgs = ["tools/slk-export/src/cli.js"];
    if (existsSync(stagingRoot)) {
      slkArgs.push("--in", stagingRoot);
    }
    run("node", slkArgs, { shell: false, live: true });
  } else {
    log("--- skip slk-export ---");
  }

  // --- 9. passthrough 已并入 convert；此处仅在跳过 convert 时补跑 ---
  if (skipConvert) {
    log("--- sync-data-assets（convert 已跳过，补跑 passthrough）---");
    run("node", ["tools/sync-data-assets.mjs"], { shell: false, live: true });
  } else {
    log("--- skip sync-data-assets（已由 convert passthrough 完成）---");
  }

  // --- 10. 删除 staging（默认）；--keep-staging 保留 ---
  if (!hasFlag("keep-staging") && existsSync(join(REPO_ROOT, "assets/.staging"))) {
    log("--- remove assets/.staging ---");
    rmSync(join(REPO_ROOT, "assets/.staging"), { recursive: true, force: true });
  }

  log("=== ✅ 资源就绪 ===");
  log("下一步：godot --editor --path .");
  plog.endSession({ ok: true });
}

main();
