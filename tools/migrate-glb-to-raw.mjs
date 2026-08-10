#!/usr/bin/env node
// 一次性迁移：将 assets/asset-converted/ 下所有 *.glb 移到 <同目录>/raw/<同名>.glb
// 并在 raw/ 下放空 .gdignore 阻止 Godot 编辑器 auto-import。
//
// 运行：node tools/migrate-glb-to-raw.mjs [--dry-run] [--root <path>]
//
// 迁移后删 assets/asset-converted/.gdignore（顶层），编辑器就能 FileSystem 看到 .scn/.png/.json
// 但看不到 raw/ 子目录里的 .glb。

import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
let dryRun = false;
let rootIdx = args.indexOf("--root");
const rootArg = rootIdx >= 0 ? args[rootIdx + 1] : null;
if (args.includes("--dry-run")) dryRun = true;

const projectRoot = path.resolve(
  path.dirname(new URL(import.meta.url).pathname.replace(/^\//, "")),
  "..",
);
const root = path.resolve(projectRoot, rootArg ?? "assets/asset-converted");

if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
  console.error(`[migrate-glb-to-raw] root not found: ${root}`);
  process.exit(2);
}

const IGNORE_BODY = "## Godot: 文件存在即忽略此目录（防止 GLB auto-import）。\n";

// 1) 收集所有 *.glb + *.glb.bin（递归；GLB 外部 BIN chunk）
const glbFiles = [];
(function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      // 已经迁移过的 raw/ 跳过（不再下钻，避免二次迁移）
      if (entry.name === "raw" && path.dirname(full) !== root) {
        continue;
      }
      walk(full);
    } else if (entry.isFile()) {
      const lower = entry.name.toLowerCase();
      if (lower.endsWith(".glb") || lower.endsWith(".glb.bin")) {
        glbFiles.push(full);
      }
    }
  }
})(root);

console.log(`[migrate-glb-to-raw] found ${glbFiles.length} .glb under ${root}`);

let moved = 0;
let skipped = 0;
const touchedRawDirs = new Set();

for (const glbAbs of glbFiles) {
  const parent = path.dirname(glbAbs);
  const base = path.basename(glbAbs);
  const rawDir = path.join(parent, "raw");
  const dest = path.join(rawDir, base);

  if (parent.endsWith(`/${"raw"}`) || parent.endsWith("\\raw")) {
    // 已经在 raw/ 下了，跳过
    skipped += 1;
    continue;
  }

  if (dryRun) {
    console.log(`  [DRY] ${path.relative(root, glbAbs)} -> raw/${base}`);
  } else {
    fs.mkdirSync(rawDir, { recursive: true });
    fs.renameSync(glbAbs, dest);
    touchedRawDirs.add(rawDir);
    moved += 1;
  }
}

// 2) 每个 raw/ 写 .gdignore
let gdignoreWritten = 0;
for (const rawDir of touchedRawDirs) {
  const gi = path.join(rawDir, ".gdignore");
  if (dryRun) {
    console.log(`  [DRY] write ${path.relative(root, gi)}`);
  } else {
    fs.writeFileSync(gi, IGNORE_BODY);
    gdignoreWritten += 1;
  }
}

console.log(
  `[migrate-glb-to-raw] moved=${moved} skipped=${skipped} raw_dirs=${touchedRawDirs.size} gdignore=${gdignoreWritten} dry_run=${dryRun}`,
);

if (dryRun) {
  console.log(
    "[migrate-glb-to-raw] dry-run only; re-run without --dry-run to apply.",
  );
}