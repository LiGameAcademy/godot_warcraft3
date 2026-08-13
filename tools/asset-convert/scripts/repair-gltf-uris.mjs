/**
 * 修复历史 convert 产物：
 * 1) buffers[].uri: Foo.partial.bin → Foo.bin（文件实际是 .bin）
 * 2) images[] 缺 uri：用 name（逻辑 PNG 路径）补相对 URI
 *
 * 用法（仓库根）：
 *   node tools/asset-convert/scripts/repair-gltf-uris.mjs
 *   node tools/asset-convert/scripts/repair-gltf-uris.mjs --include Units/Creeps/
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { uriFromModelToPng, normalizeLogicalPath } from "../src/paths.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, "../../..");
const OUT_DIR = path.join(PROJECT_ROOT, "assets", "asset-converted");

function parseArgs(argv) {
  const includes = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--include" && argv[i + 1]) {
      includes.push(String(argv[++i]).replace(/\\/g, "/"));
    }
  }
  return { includes };
}

function walkGltf(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) walkGltf(p, out);
    else if (name.toLowerCase().endsWith(".gltf")) out.push(p);
  }
  return out;
}

function matchInclude(logical, includes) {
  if (!includes.length) return true;
  const n = logical.toLowerCase();
  return includes.some((inc) => n.includes(inc.toLowerCase().replace(/\\/g, "/")));
}

function repairOne(absGltf) {
  const logical = normalizeLogicalPath(path.relative(OUT_DIR, absGltf).replace(/\\/g, "/"));
  let raw = fs.readFileSync(absGltf, "utf8");
  let doc;
  try {
    doc = JSON.parse(raw);
  } catch {
    return { ok: false, reason: "json" };
  }
  let changed = false;
  let fixedBin = 0;
  let fixedImg = 0;

  if (Array.isArray(doc.buffers)) {
    for (const buf of doc.buffers) {
      if (!buf || typeof buf.uri !== "string") continue;
      if (!buf.uri.toLowerCase().endsWith(".partial.bin")) continue;
      const next = buf.uri.replace(/\.partial\.bin$/i, ".bin");
      const nextAbs = path.join(path.dirname(absGltf), next);
      if (!fs.existsSync(nextAbs)) continue;
      buf.uri = next;
      fixedBin++;
      changed = true;
    }
  }

  if (Array.isArray(doc.images)) {
    for (const img of doc.images) {
      if (!img || typeof img !== "object") continue;
      const hasUri = typeof img.uri === "string" && img.uri.length > 0;
      if (hasUri) continue;
      const name = typeof img.name === "string" ? img.name.replace(/\\/g, "/") : "";
      if (!name || !name.toLowerCase().endsWith(".png")) continue;
      // name 已是相对 asset-converted 的逻辑路径（如 Textures/Goldmine.png）
      const uri = uriFromModelToPng(logical, name);
      const pngAbs = path.join(OUT_DIR, ...name.split("/"));
      if (!fs.existsSync(pngAbs)) {
        // 仍写 uri：运行时/后续 convert 可补；多数贴图已在 Textures/
      }
      img.uri = uri;
      if (!img.mimeType) img.mimeType = "image/png";
      fixedImg++;
      changed = true;
    }
  }

  if (!changed) return { ok: true, changed: false, fixedBin, fixedImg };
  fs.writeFileSync(absGltf, `${JSON.stringify(doc, null, 2)}\n`, "utf8");
  return { ok: true, changed: true, fixedBin, fixedImg };
}

function main() {
  const { includes } = parseArgs(process.argv.slice(2));
  const files = walkGltf(OUT_DIR).filter((abs) => {
    const logical = path.relative(OUT_DIR, abs).replace(/\\/g, "/");
    return matchInclude(logical, includes);
  });
  let scanned = 0;
  let rewritten = 0;
  let bins = 0;
  let imgs = 0;
  let errors = 0;
  for (const abs of files) {
    scanned++;
    const r = repairOne(abs);
    if (!r.ok) {
      errors++;
      continue;
    }
    if (r.changed) {
      rewritten++;
      bins += r.fixedBin;
      imgs += r.fixedImg;
    }
  }
  console.log(
    `repair-gltf-uris: scanned=${scanned} rewritten=${rewritten} binFixes=${bins} imgFixes=${imgs} errors=${errors}`,
  );
  if (errors > 0) process.exitCode = 2;
}

main();
