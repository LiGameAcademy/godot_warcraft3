import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const UNITS = path.join(ROOT, "assets/slk-exported/Units");
const OUT = path.join(ROOT, "scripts/definitions/units");

/** @type {Record<string, {className:string, table:string, file:string}>} */
const MAP = {
  "UnitData.json": { className: "UnitDataDef", table: "UnitData", file: "unit_data_def.gd" },
  "UnitBalance.json": { className: "UnitBalanceDef", table: "UnitBalance", file: "unit_balance_def.gd" },
  "unitUI.json": { className: "UnitUiDef", table: "UnitUI", file: "unit_ui_def.gd" },
  "UnitAbilities.json": { className: "UnitAbilitiesDef", table: "UnitAbilities", file: "unit_abilities_def.gd" },
  "UnitWeapons.json": { className: "UnitWeaponsDef", table: "UnitWeapons", file: "unit_weapons_def.gd" },
  "AbilityData.json": { className: "AbilityDataDef", table: "AbilityData", file: "ability_data_def.gd" },
  "AbilityMetaData.json": {
    className: "AbilityMetaDataDef",
    table: "AbilityMetaData",
    file: "ability_meta_data_def.gd",
  },
  "DestructableData.json": {
    className: "DestructableDataDef",
    table: "DestructableData",
    file: "destructable_data_def.gd",
  },
  "DestructableMetaData.json": {
    className: "DestructableMetaDataDef",
    table: "DestructableMetaData",
    file: "destructable_meta_data_def.gd",
  },
  "MiscMetaData.json": { className: "MiscMetaDataDef", table: "MiscMetaData", file: "misc_meta_data_def.gd" },
  "UnitMetaData.json": { className: "UnitMetaDataDef", table: "UnitMetaData", file: "unit_meta_data_def.gd" },
  "UpgradeData.json": { className: "UpgradeDataDef", table: "UpgradeData", file: "upgrade_data_def.gd" },
  "UpgradeMetaData.json": {
    className: "UpgradeMetaDataDef",
    table: "UpgradeMetaData",
    file: "upgrade_meta_data_def.gd",
  },
  "UpgradeEffectMetaData.json": {
    className: "UpgradeEffectMetaDataDef",
    table: "UpgradeEffectMetaData",
    file: "upgrade_effect_meta_data_def.gd",
  },
};

const BOOL_HINT = new Set([
  "valid",
  "canSleep",
  "fatLOS",
  "canFlee",
  "InBeta",
  "useInEditor",
  "hero",
  "item",
  "checkDep",
  "lightweight",
  "tilesetSpecific",
  "useClickHelper",
  "onCliffs",
  "onWater",
  "canPlaceDead",
  "walkable",
  "canPlaceRandScale",
  "fogVis",
  "showInMM",
  "useMMColor",
  "UserList",
  "selectable",
  "ignoreCD",
  "usable",
  "perishable",
  "droppable",
  "pawnable",
  "sellable",
  "pickRandom",
  "powerup",
  "drop",
  "morph",
  "special",
  "campaign",
  "inEditor",
  "hiddenInEditor",
  "hostilePal",
  "dropItems",
  "nbmmIcon",
  "scaleBull",
  "customTeamColor",
  "shadowOnWater",
  "selCircOnWater",
  "used",
  "global",
  "inherit",
  "isbldg",
  "nbrandom",
  "repulse",
  "showUI1",
  "showUI2",
  "caseSens",
  "canBeEmpty",
  "forceNonNeg",
]);

const FLOAT_HINT = new Set([
  "death",
  "moveHeight",
  "moveFloor",
  "turnRate",
  "propWin",
  "buffRadius",
  "requireWaterRadius",
  "scale",
  "minScale",
  "maxScale",
  "maxPitch",
  "maxRoll",
  "radius",
  "fogRadius",
  "selSize",
  "occH",
  "flyH",
  "fixedRot",
  "cliffHeight",
  "blend",
  "elevRad",
  "fogRad",
  "walk",
  "run",
  "selZ",
  "modelScale",
  "elevPts",
  "shadowW",
  "shadowH",
  "shadowX",
  "shadowY",
  "regenHP",
  "regenMana",
  "def",
  "defUp",
  "realdef",
  "spd",
  "minSpd",
  "maxSpd",
  "STRplus",
  "INTplus",
  "AGIplus",
  "collision",
  "acquire",
  "minRange",
  "castpt",
  "castbsw",
  "launchX",
  "launchY",
  "launchZ",
  "launchSwimZ",
  "impactZ",
  "impactSwimZ",
  "goldbase",
  "goldmod",
  "lumberbase",
  "lumbermod",
  "timebase",
  "timemod",
  "minVal",
  "maxVal",
  "selcircsize",
  "DPS",
]);

