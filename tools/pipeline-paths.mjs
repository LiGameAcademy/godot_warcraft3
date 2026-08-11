/**
 * 管线 staging / 遗留 cache 路径约定。
 * extract 默认写 staging；convert / slk / map-parse 读 staging；
 * 若 staging 不存在则回退旧 .cache/wc3-assets（并警告）。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = path.resolve(__dirname, "..");

export const STAGING_ROOT = path.join(REPO_ROOT, "assets", ".staging", "wc3-assets");
export const STAGING_MANIFEST = path.join(REPO_ROOT, "assets", ".staging", "manifest.json");
export const LEGACY_CACHE_ROOT = path.join(REPO_ROOT, ".cache", "wc3-assets");
export const LEGACY_MANIFEST = path.join(REPO_ROOT, ".cache", "manifest.json");
/** 管线进度文档（gitignore：logs/） */
export const PROGRESS_LOG = path.join(REPO_ROOT, "logs", "pipeline-progress.md");

/**
 * 解析 extract 源根：优先 staging，其次遗留 .cache。
 * @returns {{ root: string, kind: "staging" | "legacy-cache" | "missing" }}
 */
export function resolveExtractRoot() {
  if (fs.existsSync(STAGING_ROOT)) {
    return { root: STAGING_ROOT, kind: "staging" };
  }
  if (fs.existsSync(LEGACY_CACHE_ROOT)) {
    return { root: LEGACY_CACHE_ROOT, kind: "legacy-cache" };
  }
  return { root: STAGING_ROOT, kind: "missing" };
}
