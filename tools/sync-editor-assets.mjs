/**
 * @deprecated 请用 tools/sync-data-assets.mjs。
 * 本文件保留为兼容入口（dev-setup / 旧文档），直接转调 sync-data-assets。
 */
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const target = path.join(__dirname, "sync-data-assets.mjs");
const args = process.argv.slice(2);
console.warn("[deprecated] sync-editor-assets.mjs → sync-data-assets.mjs");
const r = spawnSync(process.execPath, [target, ...args], { stdio: "inherit" });
process.exit(r.status ?? 1);
