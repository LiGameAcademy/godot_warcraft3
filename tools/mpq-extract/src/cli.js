#!/usr/bin/env node
import path from "node:path";
import { fileURLToPath } from "node:url";
import { detectClassicMpqs } from "./detect.js";
import { extractMpqs } from "./extract.js";
import { resolveFromPackage } from "./paths.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PACKAGE_ROOT = path.resolve(__dirname, "..");

function printHelp() {
  console.log(`用法:
  npm run extract -- --game-dir <经典魔兽安装目录> [选项]

选项:
  --game-dir <path>   经典 WC3 安装目录（必需，含 War3.mpq 等）
  --out <path>        解包输出目录（默认: ../../assets/.staging/wc3-assets）
  --manifest <path>   manifest 路径（默认: ../../assets/.staging/manifest.json）
  --force             忽略增量缓存，全量重解
  --include <glob>    仅包含匹配的逻辑路径（可重复）
  --exclude <glob>    排除匹配的逻辑路径（可重复）
  -h, --help          显示帮助

示例:
  npm run extract -- --game-dir "C:/Games/Warcraft III"
  npm run extract -- --game-dir "D:/WC3" --include "Units/**" --include "UI/**"
`);
}

/**
 * @param {string[]} argv
 */
function parseArgs(argv) {
  /** @type {{
   *   gameDir: string | null,
   *   out: string,
   *   manifest: string,
   *   force: boolean,
   *   include: string[],
   *   exclude: string[],
   *   help: boolean
   * }} */
  const opts = {
    gameDir: null,
    out: "../../assets/.staging/wc3-assets",
    manifest: "../../assets/.staging/manifest.json",
    force: false,
    include: [],
    exclude: [],
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
      case "--game-dir":
        opts.gameDir = argv[++i] ?? null;
        break;
      case "--out":
        opts.out = argv[++i] ?? opts.out;
        break;
      case "--manifest":
        opts.manifest = argv[++i] ?? opts.manifest;
        break;
      case "--include":
        if (argv[i + 1]) opts.include.push(argv[++i]);
        break;
      case "--exclude":
        if (argv[i + 1]) opts.exclude.push(argv[++i]);
        break;
      default:
        if (arg.startsWith("-")) {
          throw new Error(`未知参数: ${arg}`);
        }
        break;
    }
  }

  return opts;
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

  if (!opts.gameDir) {
    console.error("错误: 必须指定 --game-dir");
    printHelp();
    process.exit(1);
  }

  const gameDir = path.resolve(opts.gameDir);
  const outDir = resolveFromPackage(opts.out, PACKAGE_ROOT);
  const manifestPath = resolveFromPackage(opts.manifest, PACKAGE_ROOT);

  console.log("godot_warcraft3 MPQ 解包工具");
  console.log(`  game-dir: ${gameDir}`);
  console.log(`  out:      ${outDir}`);
  console.log(`  manifest: ${manifestPath}`);
  console.log(`  force:    ${opts.force}`);
  if (opts.include.length) console.log(`  include:  ${opts.include.join(", ")}`);
  if (opts.exclude.length) console.log(`  exclude:  ${opts.exclude.join(", ")}`);

  let mpqs;
  try {
    mpqs = detectClassicMpqs(gameDir);
  } catch (err) {
    console.error(err.message ?? err);
    process.exit(1);
  }

  console.log("\n将按以下顺序解包（后者覆盖前者）:");
  for (const m of mpqs) {
    console.log(`  - ${m.canonicalName}  (${m.absolutePath})`);
  }

  const result = extractMpqs({
    mpqs,
    outDir,
    manifestPath,
    gameDir,
    force: opts.force,
    include: opts.include,
    exclude: opts.exclude,
  });

  process.exit(result.errors > 0 ? 2 : 0);
}

main();
