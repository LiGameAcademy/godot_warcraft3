#!/usr/bin/env node
// 一次性回退：将 raw/<Name>.glb 移回 <Name>.glb，删 raw/ 目录（连带 .gdignore）。
// 与 migrate-glb-to-raw.mjs 相反。

import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const projectRoot = path.resolve(
  path.dirname(new URL(import.meta.url).pathname.replace(/^\//, "")),
  "..",
);
const rootIdx = args.indexOf("--root");
const root = path.resolve(
  projectRoot,
  rootIdx >= 0 ? args[rootIdx + 1] : "assets/asset-converted",
);

if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
  console.error(`[rollback-glb-raw] root not found: ${root}`);
  process.exit(2);
}

// 收集所有 raw/ 目录
const rawDirs = [];
(function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const full = path.join(dir, entry.name);
    if (entry.name === "raw") {
      rawDirs.push(full);
      // 不再下钻：raw/ 子目录不应再含 raw/
      continue;
    }
    walk(full);
  }
})(root);

console.log(`[rollback-glb-raw] found ${rawDirs.length} raw/ dirs`);

let movedGlb = 0;
let removedRawDirs = 0;
for (const rawDir of rawDirs) {
  const parent = path.dirname(rawDir);
  for (const f of fs.readdirSync(rawDir, { withFileTypes: true })) {
    if (!f.isFile()) continue;
    if (!f.name.toLowerCase().endsWith(".glb")) continue;
    const src = path.join(rawDir, f.name);
    const dest = path.join(parent, f.name);
    if (dryRun) {
      console.log(`  [DRY] ${path.relative(root, src)} -> ${path.relative(root, dest)}`);
    } else {
      fs.renameSync(src, dest);
      movedGlb += 1;
    }
  }
  if (dryRun) {
    console.log(`  [DRY] rmdir ${path.relative(root, rawDir)}`);
  } else {
    fs.rmSync(rawDir, { recursive: true, force: true });
    removedRawDirs += 1;
  }
}

console.log(
  `[rollback-glb-raw] moved_glb=${movedGlb} removed_raw=${removedRawDirs} dry_run=${dryRun}`,
);