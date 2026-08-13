/**
 * 将运行时/编辑器依赖的数据与寻路掩码从 extract 根同步到 assets/ 三车道。
 * 优先 assets/.staging/wc3-assets；回退遗留 .cache/wc3-assets。
 *
 * 注：完整 bootstrap 已把本步并入 convert passthrough；本脚本供单独补跑。
 *
 *   UnitFunc / UnitStrings / Command* / *Ability* / UI txt → assets/slk-exported/
 *   PathTextures/**               → assets/asset-converted/
 *
 * 用法：
 *   node tools/sync-data-assets.mjs
 *   node tools/sync-data-assets.mjs --force
 */
import path from "node:path";
import { fileURLToPath } from "node:url";
import { copyPassthroughBatch } from "./asset-convert/src/copy-passthrough.js";
import { resolveExtractRoot, LEGACY_CACHE_ROOT } from "./pipeline-paths.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const DATA_ROOT = path.join(REPO_ROOT, "assets", "slk-exported");
const CONVERTED_ROOT = path.join(REPO_ROOT, "assets", "asset-converted");

function parseArgs(argv) {
  return {
    force: argv.includes("--force"),
    help: argv.includes("-h") || argv.includes("--help"),
  };
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    console.log(`用法: node tools/sync-data-assets.mjs [--force]

从 staging（或遗留 .cache）同步：
  · UnitFunc / UnitStrings / Command* / *Ability* / UI txt → assets/slk-exported/
  · PathTextures/**               → assets/asset-converted/
`);
    return;
  }

  const extracted = resolveExtractRoot();
  if (extracted.kind === "missing") {
    console.error(
      `未找到 staging (${path.relative(REPO_ROOT, extracted.root)}) 或遗留 cache，请先 bootstrap / mpq-extract`,
    );
    process.exitCode = 1;
    return;
  }
  if (extracted.kind === "legacy-cache") {
    console.warn(
      `[sync-data-assets] staging 不存在，回退 ${path.relative(REPO_ROOT, LEGACY_CACHE_ROOT)}`,
    );
  }

  console.log("sync-data-assets");
  console.log(`  in:         ${extracted.root}`);
  console.log(`  data out:   ${DATA_ROOT}`);
  console.log(`  visual out: ${CONVERTED_ROOT}`);

  const r = copyPassthroughBatch({
    inDir: extracted.root,
    convertedOut: CONVERTED_ROOT,
    dataOut: DATA_ROOT,
    force: opts.force,
  });
  console.log(
    `完成: copied=${r.copied} skipped=${r.skipped} missing=${r.missing}`,
  );
}

main();
