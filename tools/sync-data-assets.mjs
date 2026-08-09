/**
 * 将运行时/编辑器依赖的数据与寻路掩码从 .cache/wc3-assets（extract 中间态）
 * 同步到 assets/ 三车道（见 docs/architecture/ASSET_LANES.md）。
 *
 *   UnitFunc / UnitStrings / UI txt → assets/slk-exported/
 *   PathTextures/**               → assets/asset-converted/
 *
 * 用法：
 *   node tools/sync-data-assets.mjs
 *   node tools/sync-data-assets.mjs --force
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const CACHE_ROOT = path.join(REPO_ROOT, ".cache", "wc3-assets");
const DATA_ROOT = path.join(REPO_ROOT, "assets", "slk-exported");
const CONVERTED_ROOT = path.join(REPO_ROOT, "assets", "asset-converted");

const DATA_FIXED = [
  "UI/WorldEditData.txt",
  "UI/WorldEditStrings.txt",
  "UI/WorldEditGameStrings.txt",
];

const UNIT_TXT_NAMES = [
  "HumanUnitFunc.txt",
  "OrcUnitFunc.txt",
  "UndeadUnitFunc.txt",
  "NightElfUnitFunc.txt",
  "NeutralUnitFunc.txt",
  "CampaignUnitFunc.txt",
  "HumanUnitStrings.txt",
  "OrcUnitStrings.txt",
  "UndeadUnitStrings.txt",
  "NightElfUnitStrings.txt",
  "NeutralUnitStrings.txt",
  "CampaignUnitStrings.txt",
];

/** 与 Wc3IdCatalog ROOTS 对齐；仅根 Units/ 为硬依赖 */
const UNIT_ROOT_PREFIXES = ["", "Melee_V0/", "Melee_V1/", "Custom_V0/", "Custom_V1/"];

function parseArgs(argv) {
  return {
    force: argv.includes("--force"),
    help: argv.includes("-h") || argv.includes("--help"),
  };
}

function isRequiredDataLogical(logical) {
  if (DATA_FIXED.includes(logical)) return true;
  const parts = logical.split("/");
  return parts.length === 2 && parts[0] === "Units";
}

function ensureCopy(src, dst, force) {
  if (!fs.existsSync(src)) {
    return { ok: false, reason: `missing: ${src}` };
  }
  if (!force && fs.existsSync(dst)) {
    const ss = fs.statSync(src);
    const ds = fs.statSync(dst);
    if (ss.size === ds.size && ss.mtimeMs <= ds.mtimeMs) {
      return { ok: true, skipped: true };
    }
  }
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.copyFileSync(src, dst);
  return { ok: true, skipped: false, bytes: fs.statSync(dst).size };
}

function collectUnitTxtLogicals() {
  const out = [];
  for (const prefix of UNIT_ROOT_PREFIXES) {
    for (const name of UNIT_TXT_NAMES) {
      out.push(`${prefix}Units/${name}`);
    }
  }
  return out;
}

function walkFiles(absDir) {
  const out = [];
  if (!fs.existsSync(absDir)) return out;
  const stack = [absDir];
  while (stack.length) {
    const cur = stack.pop();
    for (const ent of fs.readdirSync(cur, { withFileTypes: true })) {
      const abs = path.join(cur, ent.name);
      if (ent.isDirectory()) stack.push(abs);
      else if (ent.isFile()) out.push(abs);
    }
  }
  return out;
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    console.log(`用法: node tools/sync-data-assets.mjs [--force]

从 .cache/wc3-assets 同步：
  · UnitFunc / UnitStrings / UI txt → assets/slk-exported/
  · PathTextures/**               → assets/asset-converted/
`);
    return;
  }
  if (!fs.existsSync(CACHE_ROOT)) {
    console.error(`未找到 ${CACHE_ROOT}，请先运行 tools/mpq-extract / bootstrap`);
    process.exitCode = 1;
    return;
  }

  console.log("sync-data-assets");
  console.log(`  cache:      ${CACHE_ROOT}`);
  console.log(`  data out:   ${DATA_ROOT}`);
  console.log(`  visual out: ${CONVERTED_ROOT}`);

  let copied = 0;
  let skipped = 0;
  let failed = 0;
  let missingOptional = 0;

  for (const logical of [...DATA_FIXED, ...collectUnitTxtLogicals()]) {
    const src = path.join(CACHE_ROOT, ...logical.split("/"));
    const dst = path.join(DATA_ROOT, ...logical.split("/"));
    const required = isRequiredDataLogical(logical);
    if (!fs.existsSync(src)) {
      if (required) {
        failed += 1;
        console.error(`ERR  ${logical}: missing cache`);
      } else {
        missingOptional += 1;
      }
      continue;
    }
    const r = ensureCopy(src, dst, opts.force);
    if (!r.ok) {
      failed += 1;
      console.error(`ERR  ${logical}: ${r.reason}`);
      continue;
    }
    if (r.skipped) {
      skipped += 1;
    } else {
      copied += 1;
      console.log(`OK   data ${logical}  (${r.bytes} bytes)`);
    }
  }

  const ptCache = path.join(CACHE_ROOT, "PathTextures");
  if (!fs.existsSync(ptCache)) {
    failed += 1;
    console.error("ERR  PathTextures/: missing cache");
  } else {
    for (const abs of walkFiles(ptCache)) {
      const rel = path.relative(CACHE_ROOT, abs).split(path.sep).join("/");
      const dst = path.join(CONVERTED_ROOT, ...rel.split("/"));
      const r = ensureCopy(abs, dst, opts.force);
      if (!r.ok) {
        failed += 1;
        console.error(`ERR  ${rel}: ${r.reason}`);
        continue;
      }
      if (r.skipped) skipped += 1;
      else {
        copied += 1;
        console.log(`OK   path ${rel}  (${r.bytes} bytes)`);
      }
    }
  }

  console.log(
    `\n完成: 复制 ${copied}，跳过 ${skipped}，可选缺失 ${missingOptional}，失败 ${failed}`,
  );
  if (failed) process.exitCode = 1;
}

main();
