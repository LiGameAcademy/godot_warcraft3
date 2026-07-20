#!/usr/bin/env node
/**
 * Download official ANSI StormLib Windows x64 DLL (Ladislav Zezula release).
 * This is the StormLib library itself — not Blizzard game assets.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PACKAGE_ROOT = path.resolve(__dirname, "..");
const VENDOR = path.join(PACKAGE_ROOT, "vendor", "stormlib");
const VERSION = "v9.40";
// Release / ANSI / Dynamic (DLL)
const URL = `https://github.com/ladislav-zezula/StormLib/releases/download/${VERSION}/stormlib_v9.40_amd64_RAD.zip`;

const dllPath = path.join(VENDOR, "StormLib.dll");
if (fs.existsSync(dllPath) && !process.argv.includes("--force")) {
  console.log(`已存在: ${dllPath}`);
  process.exit(0);
}

fs.mkdirSync(VENDOR, { recursive: true });
const zipPath = path.join(VENDOR, "stormlib_ansi_amd64.zip");

console.log(`下载 ${URL}`);
execFileSync("curl", ["-L", "-o", zipPath, URL], { stdio: "inherit" });

console.log(`解压到 ${VENDOR}`);
execFileSync(
  "powershell",
  [
    "-NoProfile",
    "-Command",
    `Expand-Archive -Path '${zipPath.replace(/'/g, "''")}' -DestinationPath '${VENDOR.replace(/'/g, "''")}' -Force`,
  ],
  { stdio: "inherit" },
);

if (!fs.existsSync(dllPath)) {
  // Some zips nest one level — search.
  const found = fs
    .readdirSync(VENDOR, { recursive: true })
    .map((f) => path.join(VENDOR, f))
    .find((f) => f.endsWith("StormLib.dll") && fs.statSync(f).isFile());
  if (found && found !== dllPath) {
    fs.copyFileSync(found, dllPath);
  }
}

if (!fs.existsSync(dllPath)) {
  console.error("解压后未找到 StormLib.dll");
  process.exit(1);
}

console.log("完成:", dllPath);
