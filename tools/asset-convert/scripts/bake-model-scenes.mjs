#!/usr/bin/env node
/**
 * 调用 Godot headless 将 asset-converted 下 GLB 烘焙为同目录 .scn。
 * 由 npm run convert 在转完模型后自动调用；亦可单独：
 *   npm run bake:scn -- --include Units/Human/
 *
 * 需要本机 Godot 4.x（环境变量 GODOT / GODOT_BIN，或常见安装路径）。
 */
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  findGodotExecutable,
  runGodotScript,
  PROJECT_ROOT,
} from "../../lib/godot-cli.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

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

export { findGodotExecutable };

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

  console.log(`bake:scn: project=${PROJECT_ROOT}`);
  return runGodotScript({
    scriptRes: "res://tools/export_model_scenes.gd",
    userArgs,
    godot,
    required: false,
  });
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
