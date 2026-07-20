import fs from "node:fs";
import path from "node:path";

/** Classic WC3 MPQ names in extract priority order (later overwrites earlier). */
export const MPQ_PRIORITY = [
  "War3.mpq",
  "War3x.mpq",
  "War3Local.mpq",
  "War3xLocal.mpq",
  "War3Patch.mpq",
];

/**
 * Find classic MPQ files under gameDir (case-insensitive filename match).
 * @param {string} gameDir
 * @returns {{ canonicalName: string, absolutePath: string }[]}
 */
export function detectClassicMpqs(gameDir) {
  if (!fs.existsSync(gameDir) || !fs.statSync(gameDir).isDirectory()) {
    throw new Error(`游戏目录不存在或不是文件夹: ${gameDir}`);
  }

  const entries = fs.readdirSync(gameDir, { withFileTypes: true });
  const byLower = new Map();
  for (const entry of entries) {
    if (!entry.isFile()) continue;
    byLower.set(entry.name.toLowerCase(), entry.name);
  }

  const found = [];
  for (const canonicalName of MPQ_PRIORITY) {
    const actual = byLower.get(canonicalName.toLowerCase());
    if (!actual) continue;
    found.push({
      canonicalName,
      absolutePath: path.join(gameDir, actual),
    });
  }

  if (found.length === 0) {
    throw new Error(
      `未在目录中找到经典 MPQ（${MPQ_PRIORITY.join(", ")}）: ${gameDir}\n` +
        "请确认这是经典《魔兽争霸3》安装目录（含 War3.mpq），而非仅含 CASC Data/ 的现代客户端。",
    );
  }

  if (!found.some((f) => f.canonicalName.toLowerCase() === "war3.mpq")) {
    console.warn("警告: 未找到 War3.mpq，解包结果可能不完整。");
  }

  return found;
}
