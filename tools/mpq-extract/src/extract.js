import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import {
  isInternalMpqFile,
  matchesFilters,
  normalizeLogicalPath,
} from "./paths.js";
import { closeArchive, extractToBuffer, listFiles, openArchive } from "./stormlib.js";

/**
 * @typedef {{ sourceMpq: string, size: number, sha256: string }} ManifestEntry
 * @typedef {{
 *   version: number,
 *   gameDir: string,
 *   extractedAt: string,
 *   files: Record<string, ManifestEntry>
 * }} Manifest
 */

/**
 * @param {string} manifestPath
 * @returns {Manifest | null}
 */
export function loadManifest(manifestPath) {
  if (!fs.existsSync(manifestPath)) return null;
  try {
    return JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  } catch {
    console.warn(`警告: 无法解析现有 manifest，将重新生成: ${manifestPath}`);
    return null;
  }
}

/**
 * @param {string} filePath
 * @returns {string}
 */
function sha256File(filePath) {
  const hash = crypto.createHash("sha256");
  hash.update(fs.readFileSync(filePath));
  return hash.digest("hex");
}

/**
 * @param {Buffer} data
 * @returns {string}
 */
function sha256Buffer(data) {
  return crypto.createHash("sha256").update(data).digest("hex");
}

/**
 * Prefer backslash names when talking to StormLib for classic WC3.
 * @param {string} logicalPath
 */
function toArchiveName(logicalPath) {
  return logicalPath.replace(/\//g, "\\");
}

/**
 * @param {object} options
 * @param {{ canonicalName: string, absolutePath: string }[]} options.mpqs
 * @param {string} options.outDir
 * @param {string} options.manifestPath
 * @param {string} options.gameDir
 * @param {boolean} options.force
 * @param {string[]} options.include
 * @param {string[]} options.exclude
 * @param {string | null} [options.listFile]
 */
export function extractMpqs(options) {
  const {
    mpqs,
    outDir,
    manifestPath,
    gameDir,
    force,
    include,
    exclude,
    listFile = null,
  } = options;

  fs.mkdirSync(outDir, { recursive: true });
  fs.mkdirSync(path.dirname(manifestPath), { recursive: true });

  /** @type {Manifest | null} */
  const previous = force ? null : loadManifest(manifestPath);
  /** @type {Record<string, ManifestEntry>} */
  const files = previous?.files ? { ...previous.files } : {};

  let extracted = 0;
  let skipped = 0;
  let overwritten = 0;
  let errors = 0;

  for (const mpq of mpqs) {
    console.log(`\n打开 ${mpq.canonicalName} ...`);
    let archive;
    try {
      archive = openArchive(mpq.absolutePath);
    } catch (err) {
      console.error(`  无法打开 ${mpq.absolutePath}: ${err.message ?? err}`);
      errors += 1;
      continue;
    }

    try {
      const names = listFiles(archive, listFile);
      console.log(`  列表文件数: ${names.length}`);

      for (const rawName of names) {
        const logicalPath = normalizeLogicalPath(rawName);
        if (!logicalPath || isInternalMpqFile(logicalPath)) continue;
        if (!matchesFilters(logicalPath, include, exclude)) continue;

        const destPath = path.join(outDir, ...logicalPath.split("/"));
        const existing = files[logicalPath];

        if (
          !force &&
          existing &&
          existing.sourceMpq === mpq.canonicalName &&
          fs.existsSync(destPath)
        ) {
          try {
            const diskSha = sha256File(destPath);
            if (diskSha === existing.sha256 && fs.statSync(destPath).size === existing.size) {
              skipped += 1;
              continue;
            }
          } catch {
            // fall through to re-extract
          }
        }

        try {
          const data = extractToBuffer(archive, toArchiveName(logicalPath));
          fs.mkdirSync(path.dirname(destPath), { recursive: true });
          const alreadyOnDisk = fs.existsSync(destPath);
          fs.writeFileSync(destPath, data);

          const entry = {
            sourceMpq: mpq.canonicalName,
            size: data.length,
            sha256: sha256Buffer(data),
          };
          const wasKnown = Boolean(files[logicalPath]);
          files[logicalPath] = entry;

          if (alreadyOnDisk || wasKnown) overwritten += 1;
          else extracted += 1;
        } catch (err) {
          console.error(`  解包失败 ${logicalPath}: ${err.message ?? err}`);
          errors += 1;
        }
      }
    } finally {
      closeArchive(archive);
    }
  }

  /** @type {Manifest} */
  const manifest = {
    version: 1,
    gameDir: path.resolve(gameDir),
    extractedAt: new Date().toISOString(),
    files,
  };

  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");

  console.log("\n完成:");
  console.log(`  新写入:   ${extracted}`);
  console.log(`  覆盖写入: ${overwritten}`);
  console.log(`  跳过:     ${skipped}`);
  console.log(`  错误:     ${errors}`);
  console.log(`  清单条目: ${Object.keys(files).length}`);
  console.log(`  输出目录: ${outDir}`);
  console.log(`  Manifest: ${manifestPath}`);

  return { extracted, overwritten, skipped, errors, fileCount: Object.keys(files).length };
}
