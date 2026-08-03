#!/usr/bin/env node
/**
 * 调用 Godot headless 将 asset-converted 下 GLB 烘焙为同目录 .scn。
 * 由 npm run convert 在转完模型后自动调用；亦可单独：
 *   npm run bake:scn -- --include Units/Human/
 *
 * 需要本机 Godot 4.x（环境变量 GODOT / GODOT_BIN，或常见安装路径）。
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PACKAGE_ROOT = path.resolve(__dirname, "..");
const PROJECT_ROOT = path.resolve(PACKAGE_ROOT, "../..");

function printHelp() {
  console.log(`用法:
  npm run bake:scn -- [选项]

选项:
  --include <path>   仅烘焙逻辑路径子串匹配（可重复）
  --force            强制重烤
  --limit <n>        最多处理 n 个 GLB（调试用）
  --godot <path>     Godot 可执行文件
  -h, --help

环境变量: GODOT 或 GODOT_BIN
`);
}

function parseArgs(argv) {
  const opts = {
    include: [],
    force: false,
    limit: 0,
    godot: "",
    help: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case "-h":
      case "--help":
        opts.help = true;
        break;
      case "--force":
        opts.force = true;
        break;
      case "--include":
        if (argv[i + 1]) opts.include.push(argv[++i]);
        break;
      case "--limit":
        if (argv[i + 1]) opts.limit = Number(argv[++i]) || 0;
        break;
      case "--godot":
        if (argv[i + 1]) opts.godot = argv[++i];
        break;
      default:
        if (arg.startsWith("-")) throw new Error(`未知参数: ${arg}`);
        break;
    }
  }
  return opts;
}

function candidateGodotBins() {
  const home = os.homedir();
  const desktop = path.join(home, "Desktop");
  const list = [
    process.env.GODOT,
    process.env.GODOT_BIN,
    path.join(desktop, "Godot_v4.6.3-stable_win64_console.exe"),
    path.join(desktop, "Godot_v4.6.3-stable_win64.exe"),
    path.join(desktop, "Godot_v4.5.1-stable_win64_console.exe"),
    path.join(desktop, "Godot_v4.5.1-stable_win64.exe"),
    path.join(desktop, "Godot_v4.4.1-stable_win64_console.exe"),
    "C:\\Program Files\\Godot\\Godot_v4.exe",
    "godot",
  ].filter(Boolean);
  return list;
}

export function findGodotExecutable(explicit = "") {
  if (explicit && fs.existsSync(explicit)) return explicit;
  for (const c of candidateGodotBins()) {
    if (c === "godot") {
      const which = spawnSync(process.platform === "win32" ? "where" : "which", ["godot"], {
        encoding: "utf8",
      });
      if (which.status === 0) {
        const first = String(which.stdout || "")
          .split(/\r?\n/)
          .map((s) => s.trim())
          .find(Boolean);
        if (first) return first;
      }
      continue;
    }
    if (fs.existsSync(c)) return c;
  }
  return "";
}

/**
 * @param {{ include?: string[], force?: boolean, limit?: number, godot?: string }} opts
 * @returns {number} exit code
 */
export function bakeModelScenes(opts = {}) {
  const godot = findGodotExecutable(opts.godot || "");
  if (!godot) {
    console.warn(
      "bake:scn: 未找到 Godot。请设置环境变量 GODOT，或安装后重试。\n" +
        "  已跳过 .scn 烘焙；运行时仍可从 GLB 解析，或稍后: npm run bake:scn",
    );
    return 0;
  }

  const userArgs = [];
  for (const inc of opts.include || []) {
    userArgs.push("--include", inc);
  }
  if (opts.force) userArgs.push("--force");
  if (opts.limit > 0) userArgs.push("--limit", String(opts.limit));

  const args = [
    "--headless",
    "--path",
    PROJECT_ROOT,
    "-s",
    "res://tools/export_model_scenes.gd",
  ];
  if (userArgs.length) {
    args.push("--", ...userArgs);
  }

  console.log(`bake:scn: ${godot}`);
  console.log(`  project: ${PROJECT_ROOT}`);
  if (userArgs.length) console.log(`  args: ${userArgs.join(" ")}`);

  const r = spawnSync(godot, args, {
    cwd: PROJECT_ROOT,
    stdio: "inherit",
    shell: false,
  });
  if (r.error) {
    console.error("bake:scn: 启动 Godot 失败:", r.error.message);
    return 1;
  }
  return r.status ?? 1;
}

function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (err) {
    console.error(err.message ?? err);
    printHelp();
    process.exit(1);
  }
  if (opts.help) {
    printHelp();
    process.exit(0);
  }
  process.exit(bakeModelScenes(opts));
}

const isDirect =
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isDirect) {
  main();
}
