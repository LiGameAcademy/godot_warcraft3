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
//   5. asset-convert （按 config.skip.convert 跳过）
//   6. map-parse     （按 config.maps.items 列表）
//   7. slk-export    （按 config.skip.slk 跳过）
//   8. 打印 "✅ 资源就绪"
//
// 用法：
//   node tools/bootstrap.mjs [options]
//     --no-extract      跳过 mpq-extract
//     --no-convert      跳过 m2g convert
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
  readdirSync,
  rmSync,
  mkdirSync,
  writeFileSync,
} from "node:fs";
import { resolve, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

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
const log = (msg) => console.log(`[bootstrap] ${msg}`);
const vlog = (msg) => verbose && console.log(`  ${msg}`);

// ===== run subprocess =====
/** @param {{shell?: boolean, cwd?: string, env?: Record<string, string>}} [opts] */
//   opts.shell: 必须显式传；不靠推断。
//     true  → 走 cmd.exe（用于 npm 这类 .ps1 脚本）
//     false → 直接 exec（用于 node 这类真 .exe；避开 cmd.exe 对路径空格/括号的转义）
function run(cmd, cmdArgs, opts = {}) {
  const label = `${cmd} ${cmdArgs.join(" ")}`;
  vlog(`$ ${label}`);
  if (opts.shell === undefined) {
    throw new Error(`run("${cmd}", ...): opts.shell 必须显式传（true/false）`);
  }
  const result = spawnSync(cmd, cmdArgs, {
    stdio: verbose ? "inherit" : "pipe",
    cwd: opts.cwd || REPO_ROOT,
    env: { ...process.env, ...(opts.env || {}) },
    shell: opts.shell,
  });
  if (result.status !== 0) {
    console.error(`❌ ${label} failed (exit ${result.status ?? "null"})`);
    if (!verbose && result.stderr) {
      console.error(result.stderr.toString());
    }
    process.exit(result.status || 1);
  }
}

// ===== checks =====
function checkNodeMin(minMajor) {
  const major = parseInt(process.versions.node.split(".")[0], 10);
  if (Number.isNaN(major) || major < minMajor) {
    console.error(`❌ Node ${process.versions.node}, need >= ${minMajor}`);
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
    --no-parse        跳过 map-parse
    --no-slk          跳过 slk-export
    --clean           清掉本地缓存再跑（保留 .gdignore）
    --clean-imports   只清 Godot auto-import 残留（*.import + GLB 旁重复 PNG）
    --verbose         详细日志（每个子命令完整 stdout）
    --config <path>   配置文件（默认 tools/bootstrap.config.json）
    -h, --help        显示本帮助

配置：tools/bootstrap.config.json
  wc3.path / godot.path / maps.items / convert.{include,exclude} / skip.*

示例：
  # 完整跑（首次 clone）
  node tools/bootstrap.mjs

  # 只重做 slk-export（slk 表改了）
  node tools/bootstrap.mjs --no-extract --no-convert --no-parse

  # 改了 config.maps 后
  node tools/bootstrap.mjs --no-extract --no-convert

  # 清掉所有本地缓存重来
  node tools/bootstrap.mjs --clean

  # 只清 Godot auto-import 残留（不影响 GLB/.scn/canonical PNG）
  node tools/bootstrap.mjs --clean-imports
`;

const CLEAN_TARGETS = [
  "assets/asset-converted",
  "assets/model-scenes",
  "assets/pe2-prefabs",
  "assets/visuals",
  "assets/map-parsed",
  "assets/slk-exported",
  "tools/asset-convert/tmp",
  "tools/map-parse/tmp",
  "tools/mpq-extract/tmp",
  "tools/asset-convert/scripts/_additive_geoset_hits.json",
];

const GDIGNORE_REL = "assets/asset-converted/.gdignore";

function ensureGdignore() {
  // 阻止 Godot auto-import → 不在 GLB 旁生成 <model>_<tex>.png 重复副产物
  const target = join(REPO_ROOT, GDIGNORE_REL);
  if (!existsSync(target)) {
    log(`ensure ${GDIGNORE_REL}`);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, "");
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

/** 只清 Godot auto-import 残留：*.import + GLB 旁的 <model>_<tex>.png。GLB/.scn/canonical PNG 不动。 */
function cleanImports() {
  const root = join(REPO_ROOT, "assets/asset-converted");
  if (!existsSync(root)) {
    log("  (assets/asset-converted 不存在，跳过)");
    return;
  }
  let importFiles = 0;
  let dupPngs = 0;
  // 1. 全删 *.import
  const importList = walk(root, (p) => p.endsWith(".import"));
  for (const p of importList) {
    rmSync(p, { force: true });
    importFiles += 1;
  }
  // 2. GLB 旁的 <model>_<tex>.png：副产物命名形如 <glbStem>_<texStem>.png。
  //    规则：与同目录 GLB/.scn 同 stem、且文件名含 _ → 删（占位符与 canonical 不含 _，保留）。
  const pngFiles = walk(root, (p) => p.endsWith(".png"));
  for (const p of pngFiles) {
    const rel = p.slice(root.length + 1).replace(/\\/g, "/");
    if (rel.includes("_placeholders/")) continue;  // 占位符，保留
    const name = p.split(/[\\/]/).pop();
    if (!name.includes("_")) continue;  // 纯名字 PNG（canonical），保留
    const stem = name.split("_")[0];
    const dir = p.slice(0, p.length - name.length - 1);
    if (
      existsSync(join(dir, `${stem}.glb`)) ||
      existsSync(join(dir, `${stem}.scn`))
    ) {
      rmSync(p, { force: true });
      dupPngs += 1;
    }
  }
  log(`  删除 *.import：${importFiles}`);
  log(`  删除 GLB 旁重复 PNG：${dupPngs}`);
}

/** @param {(p: string) => boolean} match */
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

// ===== main =====
function main() {
  log("=== godot_warcraft3 bootstrap ===");
  log(`node ${process.versions.node}`);
  checkNodeMin(18);

  // --help
  if (hasFlag("help") || hasFlag("h")) {
    console.log(HELP_TEXT);
    process.exit(0);
  }

  const config = loadConfig();
  log(`config: ${configPath}`);

  const wc3Path = envOr(config.wc3?.path, "WC3_PATH");
  const godotPath =
    envOr(config.godot?.path, "GODOT_BIN") ||
    envOr(config.godot?.path, "GODOT");
  const skip = config.skip || {};
  const doClean = clean || skip.clean;

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
      console.error(`❌ Missing dependency: godot`);
      console.error(`   See docs/tools/ASSET_LAYOUT.md §6`);
      process.exit(1);
    }
  }
  if (wc3Path) {
    log(`WC3: ${wc3Path}`);
    if (!existsSync(join(wc3Path, "war3.mpq"))) {
      console.error(`❌ war3.mpq not found in ${wc3Path}`);
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
    process.exit(0);
  }

  // --- 4. npm install (workspaces) ---
  // npm 是 npm.ps1，shell:true 让 Windows 能 exec
  log("--- npm install (workspaces) ---");
  run("npm", ["install", "--workspaces", "--include-workspace-root"], { shell: true });

  // --- 5/6/7/8. 工具调用全部直跑 node（避开 cmd.exe wrap 路径转义） ---
  // node 是真 .exe，shell:false 也能 exec；不走 npm run 意味着路径里的空格/括号不会被 cmd.exe 转义
  // CLI 入口约定：tools/<name>/src/cli.js（与 package.json scripts: "<name>": "node src/cli.js" 对应）

  // --- 5. mpq-extract ---
  if (!skip.extract && wc3Path) {
    log("--- mpq-extract ---");
    run("node", ["tools/mpq-extract/src/cli.js", "--game-dir", wc3Path], { shell: false });
  } else {
    log("--- skip mpq-extract ---");
  }

  // --- 6. asset-convert ---
  if (!skip.convert) {
    log("--- asset-convert (m2g) ---");
    const include = (config.convert?.include || []).flatMap((g) => ["--include", g]);
    const exclude = (config.convert?.exclude || []).flatMap((g) => ["--exclude", g]);
    run("node", [
      "tools/asset-convert/src/cli.js",
      ...include, ...exclude,
    ], { shell: false });
  } else {
    log("--- skip asset-convert ---");
  }

  // --- 7. map-parse ---
  if (!skip.parse) {
    log("--- map-parse ---");
    const items = config.maps?.items || [];
    if (items.length === 0) {
      log("  (no maps in config.maps.items, skip)");
    } else {
      for (const m of items) {
        log(`  parsing ${m.name} (${m.w3x})`);
        run("node", [
          "tools/map-parse/src/cli.js",
          m.w3x, m.out,
        ], { shell: false });
      }
    }
  } else {
    log("--- skip map-parse ---");
  }

  // --- 8. slk-export ---
  if (!skip.slk) {
    log("--- slk-export ---");
    run("node", ["tools/slk-export/src/cli.js"], { shell: false });
  } else {
    log("--- skip slk-export ---");
  }

  log("=== ✅ 资源就绪 ===");
  log("下一步：godot --editor --path .");
}

main();
