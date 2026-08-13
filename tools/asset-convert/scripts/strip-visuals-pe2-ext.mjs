#!/usr/bin/env node
/**
 * 从 assets/visuals 下所有 .tscn 去掉 pe2.tscn ExtResource 与 Pe2Root 节点。
 * 原因：pe2 贴图在 asset-converted（.gdignore），ResourceLoader 会刷 No loader / Parse Error。
 * 运行时粒子改由 pe2.json + RuntimeAssets 组装（MapModelCache._compose_visual_packed）。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(__dirname, "../../..");
const ROOT = path.join(REPO, "assets", "visuals");

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith(".tscn")) out.push(p);
  }
  return out;
}

function strip(text) {
  const lines = text.split(/\r?\n/);
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (line.includes("ext_resource") && line.includes("pe2.tscn")) {
      i += 1;
      continue;
    }
    if (/^\[node name="Pe2Root"/.test(line)) {
      i += 1;
      while (
        i < lines.length &&
        !/^\[node /.test(lines[i]) &&
        !/^\[connection /.test(lines[i])
      ) {
        i += 1;
      }
      continue;
    }
    out.push(line);
    i += 1;
  }
  let result = out.join("\n");
  const extCount = (result.match(/^\[ext_resource/gm) || []).length;
  result = result.replace(/^(load_steps=)\d+/m, `$1${extCount + 1}`);
  result = result.replace(/\n{3,}/g, "\n\n");
  if (!result.endsWith("\n")) result += "\n";
  return result;
}

const files = walk(ROOT);
let changed = 0;
for (const f of files) {
  const before = fs.readFileSync(f, "utf8");
  if (!before.includes("pe2.tscn") && !before.includes("Pe2Root")) continue;
  const after = strip(before);
  if (after !== before) {
    fs.writeFileSync(f, after);
    changed += 1;
  }
}
console.log(`strip-visuals-pe2-ext: changed=${changed} scanned=${files.length}`);
