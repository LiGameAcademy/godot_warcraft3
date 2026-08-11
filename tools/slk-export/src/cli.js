#!/usr/bin/env node
import path from "node:path";
import { fileURLToPath } from "node:url";
import { exportSlkBatch } from "./export-slk.js";
import { resolveExtractRoot, LEGACY_CACHE_ROOT } from "../../pipeline-paths.mjs";

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

将经典 WC3 .slk（SYLK 表）解析为 JSON。
默认读取 assets/.staging/wc3-assets（回退 .cache/wc3-assets），写出到 assets/slk-exported。

选项:
  --in <path>           解包资产根目录（默认: staging / 遗留 cache）
  --out <path>          输出根目录（默认: ../../assets/slk-exported）
  --overwrite           覆盖已有导出（并删除同名历史 .csv）
  --force               同 --overwrite（注意：经 npm 调用时可能被 npm 吞掉，请优先用 --overwrite）
  --include <glob>      仅包含逻辑路径（可重复）
  --exclude <glob>      排除逻辑路径（可重复；默认已排除 File*.slk / NotUsed / 旧版本目录）
  --no-default-exclude  不使用默认排除规则
  --compact             JSON 不缩进
  -h, --help            帮助

示例:
  node src/cli.js
  node src/cli.js --include "Units/**" --overwrite
  node src/cli.js --include "Units/UnitData.slk" --include "Units/unitUI.slk"
  npm run export "--" "--include=TerrainArt/**" --overwrite
`);
}

function parseArgs(argv) {
  const extracted = resolveExtractRoot();
  if (extracted.kind === "legacy-cache") {
    console.warn(
      `[slk-export] staging 不存在，回退 ${path.relative(REPO_ROOT, LEGACY_CACHE_ROOT)}`,
    );
  }
  const opts = {
    inDir: extracted.root,
    outDir: path.join(REPO_ROOT, "assets", "slk-exported"),
    force: false,
    include: /** @type {string[]} */ ([]),
    exclude: /** @type {string[]} */ ([]),
    useDefaultExclude: true,
    pretty: true,
    help: false,
  };

  // 展开 --key=value，便于 PowerShell 下 npm 传参
  /** @type {string[]} */
  const args = [];
  for (const raw of argv) {
    const eq = raw.match(/^(--[^=]+)=(.*)$/);
    if (eq) {
      args.push(eq[1], eq[2]);
    } else {
      args.push(raw);
    }
  }

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    switch (arg) {
      case "-h":
      case "--help":
        opts.help = true;
        break;
      case "--overwrite":
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
        opts.inDir = path.resolve(args[++i] ?? opts.inDir);
        break;
      case "--out":
        opts.outDir = path.resolve(args[++i] ?? opts.outDir);
        break;
      case "--format": {
        // 兼容旧参数：仅接受 json；csv 已弃用
        const list = String(args[++i] ?? "json")
          .split(",")
          .map((s) => s.trim().toLowerCase())
          .filter(Boolean);
        if (list.includes("csv")) {
          console.warn("警告: CSV 导出已弃用，将只写出 JSON。");
        }
        if (list.length && !list.includes("json")) {
          throw new Error("--format 仅支持 json（CSV 已弃用）");
        }
        break;
      }
      case "--include":
        if (args[i + 1]) opts.include.push(args[++i]);
        break;
      case "--exclude":
        if (args[i + 1]) opts.exclude.push(args[++i]);
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
  console.log(`  in:     ${opts.inDir}`);
  console.log(`  out:    ${opts.outDir}`);
  console.log(`  format: json`);
  console.log(`  force:  ${opts.force}`);
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
