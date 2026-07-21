#!/usr/bin/env node
/**
 * 从 War3x.mpq 抽出嵌套地形包 I.mpq（Icecrown），
 * 写入 ReplaceableTextures/Cliff/I_Cliff*.blp 与 Water/I_Water*.blp。
 *
 * 用法（需已 npm install mpq-extract / StormLib）：
 *   node tools/extract-icecrown-replaceables.mjs ["D:/Program Files (x86)/Warcraft3"]
 * 然后：
 *   node tools/asset-convert/src/cli.js --force --include "ReplaceableTextures/Cliff/I_Cliff*.blp" --include "ReplaceableTextures/Water/I_Water*.blp"
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  openArchive,
  closeArchive,
  extractToBuffer,
} from "./mpq-extract/src/stormlib.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const gameDir = process.argv[2] || "D:/Program Files (x86)/Warcraft3";
const war3x = path.join(gameDir, "War3x.mpq");
const cacheCliff = path.join(root, ".cache/wc3-assets/ReplaceableTextures/Cliff");
const cacheWater = path.join(root, ".cache/wc3-assets/ReplaceableTextures/Water");
const nestedDir = path.join(root, ".cache/nested");

if (!fs.existsSync(war3x)) {
  console.error("找不到 War3x.mpq:", war3x);
  process.exit(1);
}

const h = openArchive(war3x);
const iMpqBuf = extractToBuffer(h, "I.mpq");
closeArchive(h);
if (!iMpqBuf) {
  console.error("War3x 内无 I.mpq");
  process.exit(1);
}
fs.mkdirSync(nestedDir, { recursive: true });
const iMpqPath = path.join(nestedDir, "I.mpq");
fs.writeFileSync(iMpqPath, iMpqBuf);
console.log("extracted nested I.mpq", iMpqBuf.length, "bytes");

const hi = openArchive(iMpqPath);
fs.mkdirSync(cacheCliff, { recursive: true });
fs.mkdirSync(cacheWater, { recursive: true });

function pull(archiveName, destPath) {
  const buf = extractToBuffer(hi, archiveName);
  if (!buf || buf.length < 100) {
    console.warn("missing", archiveName);
    return false;
  }
  fs.writeFileSync(destPath, buf);
  console.log("→", path.relative(root, destPath), buf.length);
  return true;
}

pull("ReplaceableTextures\\Cliff\\Cliff0.blp", path.join(cacheCliff, "I_Cliff0.blp"));
pull("ReplaceableTextures\\Cliff\\Cliff1.blp", path.join(cacheCliff, "I_Cliff1.blp"));
let waterN = 0;
for (let i = 0; i < 45; i++) {
  const n = String(i).padStart(2, "0");
  if (
    pull(
      `ReplaceableTextures\\Water\\Water${n}.blp`,
      path.join(cacheWater, `I_Water${n}.blp`),
    )
  ) {
    waterN += 1;
  }
}
closeArchive(hi);
console.log("done. cliffs=2 water=", waterN);
console.log("next: convert those BLPs with asset-convert --force --include …");
