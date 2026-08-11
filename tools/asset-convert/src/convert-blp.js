import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { PNG } from "pngjs";
import { decodeBLP, getBLPImageData } from "war3-model";
import { blpLogicalToPng } from "./paths.js";
import { walkFiles } from "./walk.js";
import { atomicWriteBytesSync } from "./atomic-write.js";
import { getLog } from "../../pipeline-log.mjs";

/**
 * @param {Buffer} blpBuffer
 * @returns {Buffer} PNG bytes
 */
export function blpBufferToPng(blpBuffer) {
  const copy = blpBuffer.buffer.slice(
    blpBuffer.byteOffset,
    blpBuffer.byteOffset + blpBuffer.byteLength,
  );
  const blp = decodeBLP(copy);
  const imageData = getBLPImageData(blp, 0);
  const png = new PNG({
    width: blp.width,
    height: blp.height,
    inputHasAlpha: true,
  });
  // Copy only the image view (respect byteOffset/byteLength).
  png.data = Buffer.from(
    imageData.data.buffer,
    imageData.data.byteOffset,
    imageData.data.byteLength,
  );
  return PNG.sync.write(png);
}

/**
 * @param {object} options
 * @param {string} options.inDir
 * @param {string} options.outDir
 * @param {boolean} options.force
 * @param {string[]} options.include
 * @param {string[]} options.exclude
 */
export function convertBlpBatch(options) {
  const { inDir, outDir, force, include, exclude } = options;
  const files = walkFiles(inDir, new Set([".blp"]), include, exclude);

  let converted = 0;
  let skipped = 0;
  let errors = 0;

  const log = getLog();
  log.info(`\n[textures] 发现 ${files.length} 个 .blp`);

  const t0 = Date.now();
  let processed = 0;
  for (const file of files) {
    const pngLogical = blpLogicalToPng(file.logicalPath);
    const dest = path.join(outDir, ...pngLogical.split("/"));

    if (!force && fs.existsSync(dest)) {
      const srcStat = fs.statSync(file.absPath);
      const dstStat = fs.statSync(dest);
      if (dstStat.mtimeMs >= srcStat.mtimeMs && dstStat.size > 0) {
        skipped += 1;
        processed += 1;
        if (processed % 200 === 0 || processed === files.length) {
          const sec = ((Date.now() - t0) / 1000).toFixed(1);
          log.progress(
            `[textures] progress ${processed}/${files.length} converted=${converted} skipped=${skipped} (${sec}s)`,
          );
        }
        continue;
      }
    }

    try {
      const png = blpBufferToPng(fs.readFileSync(file.absPath));
      // P3-10：PNG 写盘 atomic
      atomicWriteBytesSync(dest, png);
      converted += 1;
    } catch (err) {
      log.error(`失败 ${file.logicalPath}: ${err.message ?? err}`, err);
      errors += 1;
    }
    processed += 1;
    if (processed % 200 === 0 || processed === files.length) {
      const sec = ((Date.now() - t0) / 1000).toFixed(1);
      log.progress(
        `[textures] progress ${processed}/${files.length} converted=${converted} skipped=${skipped} (${sec}s)`,
      );
    }
  }

  log.info(`[textures] 完成: 转换 ${converted}, 跳过 ${skipped}, 错误 ${errors}`);
  return { converted, skipped, errors, fileCount: files.length };
}

/** Deterministic placeholder for empty / team-color replaceable slots. */
export function writePlaceholderPng(destPath, rgba = [255, 0, 255, 255]) {
  const png = new PNG({ width: 1, height: 1, inputHasAlpha: true });
  png.data = Buffer.from(rgba);
  // P3-10：占位 PNG 也走 atomic，避免 placeholder 半成品被 cache 当成"已存在"误判
  atomicWriteBytesSync(destPath, PNG.sync.write(png));
}

export function sha256File(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}
