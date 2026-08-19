/**
 * 清掉 asset-converted 下 GLB 时代 / Godot auto-import 残留。
 *
 * 删除：
 *   - *.import
 *   - baseColor.png / baseColor_*.png（Godot 从 embed GLB 抽出）
 *   - *.glb / *.glb.bin / *.glb.glb.bin / *.glb.import
 *   - 与同目录 .gltf 的 images[].uri 无关的旁路 PNG（如 Footman_Footman.png）
 *
 * 保留：
 *   - *.gltf / *.bin / *.scn / *.pe2.json / *.geosetvis.json / *.cameras.json / *.collision.json / *.attachments.json / *.animkeys.json
 *   - Textures/、ReplaceableTextures/、_placeholders/ 下的 canonical PNG
 *   - 被本目录 .gltf URI 引用的同目录 PNG（如 TownHallCastleKeep.png）
 */
import fs from "node:fs";
import path from "node:path";

/**
 * @param {string} outDir abs path to assets/asset-converted
 * @param {{ dryRun?: boolean, include?: string[] }} [opts]
 * @returns {{ import: number, baseColor: number, glbLeftover: number, orphanPng: number, files: string[] }}
 */
export function cleanConvertedJunk(outDir, opts = {}) {
  const dryRun = Boolean(opts.dryRun);
  const include = opts.include ?? [];
  const stats = {
    import: 0,
    baseColor: 0,
    glbLeftover: 0,
    orphanPng: 0,
    files: /** @type {string[]} */ ([]),
  };

  if (!fs.existsSync(outDir) || !fs.statSync(outDir).isDirectory()) {
    return stats;
  }

  /** @param {string} abs */
  function shouldVisit(abs) {
    if (include.length === 0) return true;
    const rel = path.relative(outDir, abs).replace(/\\/g, "/");
    return include.some((g) => {
      // 简单子串 / 前缀匹配（与 convert include 风格一致）
      const needle = String(g).replace(/\\/g, "/").replace(/\*\*/g, "").replace(/\*/g, "");
      return rel.includes(needle.replace(/\/$/, "")) || rel.startsWith(needle);
    });
  }

  /** @param {string} abs @param {keyof typeof stats} bucket */
  function rm(abs, bucket) {
    const rel = path.relative(outDir, abs).replace(/\\/g, "/");
    stats[bucket] += 1;
    stats.files.push(rel);
    if (!dryRun) {
      try {
        fs.unlinkSync(abs);
      } catch {
        /* ignore */
      }
    }
  }

  // 1) 全局：import / baseColor / glb 残留
  (function walk(dir) {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (e.name === ".git") continue;
        walk(full);
        continue;
      }
      if (!e.isFile() || !shouldVisit(full)) continue;
      const lower = e.name.toLowerCase();
      if (lower.endsWith(".import")) {
        rm(full, "import");
        continue;
      }
      if (lower === "basecolor.png" || /^basecolor_\d+\.png$/i.test(e.name)) {
        rm(full, "baseColor");
        continue;
      }
      if (
        lower.endsWith(".glb") ||
        lower.endsWith(".glb.bin") ||
        lower.endsWith(".glb.glb.bin") ||
        /\.glb\./i.test(e.name)
      ) {
        rm(full, "glbLeftover");
      }
    }
  })(outDir);

  // 2) 按目录：删未被本目录 .gltf 引用的旁路 PNG
  (function walkDirs(dir) {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    const files = [];
    const subdirs = [];
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) subdirs.push(full);
      else if (e.isFile()) files.push(e.name);
    }
    for (const d of subdirs) walkDirs(d);

    const gltfs = files.filter((n) => n.toLowerCase().endsWith(".gltf"));
    if (gltfs.length === 0) return;

    // Textures / ReplaceableTextures / _placeholders 是共享根，不按「旁路」清
    const relDir = path.relative(outDir, dir).replace(/\\/g, "/").toLowerCase();
    if (
      relDir === "textures" ||
      relDir.startsWith("textures/") ||
      relDir === "replaceabletextures" ||
      relDir.startsWith("replaceabletextures/") ||
      relDir === "_placeholders" ||
      relDir.startsWith("_placeholders/")
    ) {
      return;
    }

    const keep = new Set();
    for (const gname of gltfs) {
      const gpath = path.join(dir, gname);
      let json;
      try {
        json = JSON.parse(fs.readFileSync(gpath, "utf8"));
      } catch {
        continue;
      }
      for (const im of json.images || []) {
        const uri = String(im.uri || "").replace(/\\/g, "/");
        if (uri && !uri.startsWith("data:")) {
          const resolved = path.resolve(dir, uri);
          keep.add(path.normalize(resolved).toLowerCase());
        }
        // 无 uri 时仍按 name 基名保留同目录 PNG，避免 clean 删掉后 repair 补出悬空 URI
        const nameHint = String(im.name || "").replace(/\\/g, "/");
        if (nameHint) {
          const base = path.basename(nameHint);
          if (base.toLowerCase().endsWith(".png") || base.toLowerCase().endsWith(".blp")) {
            const pngName = base.replace(/\.blp$/i, ".png");
            keep.add(path.normalize(path.join(dir, pngName)).toLowerCase());
          }
        }
      }
    }

    for (const name of files) {
      if (!name.toLowerCase().endsWith(".png")) continue;
      if (/^basecolor/i.test(name)) continue; // 已在全局步删
      const abs = path.join(dir, name);
      if (!shouldVisit(abs)) continue;
      const key = path.normalize(abs).toLowerCase();
      if (keep.has(key)) continue;
      rm(abs, "orphanPng");
    }
  })(outDir);

  return stats;
}
