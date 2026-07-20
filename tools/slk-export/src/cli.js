#!/usr/bin/env node
import path from "node:path";
import { fileURLToPath } from "node:url";
import { exportSlkBatch } from "./export-slk.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PACKAGE_ROOT = path.resolve(__dirname, "..");
const REPO_ROOT = path.resolve(PACKAGE_ROOT, "../..");

const DEFAULT_EXCLUDE = [
  "File*.slk",
  "**/NotUsed_*.slk",
  "Custom_V0/**",
  "Custom_V1/**",
  "Melee_V0/**",
];

function printHelp() {
  console.log(`用法:
  npm run export -- [选项]

将经典 WC3 .slk（SYLK 表）解析为 JSON / CSV。
默认读取 .cache/wc3-assets，写出到 assets/slk-exported。

选项:
  --in <path>           解包资产根目录（默认: ../../.cache/wc3-assets）
  --out <path>          输出根目录（默认: ../../assets/slk-exported）
  --format <list>       导出格式，逗号分隔：json,csv（默认两者都导出）
  --force               覆盖已有导出
  --include <glob>      仅包含逻辑路径（可重复）
  --exclude <glob>      排除逻辑路径（可重复；默认已排除 File*.slk / NotUsed / 旧版本目录）
  --no-default-exclude  不使用默认排除规则
  --compact             JSON 不缩进
  -h, --help            帮助

示例:
  npm run export --
  npm run export -- --include "Units/**" --force
  npm run export -- --include "Units/UnitData.slk" --include "Units/unitUI.slk"
  npm run export -- --include "TerrainArt/**" --format csv
`);
}

function parseArgs(argv) {
  const opts = {
    inDir: path.join(REPO_ROOT, ".cache", "wc3-assets"),
    outDir: path.join(REPO_ROOT, "assets", "slk-exported"),
    formats: /** @type {('json'|'csv')[]} */ (["json", "csv"]),
    force: false,
    include: /** @type {string[]} */ ([]),
    exclude: /** @type {string[]} */ ([]),
    useDefaultExclude: true,
    pretty: true,
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
      case "--compact":
        opts.pretty = false;
        break;
      case "--no-default-exclude":
        opts.useDefaultExclude = false;
        break;
      case "--in":
        opts.inDir = path.resolve(argv[++i] ?? opts.inDir);
        break;
      case "--out":
        opts.outDir = path.resolve(argv[++i] ?? opts.outDir);
        break;
      case "--format": {
        const list = String(argv[++i] ?? "json,csv")
          .split(",")
          .map((s) => s.trim().toLowerCase())
          .filter(Boolean);
        opts.formats = /** @type {('json'|'csv')[]} */ (
          list.filter((f) => f === "json" || f === "csv")
        );
        if (!opts.formats.length) throw new Error("--format 需包含 json 或 csv");
        break;
      }
      case "--include":
        if (argv[i + 1]) opts.include.push(argv[++i]);
        break;
      case "--exclude":
        if (argv[i + 1]) opts.exclude.push(argv[++i]);
        break;
      default:
        if (arg.startsWith("-")) throw new Error(`未知参数: ${arg}`);
        break;
    }
  }

  if (opts.useDefaultExclude) {
    opts.exclude = [...DEFAULT_EXCLUDE, ...opts.exclude];
  }
  return opts;
}

function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (e) {
    console.error(String(e));
    process.exitCode = 1;
    return;
  }

  if (opts.help) {
    printHelp();
    return;
  }

  console.log("godot_warcraft3 SLK 导出");
  console.log(`  in:      ${opts.inDir}`);
  console.log(`  out:     ${opts.outDir}`);
  console.log(`  formats: ${opts.formats.join(",")}`);
  console.log(`  force:   ${opts.force}`);
  if (opts.include.length) console.log(`  include: ${opts.include.join(", ")}`);
  if (opts.exclude.length) console.log(`  exclude: ${opts.exclude.join(", ")}`);

  const result = exportSlkBatch(opts);
  console.log(
    `\n完成: 导出 ${result.converted}，跳过 ${result.skipped}，错误 ${result.errors}`,
  );
  console.log(`索引: ${path.join(opts.outDir, "index.json")}`);
  if (result.errors) process.exitCode = 1;
}

main();
