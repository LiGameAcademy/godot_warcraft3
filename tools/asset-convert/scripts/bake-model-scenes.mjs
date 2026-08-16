#!/usr/bin/env node
/**
 * 调用 Godot headless 将 asset-converted 下 GLB 烘焙为同目录 .scn。
 * 由 npm run convert 在转完模型后自动调用；亦可单独：
 *   npm run bake:scn -- --include Units/Human/
 *
 * 并行：--workers N 启 N 个 Godot 子进程各跑 1/N 桶（hash 分桶，
 * 由 export_model_scenes.gd 的 --shard / --shard-id 配合）。
 * 默认 1（串行）；2-4 适合老 PC（每 Godot 实例 ~300-500MB 内存）。
 *
 * 需要本机 Godot 4.x（环境变量 GODOT / GODOT_BIN，或常见安装路径）。
 */
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import {
  findGodotExecutable,
  runGodotScript,
  PROJECT_ROOT,
} from "../../lib/godot-cli.mjs";
import { getLog } from "../../pipeline-log.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function printHelp() {
  console.log(`用法:
  npm run bake:scn -- [选项]

选项:
  --include <path>   仅烘焙逻辑路径子串匹配（可重复）
  --force            强制重烤
  --limit <n>        最多处理 n 个 GLB（调试用）
  --workers N        Godot 并行 worker 数（默认 1 串行；2-4 加速）
  --godot <path>     Godot 可执行文件
  -h, --help

环境变量: GODOT 或 GODOT_BIN；WORKERS 或 BAKE_WORKERS 也能设 workers。
`);
}

function parseArgs(argv) {
  const opts = {
    include: [],
    force: false,
    limit: 0,
    workers: Number(process.env.WORKERS || process.env.BAKE_WORKERS) || 1,
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
      case "--workers":
        if (argv[i + 1]) opts.workers = Math.max(1, Number(argv[++i]) || 1);
        break;
      case "--godot":
        if (argv[i + 1]) opts.godot = argv[i + 1];
        break;
      default:
        if (arg.startsWith("-")) throw new Error(`未知参数: ${arg}`);
        break;
    }
  }
  return opts;
}

export { findGodotExecutable };

/**
 * @param {{ include?: string[], force?: boolean, limit?: number, workers?: number, godot?: string }} opts
 * @returns {number} exit code
 */
export function bakeModelScenes(opts = {}) {
  const godot = findGodotExecutable(opts.godot || "");
  if (!godot) {
    getLog().warn(
      "bake:scn: 未找到 Godot，已跳过 .scn 烘焙",
      "设置 GODOT / GODOT_BIN 后可 npm run bake:scn；运行时仍可从 .gltf 解析",
    );
    return 0;
  }

  const workers = Math.max(1, Number(opts.workers) || 1);

  const baseUserArgs = [];
  for (const inc of opts.include || []) {
    baseUserArgs.push("--include", inc);
  }
  if (opts.force) baseUserArgs.push("--force");
  if (opts.limit > 0) baseUserArgs.push("--limit", String(opts.limit));

  getLog().info(`bake:scn: project=${PROJECT_ROOT} workers=${workers}`);

  if (workers === 1) {
    return runGodotScript({
      scriptRes: "res://scripts/tool/export_model_scenes.gd",
      userArgs: baseUserArgs,
      godot,
      required: false,
    });
  }

  // 并行模式：启 N 个 godot，每个跑 1/N 桶（spawn 不等结束，同时跑）
  const baseArgs = [
    "--headless",
    "--path",
    PROJECT_ROOT,
    "-s",
    "res://scripts/tool/export_model_scenes.gd",
  ];
  if (baseUserArgs.length) baseArgs.push("--", ...baseUserArgs);

  const procs = [];
  for (let k = 0; k < workers; k += 1) {
    const args = [
      ...baseArgs,
      "--shard", String(workers),
      "--shard-id", String(k),
    ];
    getLog().info(`  worker ${k + 1}/${workers}: ${path.basename(godot)}`);
    const p = spawn(godot, args, {
      cwd: PROJECT_ROOT,
      stdio: "inherit",
      shell: false,
      windowsHide: true,
      env: process.env,
    });
    procs.push(p);
  }

  // 等所有 worker 完成，聚合 exit code（用 Promise 等 close 事件拿到 status）
  return Promise.all(
    procs.map(
      (p, k) =>
        new Promise((resolveP) => {
          p.on("close", (code, signal) => {
            if (code !== 0) {
              getLog().error(`worker ${k + 1} failed: code=${code} signal=${signal}`);
            }
            resolveP(code);
          });
          p.on("error", (err) => {
            getLog().error(`worker ${k + 1} spawn error: ${err.message}`, err);
            resolveP(1);
          });
        }),
    ),
  ).then((codes) => {
    // 任意 worker 失败 → 非 0（与之前单实例 runGodotScript 行为一致）
    const maxCode = codes.reduce((acc, c) => (c !== 0 ? (acc || c || 1) : acc), 0);
    return maxCode || 0;
  });
}

async function main() {
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
  const code = await bakeModelScenes(opts);
  process.exit(code);
}

const isDirect =
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isDirect) {
  main();
}
