#!/usr/bin/env node
// tools/mark-no-scn.mjs
// 2026-08-10：标记"不需要 .scn 烘焙"的 GLB（GLB 本身不能 bake 或纯装饰）
// ──────────────────────────────────────────────────────────────
// 数据文件：assets/asset-converted/.no-scn（每行一个 glb 路径，POSIX 风格）
// 被 export_model_scenes.gd 读：已标 → skip（不算 failed）
// 被 check-scn-coverage.mjs 读：已标 → 不计入缺漏
//
// 跑法：
//   node tools/mark-no-scn.mjs --list                     # 列已标
//   node tools/mark-no-scn.mjs --add <path1> [path2 ...]  # 加若干
//   node tools/mark-no-scn.mjs --remove <path>            # 删
//   node tools/mark-no-scn.mjs --check <path>             # 查
//   node tools/mark-no-scn.mjs --from-glob <glob>         # 批量加（minimatch glob）
//   node tools/mark-no-scn.mjs --from-report <md-path>    # 从 SCN_COVERAGE.md 抽 `- \`path 批量加

import {
  existsSync,
  readFileSync,
  writeFileSync,
  readdirSync,
  statSync,
} from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = resolve(__dirname, "..");
const MARK_FILE = join(REPO_ROOT, "assets", "asset-converted", ".no-scn");
const ASSET_CONVERTED = join(REPO_ROOT, "assets", "asset-converted");

const args = process.argv.slice(2);

function readSet() {
  /** @type {Set<string>} */
  const s = new Set();
  if (!existsSync(MARK_FILE)) return s;
  const text = readFileSync(MARK_FILE, { encoding: "utf8" });
  for (const line of text.split(/\r?\n/)) {
    const t = line.trim();
    if (t && !t.startsWith("#")) s.add(t);
  }
  return s;
}

function writeSet(set) {
  const sorted = [...set].sort();
  const header = [
    "# 标记为 _no_scn 的 GLB 列表（export_model_scenes.gd 跳过）",
    "# 每行一个 glb 路径，POSIX 风格（用 / 分隔）",
    "# 用 tools/mark-no-scn.mjs 维护",
    "",
  ].join("\n");
  const text = header + sorted.join("\n") + "\n";
  // 自动写父目录（assets/asset-converted/ 已存在）
  writeFileSync(MARK_FILE, text, { encoding: "utf8" });
}

function toPosixPath(p) {
  // 转 POSIX；去掉前导 "./" 或 "../" 或盘符
  let s = p.replace(/\\/g, "/");
  // 去掉绝对路径前缀到 assets/asset-converted
  const idx = s.lastIndexOf("asset-converted/");
  if (idx >= 0) s = s.slice(idx + "asset-converted/".length);
  // 去掉前导 ./
  while (s.startsWith("./")) s = s.slice(2);
  return s;
}

function globAdd(pattern) {
  // 扫 ASSET_CONVERTED 下所有 .glb，匹配简单 glob（** + *）
  /** @param {string} dir @returns {string[]} */
  function walk(dir) {
    /** @type {string[]} */
    const out = [];
    let entries;
    try { entries = readdirSync(dir, { withFileTypes: true }); }
    catch { return out; }
    for (const e of entries) {
      const p = join(dir, e.name);
      if (e.isDirectory()) {
        out.push(...walk(p));
      } else if (e.isFile() && p.toLowerCase().endsWith(".glb")) {
        out.push(p);
      }
    }
    return out;
  }
  // 简单 glob 匹配：** 匹配任意层级（含空），* 匹配单段（不含 /）
  function matchGlob(s, pat) {
    // 转义 . + ? ( ) | ^ $ 之外的 regex 字符
    const re = new RegExp(
      "^" +
        pat
          .split("**")
          .map((seg, i) =>
            seg
              .split("*")
              .map((s2) =>
                s2.replace(/[.+?^${}()|[\]\\]/g, "\\$&")
              )
              .join("[^/]*")
          )
          .join(".*") +
        "$"
    );
    return re.test(s);
  }
  const all = walk(ASSET_CONVERTED);
  const matched = [];
  for (const p of all) {
    const rel = toPosixPath(p);
    if (matchGlob(rel, pattern)) {
      matched.push(rel);
    }
  }
  return matched;
}