for (const n of [1, 2, 3, 4]) {
  for (const p of [
    "Cast",
    "Dur",
    "HeroDur",
    "Cool",
    "Cost",
    "Area",
    "Rng",
    "DataA",
    "DataB",
    "DataC",
    "DataD",
    "DataE",
  ]) {
    FLOAT_HINT.add(`${p}${n}`);
  }
}
for (const n of [1, 2]) {
  for (const p of [
    "rangeN",
    "RngTst",
    "RngBuff",
    "cool",
    "mincool",
    "dmgplus",
    "dmgUp",
    "mindmg",
    "avgdmg",
    "maxdmg",
    "dmgpt",
    "backSw",
    "Farea",
    "Harea",
    "Qarea",
    "Hfact",
    "Qfact",
    "damageLoss",
    "spillDist",
    "spillRadius",
    "dmod",
  ]) {
    FLOAT_HINT.add(`${p}${n}`);
  }
}
for (const n of [1, 2, 3, 4]) {
  FLOAT_HINT.add(`base${n}`);
  FLOAT_HINT.add(`mod${n}`);
}

const FILE_HINT = new Set([
  "file",
  "texFile",
  "pathTex",
  "pathTexDeath",
  "portraitmodel",
  "uberSplat",
  "unitShadow",
  "buildingShadow",
  "shadow",
]);

function toSnake(name) {
  let s = String(name).replace(/[()]/g, "");
  s = s.replace(/([a-z0-9])([A-Z])/g, "$1_$2");
  s = s.replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2");
  s = s.replace(/[^a-zA-Z0-9]+/g, "_");
  s = s.replace(/_+/g, "_").replace(/^_|_$/g, "");
  s = s.toLowerCase();
  if (s === "class") s = "class_kind";
  if (s === "classname") s = "class_kind";
  if (s === "type") s = "type_name";
  if (s === "global") s = "is_global";
  if (s === "repeat") s = "repeat_count";
  if (s === "index") s = "field_index";
  if (s === "sort") s = "sort_key";
  if (s === "code") s = "code_id";
  if (s === "section") s = "section_name";
  if (s === "display_name") s = "display_name_key";
  if (s === "range") s = "range_val";
  if (s === "match") s = "match_val";
  if (s === "signal") s = "signal_name";
  if (s === "var") s = "var_name";
  if (s === "func") s = "func_name";
  if (s === "pass") s = "pass_flag";
  if (s === "assert") s = "assert_flag";
  if (s === "preload") s = "preload_path";
  if (s === "load") s = "load_val";
  if (s === "print") s = "print_val";
  if (s === "self") s = "self_ref";
  if (s === "super") s = "super_ref";
  if (s === "pi") s = "pi_val";
  if (s === "tau") s = "tau_val";
  if (s === "inf") s = "inf_val";
  if (s === "nan") s = "nan_val";
  if (s === "await") s = "await_flag";
  if (s === "breakpoint") s = "breakpoint_flag";
  if (s === "yield") s = "yield_flag";
  if (/^\d/.test(s)) s = `n_${s}`;
  return s;
}

function inferType(header, samples) {
  if (BOOL_HINT.has(header)) return "bool";
  if (FLOAT_HINT.has(header)) return "float";
  if (FILE_HINT.has(header)) return "file";

  let sawFloat = false;
  let sawInt = false;
  let sawStr = false;
  let boolish = true;
  for (const v of samples) {
    if (v === undefined || v === null) continue;
    if (typeof v === "string") {
      const t = v.trim();
      if (t === "" || t === "_" || t === "-") continue;
      if (/^-?\d+$/.test(t)) {
        sawInt = true;
        if (t !== "0" && t !== "1") boolish = false;
      } else if (/^-?\d+\.\d+$/.test(t)) {
        sawFloat = true;
        boolish = false;
      } else {
        sawStr = true;
        boolish = false;
      }
    } else if (typeof v === "number") {
      if (!Number.isInteger(v)) {
        sawFloat = true;
        boolish = false;
      } else {
        sawInt = true;
        if (v !== 0 && v !== 1) boolish = false;
      }
    } else {
      sawStr = true;
      boolish = false;
    }
  }
  if (sawStr) return "string";
  if (sawFloat) return "float";
  if (
    sawInt &&
    boolish &&
    /^(InBeta|valid|hero|item|checkDep|used|global|inherit|morph|drop|powerup|showUI\d)$/i.test(header)
  ) {
    return "bool";
  }
  if (sawInt) return "int";
  return "string";
}

function defaultFor(t) {
  if (t === "bool") return "false";
  if (t === "int") return "0";
  if (t === "float") return "0.0";
  return '""';
}

