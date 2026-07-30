/**
 * 将编辑器运行时需要的 WC3 逻辑路径文件，从 .cache/wc3-assets
 * 同步到 assets/asset-converted（保持相同相对路径）。
 *
 * AssetProvider 解析顺序：converted → cache，故同步后优先读 converted。
 * 注意：内容仍属暴雪资产，保持 gitignore，勿提交（见 docs/data/LEGAL.md）。
 *
 * 用法：
 *   node tools/sync-editor-assets.mjs
 *   node tools/sync-editor-assets.mjs --force
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const CACHE_ROOT = path.join(REPO_ROOT, ".cache", "wc3-assets");
const OUT_ROOT = path.join(REPO_ROOT, "assets", "asset-converted");

/** 编辑器当前实际依赖的逻辑路径（可按需增补） */
const EDITOR_LOGICAL_PATHS = [
  "UI/WorldEditData.txt",
  "UI/WorldEditStrings.txt",
  "UI/WorldEditGameStrings.txt",
];

function parseArgs(argv) {
  return { force: argv.includes("--force"), help: argv.includes("-h") || argv.includes("--help") };
}

function ensureCopy(logical, force) {
  const src = path.join(CACHE_ROOT, ...logical.split("/"));
  const dst = path.join(OUT_ROOT, ...logical.split("/"));
  if (!fs.existsSync(src)) {
    return { logical, ok: false, reason: `missing cache: ${src}` };
  }
  if (!force && fs.existsSync(dst)) {
    const ss = fs.statSync(src);
    const ds = fs.statSync(dst);
    if (ss.size === ds.size && ss.mtimeMs <= ds.mtimeMs) {
      return { logical, ok: true, skipped: true };
    }
  }
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.copyFileSync(src, dst);
  return { logical, ok: true, skipped: false, bytes: fs.statSync(dst).size };
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    console.log(`用法: node tools/sync-editor-assets.mjs [--force]

将编辑器所需 UI 配置从 .cache/wc3-assets 拷到 assets/asset-converted。
`);
    return;
  }
  if (!fs.existsSync(CACHE_ROOT)) {
    console.error(`未找到 ${CACHE_ROOT}，请先运行 tools/mpq-extract`);
    process.exitCode = 1;
    return;
  }
  console.log("sync-editor-assets");
  console.log(`  cache: ${CACHE_ROOT}`);
  console.log(`  out:   ${OUT_ROOT}`);
  let copied = 0;
  let skipped = 0;
  let failed = 0;
  for (const logical of EDITOR_LOGICAL_PATHS) {
    const r = ensureCopy(logical, opts.force);
    if (!r.ok) {
      failed += 1;
      console.error(`ERR  ${r.logical}: ${r.reason}`);
      continue;
    }
    if (r.skipped) {
      skipped += 1;
      console.log(`SKIP ${r.logical}`);
    } else {
      copied += 1;
      console.log(`OK   ${r.logical}  (${r.bytes} bytes)`);
    }
  }
  console.log(`\n完成: 复制 ${copied}，跳过 ${skipped}，失败 ${failed}`);
  if (failed) process.exitCode = 1;
}

main();
