#!/usr/bin/env node
/**
 * Convert textures/models needed to visually restore Lost Temple.
 */
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pkg = path.resolve(__dirname, "..");

const includes = [
  // Terrain
  "TerrainArt/Icecrown/**",
  "ReplaceableTextures/Cliff/**",
  "ReplaceableTextures/LordaeronTree/**",
  "ReplaceableTextures/AshenvaleTree/**",
  "ReplaceableTextures/Water/**",
  "Textures/ShorelineParticleXY.blp",
  "Textures/White_64_Foam1.blp",
  "Doodads/LordaeronSummer/Water/**",
  // Trees / rocks / props
  // Trees: living variants 0-9 (skip *D dead / *S stump for now via exclude below)
  "Doodads/Terrain/LordaeronTree/LordaeronTree?.mdx",
  "Doodads/Terrain/AshenTree/AshenTree?.mdx",
  "Doodads/Icecrown/**",
  "Doodads/Northrend/Water/**",
  "Doodads/Northrend/Props/Bats/**",
  "Doodads/Ashenvale/Water/Fish/**",
  // Buildings
  "Buildings/Other/GoldMine/**",
  "buildings/other/GoldMine/**",
  "Buildings/Other/FountainOfLife/**",
  "buildings/other/FountainOfLife/**",
  "Buildings/Other/Merchant/**",
  "buildings/other/Merchant/**",
  "Buildings/Other/AmmoDump/**",
  "buildings/other/AmmoDump/**",
  // Creeps (Lost Temple set)
  "Units/Creeps/IceTroll/**",
  "units/creeps/IceTroll/**",
  "Units/Creeps/IceTrollShadowPriest/**",
  "units/creeps/IceTrollShadowPriest/**",
  "Units/Creeps/Mammoth/**",
  "Units/Creeps/Archnathid/**",
  "Units/Creeps/FacelessOne/**",
  "Units/Creeps/AzureDragon/**",
  "units/creeps/AzureDragon/**",
  "Units/Creeps/Nerubian/**",
  "units/creeps/Nerubian/**",
  "Units/Creeps/NerubianSpiderLord/**",
  "units/creeps/NerubianSpiderLord/**",
  "Units/Creeps/NerubianQueen/**",
  "units/creeps/NerubianQueen/**",
  "Units/Creeps/tuskarRanged/**",
  "Units/Creeps/tuskarLord/**",
  "Units/Creeps/PolarFurbolgTracker/**",
  "units/creeps/PolarFurbolgTracker/**",
  "Units/Creeps/DragonSpawnPurple/**",
  "Units/Creeps/PolarBear/**",
  "units/creeps/PolarBear/**",
];

const args = ["src/cli.js", "--force"];
for (const g of includes) {
  args.push("--include", g);
}

console.log("convert-lost-temple →", includes.length, "include globs");
const r = spawnSync(process.execPath, args, {
  cwd: pkg,
  stdio: "inherit",
  shell: false,
});
process.exit(r.status ?? 1);
