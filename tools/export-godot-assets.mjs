#!/usr/bin/env node
/**
 * 统一调用 Godot headless 导出运行时友好资产：
 *   1) GLB → .scn（bake）
 *   2) pe2.json → assets/pe2-prefabs/*.pe2.tscn（GPU 粒子预制）
 *   3) .scn + PE2 → assets/visuals/*.tscn（可提交视觉封装）
 *
 * 用法:
 *   node tools/export-godot-assets.mjs
 *   node tools/export-godot-assets.mjs --include Buildings/Human/ --force
 *   node tools/export-godot-assets.mjs --skip-bake --pe2-only
 *   node tools/export-godot-assets.mjs --godot "D:/Godot/Godot_v4.6_console.exe"
 */
import path from "node:path";
import { fileURLToPath } from "node:url";
import { findGodotExecutable, runGodotScript } from "./lib/godot-cli.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function printHelp() {
  console.log(`用法: node tools/export-godot-assets.mjs [选项]

选项:
  --include <path>   逻辑路径子串过滤（可重复；默认 Buildings/Human/）
  --force            强制重导出
  --skip-bake        跳过 GLB→.scn
  --skip-pe2         跳过 PE2 预制
  --skip-visuals     跳过 visuals 封装
  --bake-only        只 bake .scn
  --pe2-only         只导 PE2
  --visuals-only     只导 visuals
  --godot <path>     Godot 可执行文件
  -h, --help
`);
}

function parseArgs(argv) {
  const opts = {
    include: [],
    force: false,
    skipBake: false,
    skipPe2: false,
    skipVisuals: false,
    bakeOnly: false,
    pe2Only: false,
    visualsOnly: false,
    godot: "",
    help: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    switch (a) {
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
      case "--skip-bake":
        opts.skipBake = true;
        break;
      case "--skip-pe2":
        opts.skipPe2 = true;
        break;
      case "--skip-visuals":
        opts.skipVisuals = true;
        break;
      case "--bake-only":
        opts.bakeOnly = true;
        break;
      case "--pe2-only":
        opts.pe2Only = true;
        break;
      case "--visuals-only":
        opts.visualsOnly = true;
        break;
      case "--godot":
        if (argv[i + 1]) opts.godot = argv[++i];
        break;
      default:
        if (a.startsWith("-")) throw new Error(`未知参数: ${a}`);
        break;
    }
  }
  if (opts.bakeOnly) {
    opts.skipPe2 = true;
    opts.skipVisuals = true;
  }
  if (opts.pe2Only) {
    opts.skipBake = true;
    opts.skipVisuals = true;
  }
  if (opts.visualsOnly) {
    opts.skipBake = true;
    opts.skipPe2 = true;
  }
  if (opts.include.length === 0) {
    opts.include.push("Buildings/Human/");
  }
  return opts;
}

function userArgs(opts) {
  const out = [];
  for (const inc of opts.include) out.push("--include", inc);
  if (opts.force) out.push("--force");
  return out;
}

function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (e) {
    console.error(e.message ?? e);
    printHelp();
    process.exit(1);
  }
  if (opts.help) {
    printHelp();
    process.exit(0);
  }

  const godot = findGodotExecutable(opts.godot);
  if (!godot) {
    console.error(
      "未找到 Godot。请设置 GODOT 环境变量，例如:\n" +
        '  $env:GODOT = "D:\\Godot\\Godot_v4.6.3-stable_win64_console.exe"',
    );
    process.exit(1);
  }
  console.log(`export-godot-assets → Godot=${godot}`);

  const ua = userArgs(opts);
  let code = 0;

  if (!opts.skipBake) {
    console.log("\n=== [1/3] bake GLB → .scn ===");
    code = runGodotScript({
      scriptRes: "res://tools/export_model_scenes.gd",
      userArgs: ua,
      godot,
    });
    if (code !== 0) process.exit(code);
  }

  if (!opts.skipPe2) {
    console.log("\n=== [2/3] export PE2 prefabs ===");
    code = runGodotScript({
      scriptRes: "res://tools/export_pe2_scenes.gd",
      userArgs: ua,
      godot,
    });
    if (code !== 0) process.exit(code);
  }

  if (!opts.skipVisuals) {
    console.log("\n=== [3/3] export visuals ===");
    code = runGodotScript({
      scriptRes: "res://tools/export_visual_scenes.gd",
      userArgs: ua,
      godot,
    });
    if (code !== 0) process.exit(code);
  }

  console.log("\nexport-godot-assets: 完成");
  process.exit(0);
}

const isDirect =
  process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirect) main();
