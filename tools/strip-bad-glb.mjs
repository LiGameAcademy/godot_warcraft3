#!/usr/bin/env node
// 一次性清理：扫描 assets/asset-converted/ 下所有 *.glb，
// 凡是头部不是 ASCII "glTF" 二进制签名（= NodeIO 误输出的 JSON 文本），删掉。
// 删后下次 convert（已修 .glb.tmp）会重新生成二进制版。

import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const rootIdx = args.indexOf("--root");
const projectRoot = path.resolve(
  path.dirname(new URL(import.meta.url).pathname.replace(/^\//, "")),
  "..",
);
const root = path.resolve(
  projectRoot,
  rootIdx >= 0 ? args[rootIdx + 1] : "assets/asset-converted",
);

if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
  console.error(`[strip-bad-glb] root not found: ${root}`);
  process.exit(2);
}

const SIG = Buffer.from([0x67, 0x6c, 0x54, 0x46]); // 'g','l','T','F'
let scanned = 0;
let bad = 0;
const removed = [];

(function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full);
      continue;
    }
    if (!entry.isFile()) continue;
    if (!entry.name.toLowerCase().endsWith(".glb")) continue;
    scanned += 1;
    let head;
    try {
      const fd = fs.openSync(full, "r");
      const buf = Buffer.alloc(4);
      fs.readSync(fd, buf, 0, 4, 0);
      fs.closeSync(fd);
      head = buf;
    } catch {
      continue;
    }
    if (head.equals(SIG)) continue;
    bad += 1;
    const rel = path.relative(root, full).replace(/\\/g, "/");
    removed.push(rel);
    if (!dryRun) {
      fs.unlinkSync(full);
    }
  }
})(root);

console.log(
  `[strip-bad-glb] scanned=${scanned} bad=${bad} removed=${
    dryRun ? "(dry-run)" : removed.length
  }`,
);
for (const r of removed) {
  console.log(`  ${r}`);
}
if (dryRun) {
  console.log("[strip-bad-glb] dry-run; re-run without --dry-run to apply.");
}