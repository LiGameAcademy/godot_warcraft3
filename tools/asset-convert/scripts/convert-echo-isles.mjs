#!/usr/bin/env node
/**
 * Echo Isles / 人族 Melee 开发所需贴图+模型子集（比全量 convert 快很多）。
 * 覆盖：Lordaeron 地形/树/水、人族建筑与基础单位、中立建筑、野怪、常用纹理。
 */
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pkg = path.resolve(__dirname, "..");

const includes = [
  // HUD icons and selection feedback are independent of model dependencies.
  "ReplaceableTextures/CommandButtons*/**",
  "ReplaceableTextures/PassiveButtons*/**",
  "ReplaceableTextures/Selection/**",
  "UI/**",
  // 地形 / 悬崖 / 水 / 树
  "TerrainArt/LordaeronSummer/**",
  "ReplaceableTextures/Cliff/**",
  "ReplaceableTextures/LordaeronTree/**",
  "ReplaceableTextures/Water/**",
  "ReplaceableTextures/Splash/**",
  "Textures/ShorelineParticleXY.blp",
  "Textures/White_64_Foam1.blp",
  "Textures/gutz.blp",
  "Textures/Clouds8x8Fog.blp",
  // 天空 / 昼夜
  "Environment/Sky/**",
  "Environment/DNC/**",
  // 装饰物（Echo Isles 常用）
  "Doodads/LordaeronSummer/**",
  "Doodads/Terrain/LordaeronTree/**",
  "Doodads/Terrain/Cityscape/**",
  // 中立建筑（Echo Isles：金矿/酒馆/商店/雇佣兵营/集市/鱼人小屋等）
  "Buildings/Other/**",
  "buildings/other/**",
  // 野怪 / 小动物（同目录 PNG；缺贴图会粉模）
  "Units/Creeps/**",
  "units/creeps/**",
  "Units/Critters/**",
  "units/critters/**",
  // 人族建筑 + 基础单位（Melee 开局）
  "Buildings/Human/**",
  "buildings/human/**",
  "Units/Human/Peasant/**",
  "Units/Human/Footman/**",
  "Units/Human/Knight/**",
  "Units/Human/Rifleman/**",
  "Units/Human/Priest/**",
  "Units/Human/Sorceress/**",
  "Units/Human/MortarTeam/**",
  "Units/Human/GyroCopter/**",
  "Units/Human/GryphonRider/**",
  "Units/Human/HeroPaladin/**",
  "Units/Human/HeroArchMage/**",
  "Units/Human/HeroMountainKing/**",
  "Units/Human/HeroBloodElf/**",
  "Units/Human/HeroBloodMage/**",
  "Textures/Footman.blp",
  "Textures/Peasant.blp",
  "Textures/Human*.blp",
  // UI 光标 / 选中相关常用贴图
  "UI/Cursor/**",
  "UI/Feedback/**",
  "ReplaceableTextures/TeamColor/**",
  "ReplaceableTextures/TeamGlow/**",
  // 地面道具（宝箱等）；缺 PNG 会白模 / 只剩星星光晕
  "Objects/InventoryItems/**",
  "objects/InventoryItems/**",
];

const extra = process.argv.slice(2);
const args = ["src/cli.js"];
if (!extra.includes("--force") && !extra.includes("--no-force")) {
  // 默认增量；用户可显式 --force
}
for (const g of includes) {
  args.push("--include", g);
}
args.push(...extra.filter((a) => a !== "--no-force"));

console.log("convert-echo-isles →", includes.length, "include globs");
const r = spawnSync(process.execPath, args, {
  cwd: pkg,
  stdio: "inherit",
  shell: false,
});
process.exit(r.status ?? 1);