function fromReport(mdPath) {
  if (!existsSync(mdPath)) {
    console.error(`❌ 报告不存在：${mdPath}`);
    process.exit(1);
  }
  const text = readFileSync(mdPath, { encoding: "utf8" });
  /** @type {string[]} */
  const paths = [];
  // 匹配 `- \`xxx/yyy.glb\`` 模式
  const re = /^- `([^`]+\.glb)`/gm;
  let m;
  while ((m = re.exec(text)) !== null) {
    paths.push(m[1]);
  }
  return paths;
}

function main() {
  if (args.length === 0 || args.includes("--help") || args.includes("-h")) {
    console.log(`mark-no-scn: 维护"不需要 .scn 烘焙"的 GLB 列表

用法:
  node tools/mark-no-scn.mjs --list                       列已标
  node tools/mark-no-scn.mjs --add <path> [...]          加若干（可重复）
  node tools/mark-no-scn.mjs --remove <path> [...]       删若干
  node tools/mark-no-scn.mjs --check <path>              查是否已标
  node tools/mark-no-scn.mjs --from-glob <glob>          批量加（minimatch glob，如 "Environment/**"）
  node tools/mark-no-scn.mjs --from-report <md-path>     从 SCN_COVERAGE.md 抽 \- \`path.glb\` 批量加

数据文件:
  ${MARK_FILE}    (每行一个 glb 路径，POSIX 风格)

集成点:
  export_model_scenes.gd  读 .no-scn → skip
  check-scn-coverage.mjs  排除已标 GLB（不计入缺漏）
`);
    return;
  }

  const cmd = args[0];
  const set = readSet();
  const initial = set.size;

  if (cmd === "--list") {
    if (set.size === 0) {
      console.log("[mark-no-scn] 列表为空");
      return;
    }
    console.log(`[mark-no-scn] 已标 ${set.size} 个：`);
    for (const p of [...set].sort()) console.log("  " + p);
    return;
  }

  if (cmd === "--check") {
    const target = args[1];
    if (!target) {
      console.error("❌ --check 需要 <path>");
      process.exit(1);
    }
    const posix = toPosixPath(target);
    if (set.has(posix)) {
      console.log(`✅ 已标：${posix}`);
    } else {
      console.log(`❌ 未标：${posix}`);
      process.exit(1);
    }
    return;
  }

  if (cmd === "--add") {
    const paths = args.slice(1);
    if (paths.length === 0) {
      console.error("❌ --add 需要至少 1 个 <path>");
      process.exit(1);
    }
    for (const p of paths) {
      const posix = toPosixPath(p);
      if (set.has(posix)) {
        console.log(`  [skip] 已存在：${posix}`);
      } else {
        set.add(posix);
        console.log(`  [add]  ${posix}`);
      }
    }
  } else if (cmd === "--remove") {
    const paths = args.slice(1);
    if (paths.length === 0) {
      console.error("❌ --remove 需要至少 1 个 <path>");
      process.exit(1);
    }
    for (const p of paths) {
      const posix = toPosixPath(p);
      if (set.has(posix)) {
        set.delete(posix);
        console.log(`  [rm]   ${posix}`);
      } else {
        console.log(`  [skip] 不存在：${posix}`);
      }
    }
  } else if (cmd === "--from-glob") {
    const pattern = args[1];
    if (!pattern) {
      console.error("❌ --from-glob 需要 <glob>");
      process.exit(1);
    }
    const matched = globAdd(pattern);
    console.log(`[mark-no-scn] glob "${pattern}" 匹配 ${matched.length} 个：`);
    for (const p of matched) {
      if (!set.has(p)) {
        set.add(p);
        console.log(`  [add]  ${p}`);
      }
    }
  } else if (cmd === "--from-report") {
    const mdPath = args[1];
    if (!mdPath) {
      console.error("❌ --from-report 需要 <md-path>");
      process.exit(1);
    }
    const paths = fromReport(mdPath);
    console.log(`[mark-no-scn] 报告 ${mdPath} 抽 ${paths.length} 个缺漏：`);
    for (const p of paths) {
      if (!set.has(p)) {
        set.add(p);
        console.log(`  [add]  ${p}`);
      }
    }
  } else {
    console.error(`❌ 未知命令：${cmd}`);
    process.exit(1);
  }

  if (set.size !== initial) {
    writeSet(set);
    console.log(`[mark-no-scn] 写入 ${set.size} 个到 ${MARK_FILE}`);
  } else {
    console.log(`[mark-no-scn] 无变化（仍 ${set.size} 个）`);
  }
}

main();
