/**
 * 无需格式转换的资源：从 extract 根（staging / 旧 cache）直接复制到三车道。
 * 合并原 sync-data-assets 职责，供 convert/ingest 一次完成。
 */
import fs from "node:fs";
import path from "node:path";

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

const UNIT_ROOT_PREFIXES = ["", "Melee_V0/", "Melee_V1/", "Custom_V0/", "Custom_V1/"];

/**
 * @param {{
 *   inDir: string,
 *   convertedOut: string,
 *   dataOut: string,
 *   force?: boolean,
 * }} opts
 */
export function copyPassthroughBatch(opts) {
  const { inDir, convertedOut, dataOut, force = false } = opts;
  let copied = 0;
  let skipped = 0;
  let missing = 0;

  /** @param {string} src @param {string} dst */
  function ensureCopy(src, dst) {
    if (!fs.existsSync(src)) {
      missing += 1;
      return;
    }
    if (!force && fs.existsSync(dst)) {
      const ss = fs.statSync(src);
      const ds = fs.statSync(dst);
      if (ss.size === ds.size && ss.mtimeMs <= ds.mtimeMs) {
        skipped += 1;
        return;
      }
    }
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(src, dst);
    copied += 1;
  }

  // UnitFunc / UnitStrings
  for (const prefix of UNIT_ROOT_PREFIXES) {
    for (const name of UNIT_TXT_NAMES) {
      const logical = `${prefix}Units/${name}`;
      ensureCopy(path.join(inDir, ...logical.split("/")), path.join(dataOut, ...logical.split("/")));
    }
  }

  // UI txt
  for (const logical of DATA_FIXED) {
    ensureCopy(path.join(inDir, ...logical.split("/")), path.join(dataOut, ...logical.split("/")));
  }

  // PathTextures/**
  const ptSrc = path.join(inDir, "PathTextures");
  const ptDst = path.join(convertedOut, "PathTextures");
  if (fs.existsSync(ptSrc)) {
    (function walk(dir, relBase) {
      for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
        const abs = path.join(dir, ent.name);
        const rel = relBase ? `${relBase}/${ent.name}` : ent.name;
        if (ent.isDirectory()) walk(abs, rel);
        else if (ent.isFile()) {
          ensureCopy(abs, path.join(ptDst, ...rel.split("/")));
        }
      }
    })(ptSrc, "");
  }

  return { copied, skipped, missing };
}
