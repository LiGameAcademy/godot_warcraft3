// tools/asset-convert/src/m2g-tool-version.js
// 老李 P3-9：m2g 工具版本变化自动 force 重烤
// ──────────────────────────────────────────────────────────────
// 算 src/*.js + bake 脚本的 SHA256，存到 assets/.staging/m2g-tool-hash。
// 工具代码变化时只打日志提醒，**默认不**自动全量 force（避免数小时重转）。
// 需要新算法生效：显式 --force，或 --include 子集。

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const SRC_DIR = path.dirname(__filename);

const WATCH_FILES = [
  "convert-mdx.js",
  "convert-blp.js",
  "paths.js",
  "mat4.js",
  "anim.js",
  "cli.js",
  "m2g-tool-version.js",
];

/** @param {string} rootRepo @returns {string} */
export function computeM2gToolHash(rootRepo) {
  const hash = crypto.createHash("sha256");
  for (const rel of WATCH_FILES) {
    const p = path.join(SRC_DIR, rel);
    if (!fs.existsSync(p)) continue;
    hash.update(`${rel}\0`);
    hash.update(fs.readFileSync(p));
  }
  // 同时算 scripts/bake-model-scenes.mjs 一起（m2g 跑的时候 bakes 也会跑）
  const bake = path.join(SRC_DIR, "..", "scripts", "bake-model-scenes.mjs");
  if (fs.existsSync(bake)) {
    hash.update("scripts/bake-model-scenes.mjs\0");
    hash.update(fs.readFileSync(bake));
  }
  return hash.digest("hex");
}

/**
 * 读旧 hash + 写新 hash + 判断是否 force。
 * @param {string} rootRepo
 * @param {{hashFile: string, force?: boolean}} opts
 * @returns {{ force: boolean, reason: string, hash: string }}
 */
export function reconcileM2gToolVersion(rootRepo, opts) {
  const hashFile = opts.hashFile;
  const newHash = computeM2gToolHash(rootRepo);
  let oldHash = "";
  if (fs.existsSync(hashFile)) {
    try {
      oldHash = fs.readFileSync(hashFile, "utf8").trim();
    } catch {
      oldHash = "";
    }
  }
  if (opts.force) {
    fs.mkdirSync(path.dirname(hashFile), { recursive: true });
    fs.writeFileSync(hashFile, newHash, "utf8");
    return { force: true, reason: "--force passed", hash: newHash };
  }
  if (!oldHash) {
    fs.mkdirSync(path.dirname(hashFile), { recursive: true });
    fs.writeFileSync(hashFile, newHash, "utf8");
    return { force: false, reason: "first run（写入基线 hash）", hash: newHash };
  }
  if (oldHash === newHash) {
    return { force: false, reason: "tool hash 一致（mtime 增量）", hash: newHash };
  }
  // 工具变了：默认仍走 mtime 增量，避免无意全量重转（数小时）。
  // 需要吃到新算法时显式：npm run convert -- --force 或 --include 子集。
  fs.mkdirSync(path.dirname(hashFile), { recursive: true });
  fs.writeFileSync(hashFile, newHash, "utf8");
  return {
    force: false,
    reason:
      `m2g 工具已变更（hash ${oldHash.slice(0, 12)}…→${newHash.slice(0, 12)}…）；` +
      `仍用 mtime 增量。若输出格式变了请加 --force 或 --include`,
    hash: newHash,
  };
}