function assignLine(prop, header, t) {
  const fallback = t === "bool" || t === "int" ? "0" : t === "float" ? "0.0" : '""';
  const g = `rec.get("${header}", ${fallback})`;
  if (t === "bool") return `\td.${prop} = int(${g}) != 0`;
  if (t === "int") return `\td.${prop} = int(${g})`;
  if (t === "float") return `\td.${prop} = float(${g})`;
  if (t === "file") return `\td.${prop} = str(${g}).replace("\\\\", "/").strip_edges()`;
  return `\td.${prop} = str(${g}).strip_edges()`;
}

function genOne(jsonFile, meta) {
  const j = JSON.parse(fs.readFileSync(path.join(UNITS, jsonFile), "utf8"));
  const headers = j.headers.filter((h) => !/^col_\d+$/.test(h));
  const records = j.records || [];
  /** @type {Record<string, unknown[]>} */
  const samples = {};
  for (const h of headers) samples[h] = [];
  for (let i = 0; i < Math.min(60, records.length); i += 1) {
    const r = records[i];
    for (const h of headers) samples[h].push(r[h]);
  }
  const pkHeader = headers[0];
  const fields = headers.map((h) => {
    let t = inferType(h, samples[h]);
    if (BOOL_HINT.has(h)) t = "bool";
    if (FLOAT_HINT.has(h)) t = "float";
    if (FILE_HINT.has(h)) t = "file";
    if (h === pkHeader) t = "string";
    let prop = toSnake(h);
    if (h === "comment(s)" || h === "comments") prop = "comment";
    if (h === "Name") prop = "name_key";
    if (h === "Level") prop = "level";
    if (h === "Primary") prop = "primary_attr";
    if (h === "STR") prop = "str_base";
    if (h === "INT") prop = "int_base";
    if (h === "AGI") prop = "agi_base";
    if (h === "name" && meta.className === "UnitUiDef") prop = "name_key";
    if (h === "class") prop = "class_kind";
    if (h === "displayName") prop = "display_name_key";
    return { h, prop, t };
  });

  const seen = new Map();
  for (const f of fields) {
    if (!seen.has(f.prop)) {
      seen.set(f.prop, 0);
      continue;
    }
    const n = seen.get(f.prop) + 1;
    seen.set(f.prop, n);
    f.prop = `${f.prop}_${n}`;
  }

  const pkProp = fields[0].prop;
  const lines = [];
  lines.push(`class_name ${meta.className}`);
  lines.push("extends Resource");
  lines.push("");
  lines.push(`## ${j.source} 一行定义。`);
  lines.push("");
  lines.push(`const TABLE_NAME := "${meta.table}"`);
  lines.push(`const SLK_REL_PATH := "Units/${jsonFile}"`);
  lines.push(`const PRIMARY_KEY := "${pkHeader}"`);
  lines.push("");
  for (const f of fields) {
    const gdType =
      f.t === "file" ? "String" : f.t === "bool" ? "bool" : f.t === "int" ? "int" : f.t === "float" ? "float" : "String";
    lines.push(`@export var ${f.prop}: ${gdType} = ${defaultFor(f.t === "file" ? "string" : f.t)}`);
  }
  lines.push("");
  lines.push("## 显示名：优先 comment/display_name_key，否则主键。");
  lines.push("func display_name() -> String:");
  const nameCandidates = fields.filter((f) =>
    ["comment", "name_key", "display_name_key", "name"].includes(f.prop),
  );
  if (nameCandidates.length) {
    lines.push(`\tvar c := ${nameCandidates[0].prop}.strip_edges()`);
    lines.push(`\treturn c if not c.is_empty() and c != "_" else ${pkProp}`);
  } else {
    lines.push(`\treturn ${pkProp}`);
  }
  lines.push("");
  lines.push(`static func from_slk_record(rec: Dictionary) -> ${meta.className}:`);
  lines.push(`\tvar d := ${meta.className}.new()`);
  for (const f of fields) {
    lines.push(assignLine(f.prop, f.h, f.t));
  }
  lines.push("\treturn d");
  lines.push("");
  lines.push("static func register_to(store: Node) -> void:");
  lines.push("\tif store == null or not store.has_method(\"register_table\"):");
  lines.push(`\t\tpush_error("${meta.className}: 无法注册到 DefStore")`);
  lines.push("\t\treturn");
  lines.push("\tstore.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)");
  lines.push("");

  fs.writeFileSync(path.join(OUT, meta.file), lines.join("\n"), "utf8");
  console.log("wrote", meta.file, "fields=", fields.length);
}

fs.mkdirSync(OUT, { recursive: true });
for (const [jsonFile, meta] of Object.entries(MAP)) {
  genOne(jsonFile, meta);
}
console.log("done");
