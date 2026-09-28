import fs from "node:fs";
import path from "node:path";
import { mdxLogicalToCameras, mdxLogicalToCollision, mdxLogicalToModelIr, mdxLogicalToGeosetVis, mdxLogicalToGltf, mdxLogicalToPe2 } from "./paths.js";
import { walkFiles } from "./walk.js";
import { getLog } from "../../pipeline-log.mjs";

import { convertOneMdx } from "./mdx-gltf.js";
export { convertOneMdx } from "./mdx-gltf.js";
export { parseModel } from "./mdx-skeleton.js";
export { extractRibbons } from "./mdx-effects-sidecars.js";
export { writeCamerasSidecar } from "./mdx-effects-sidecars.js";
export { extractAttachments, writeAttachmentsSidecar } from "./mdx-attachments.js";

/** 合法 .gltf：JSON 且含 asset.version（方案 B 外链贴图）。 */
export function isValidGltfOnDisk(absPath) {
  let fd;
  try {
    fd = fs.openSync(absPath, "r");
  } catch {
    return false;
  }
  try {
    const stat = fs.fstatSync(fd);
    if (stat.size < 32) return false;
    const n = Math.min(stat.size, 256);
    const buf = Buffer.alloc(n);
    fs.readSync(fd, buf, 0, n, 0);
    const head = buf.toString("utf8").trimStart();
    if (!head.startsWith("{")) return false;
    return /"asset"\s*:/.test(head);
  } finally {
    try {
      fs.closeSync(fd);
    } catch {
      /* ignore */
    }
  }
}

export function unlinkQuiet(p) {
  try {
    fs.unlinkSync(p);
  } catch {
    /* ignore */
  }
}

export async function convertMdxBatch(options) {
  const { inDir, outDir, force, include, exclude } = options;
  const files = walkFiles(inDir, new Set([".mdx", ".mdl"]), include, exclude);

  let converted = 0;
  let skipped = 0;
  let errors = 0;

  const log = getLog();
  log.info(`\n[models] 发现 ${files.length} 个 .mdx/.mdl`);

  const t0 = Date.now();
  let processed = 0;
  for (const file of files) {
    const gltfLogical = mdxLogicalToGltf(file.logicalPath);
    const dest = path.join(outDir, ...gltfLogical.split("/"));
    const pe2Dest = path.join(outDir, ...mdxLogicalToPe2(file.logicalPath).split("/"));
    const geosetVisDest = path.join(
      outDir,
      ...mdxLogicalToGeosetVis(file.logicalPath).split("/"),
    );
    const camDest = path.join(
      outDir,
      ...mdxLogicalToCameras(file.logicalPath).split("/"),
    );
    const collisionDest = path.join(
      outDir,
      ...mdxLogicalToCollision(file.logicalPath).split("/"),
    );
    const irDest = path.join(outDir, ...mdxLogicalToModelIr(file.logicalPath).split("/"));

    if (
      !force &&
      fs.existsSync(dest) &&
      fs.existsSync(pe2Dest) &&
      fs.existsSync(geosetVisDest) &&
      fs.existsSync(camDest) &&
      fs.existsSync(collisionDest) &&
      fs.existsSync(irDest)
    ) {
      const srcStat = fs.statSync(file.absPath);
      const dstStat = fs.statSync(dest);
      const pe2Stat = fs.statSync(pe2Dest);
      const visStat = fs.statSync(geosetVisDest);
      const camStat = fs.statSync(camDest);
      const collisionStat = fs.statSync(collisionDest);
      const valid = isValidGltfOnDisk(dest);
      if (
        dstStat.mtimeMs >= srcStat.mtimeMs &&
        dstStat.size > 0 &&
        valid &&
        pe2Stat.mtimeMs >= srcStat.mtimeMs &&
        visStat.mtimeMs >= srcStat.mtimeMs &&
        camStat.mtimeMs >= srcStat.mtimeMs &&
        collisionStat.mtimeMs >= srcStat.mtimeMs &&
        fs.statSync(irDest).mtimeMs >= srcStat.mtimeMs
      ) {
        skipped += 1;
        processed += 1;
        if (processed % 50 === 0 || processed === files.length) {
          const sec = ((Date.now() - t0) / 1000).toFixed(1);
          log.progress(
            `[models] progress ${processed}/${files.length} converted=${converted} skipped=${skipped} errors=${errors} (${sec}s)`,
          );
        }
        continue;
      }
      if (!valid && dstStat.size > 0) {
        unlinkQuiet(dest);
        unlinkQuiet(dest.replace(/\.gltf$/i, ".bin"));
      }
    }

    try {
      await convertOneMdx(file.absPath, file.logicalPath, inDir, outDir);
      converted += 1;
    } catch (err) {
      const brief = `失败 ${file.logicalPath}: ${err instanceof Error ? err.message : err}`;
      log.error(brief, err);
      errors += 1;
    }
    processed += 1;
    if (processed % 50 === 0 || processed === files.length) {
      const sec = ((Date.now() - t0) / 1000).toFixed(1);
      log.progress(
        `[models] progress ${processed}/${files.length} converted=${converted} skipped=${skipped} errors=${errors} (${sec}s)`,
      );
    }
  }

  log.info(`[models] 完成: 转换 ${converted}, 跳过 ${skipped}, 错误 ${errors}`);
  return { converted, skipped, errors, fileCount: files.length };
}
