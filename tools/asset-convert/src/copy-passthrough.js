/**
 * 无需格式转换的资源：从 extract 根（staging / 旧 cache）复制到三车道。
 * - 视觉车道 asset-converted：Sound / Fonts / PathTextures / wav·mp3·tga…
 * - 数据车道 slk-exported：UnitFunc / Ability / UI txt
 */
import fs from "node:fs";
import path from "node:path";
import { LEGACY_CACHE_ROOT } from "../../pipeline-paths.mjs";

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

/** 命令卡 UI：图标 / Buttonpos / Tip / Hotkey（非 SLK） */
const COMMAND_ABILITY_TXT_NAMES = [
  "CommandFunc.txt",
  "CommandStrings.txt",
  "CommonAbilityFunc.txt",
  "CommonAbilityStrings.txt",
  "HumanAbilityFunc.txt",
  "HumanAbilityStrings.txt",
  "OrcAbilityFunc.txt",
  "OrcAbilityStrings.txt",
  "UndeadAbilityFunc.txt",
  "UndeadAbilityStrings.txt",
  "NightElfAbilityFunc.txt",
  "NightElfAbilityStrings.txt",
  "NeutralAbilityFunc.txt",
  "NeutralAbilityStrings.txt",
  "ItemAbilityFunc.txt",
  "ItemAbilityStrings.txt",
  "CampaignAbilityFunc.txt",
  "CampaignAbilityStrings.txt",
];

/** 升级 UI：图标 / Buttonpos / Tip / Hotkey */
const UPGRADE_TXT_NAMES = [
  "HumanUpgradeFunc.txt",
  "HumanUpgradeStrings.txt",
  "OrcUpgradeFunc.txt",
  "OrcUpgradeStrings.txt",
  "UndeadUpgradeFunc.txt",
  "UndeadUpgradeStrings.txt",
  "NightElfUpgradeFunc.txt",
  "NightElfUpgradeStrings.txt",
  "NeutralUpgradeFunc.txt",
  "NeutralUpgradeStrings.txt",
  "CampaignUpgradeFunc.txt",
  "CampaignUpgradeStrings.txt",
];

const UNIT_ROOT_PREFIXES = ["", "Melee_V0/", "Melee_V1/", "Custom_V0/", "Custom_V1/"];

/**
 * 直接落入 asset-converted（不经 BLP/MDX 转码）。
 * 不含 .blp/.mdx/.mdl/.slk（各有专用管线）。
 */
const MEDIA_PASSTHROUGH_EXTS = new Set([
  ".wav",
  ".mp3",
  ".mid",
  ".dls",
  ".mrf",
  ".ttf",
  ".otf",
  ".tga",
  ".jpg",
  ".jpeg",
  ".fdf",
  ".xxx",
  ".ifl",
]);

/** 整目录镜像到 asset-converted（内含多扩展名） */
const MIRROR_DIRS = ["PathTextures", "Sound", "Fonts", "font"];

/** passthrough 树扫描时跳过（地图 / 安装包杂项，不进视觉车道） */
const SKIP_TOP_DIRS = new Set([
  "Maps",
  "BattleNet",
  "Scripts",
  "war3.exe",
]);

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

  /** staging 缺文件时回退遗留 .cache（按逻辑相对路径） */
  function resolveSrc(logical) {
    const parts = logical.split("/");
    const primary = path.join(inDir, ...parts);
    if (fs.existsSync(primary)) return primary;
    if (LEGACY_CACHE_ROOT && path.resolve(inDir) !== path.resolve(LEGACY_CACHE_ROOT)) {
      const fb = path.join(LEGACY_CACHE_ROOT, ...parts);
      if (fs.existsSync(fb)) return fb;
    }
    return primary;
  }

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

  /** @param {string} logical */
  function copyDataLogical(logical) {
    ensureCopy(resolveSrc(logical), path.join(dataOut, ...logical.split("/")));
  }

  /** @param {string} absSrc @param {string} logicalRel 相对 extract 根，正斜杠 */
  function copyConvertedLogical(absSrc, logicalRel) {
    ensureCopy(absSrc, path.join(convertedOut, ...logicalRel.split("/")));
  }

  // —— 数据车道：UnitFunc / Ability / Upgrade / UI txt ——
  for (const prefix of UNIT_ROOT_PREFIXES) {
    for (const name of UNIT_TXT_NAMES) {
      copyDataLogical(`${prefix}Units/${name}`);
    }
  }
  for (const prefix of UNIT_ROOT_PREFIXES) {
    for (const name of COMMAND_ABILITY_TXT_NAMES) {
      copyDataLogical(`${prefix}Units/${name}`);
    }
  }
  for (const prefix of UNIT_ROOT_PREFIXES) {
    for (const name of UPGRADE_TXT_NAMES) {
      copyDataLogical(`${prefix}Units/${name}`);
    }
  }
  for (const logical of DATA_FIXED) {
    copyDataLogical(logical);
  }

  // —— 视觉车道：整目录镜像 ——
  for (const dirName of MIRROR_DIRS) {
    const srcRoot = path.join(inDir, dirName);
    if (!fs.existsSync(srcRoot)) {
      // staging 缺时试 legacy cache
      const fb = path.join(LEGACY_CACHE_ROOT, dirName);
      if (!fs.existsSync(fb)) continue;
      walkMirror(fb, dirName);
      continue;
    }
    walkMirror(srcRoot, dirName);
  }

  function walkMirror(absDir, logicalPrefix) {
    for (const ent of fs.readdirSync(absDir, { withFileTypes: true })) {
      const abs = path.join(absDir, ent.name);
      const rel = logicalPrefix ? `${logicalPrefix}/${ent.name}` : ent.name;
      if (ent.isDirectory()) walkMirror(abs, rel);
      else if (ent.isFile()) copyConvertedLogical(abs, rel.replace(/\\/g, "/"));
    }
  }

  // —— 视觉车道：全树扫描剩余媒体扩展名（漏网的 wav/tga/ttf…）——
  walkMedia(inDir, "");

  function walkMedia(absDir, logicalPrefix) {
    let ents;
    try {
      ents = fs.readdirSync(absDir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const ent of ents) {
      const name = ent.name;
      if (logicalPrefix === "" && SKIP_TOP_DIRS.has(name)) continue;
      // 已整目录镜像过的不再二次扫（避免重复 stat）
      if (logicalPrefix === "" && MIRROR_DIRS.includes(name)) continue;
      const abs = path.join(absDir, name);
      const rel = logicalPrefix ? `${logicalPrefix}/${name}` : name;
      if (ent.isDirectory()) {
        walkMedia(abs, rel);
        continue;
      }
      if (!ent.isFile()) continue;
      const ext = path.extname(name).toLowerCase();
      if (!MEDIA_PASSTHROUGH_EXTS.has(ext)) continue;
      copyConvertedLogical(abs, rel.replace(/\\/g, "/"));
    }
  }

  return { copied, skipped, missing };
}
