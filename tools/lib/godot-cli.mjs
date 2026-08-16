/**
 * 共享：定位 Godot 可执行文件，并 headless 跑 `res://scripts/tool/*.gd`。
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const PROJECT_ROOT = path.resolve(__dirname, "../..");

export function candidateGodotBins() {
  const home = os.homedir();
  const desktop = path.join(home, "Desktop");
  return [
    process.env.GODOT,
    process.env.GODOT_BIN,
    path.join(desktop, "Godot_v4.6.3-stable_win64_console.exe"),
    path.join(desktop, "Godot_v4.6.3-stable_win64.exe"),
    path.join(desktop, "Godot_v4.6.1-stable_win64_console.exe"),
    path.join(desktop, "Godot_v4.6.1-stable_win64.exe"),
    path.join(desktop, "Godot_v4.6-stable_win64_console.exe"),
    path.join(desktop, "Godot_v4.6-stable_win64.exe"),
    path.join(desktop, "Godot_v4.5.1-stable_win64_console.exe"),
    path.join(desktop, "Godot_v4.5.1-stable_win64.exe"),
    "C:\\Program Files\\Godot\\Godot_v4.exe",
    "/Applications/Godot.app/Contents/MacOS/Godot",
    "godot",
  ].filter(Boolean);
}

/** @param {string} [explicit] */
export function findGodotExecutable(explicit = "") {
  if (explicit && fs.existsSync(explicit)) return explicit;
  for (const c of candidateGodotBins()) {
    if (c === "godot") {
      const which = spawnSync(process.platform === "win32" ? "where" : "which", ["godot"], {
        encoding: "utf8",
      });
      if (which.status === 0) {
        const first = String(which.stdout || "")
          .split(/\r?\n/)
          .map((s) => s.trim())
          .find(Boolean);
        if (first) return first;
      }
      continue;
    }
    if (fs.existsSync(c)) return c;
  }
  return "";
}

/**
 * @param {object} opts
 * @param {string} opts.scriptRes  如 res://scripts/tool/export_pe2_scenes.gd
 * @param {string[]} [opts.userArgs]  -- 之后传给脚本的参数
 * @param {string} [opts.godot]
 * @param {boolean} [opts.required] 找不到 Godot 时是否失败（默认 true）
 * @returns {number} exit code
 */
export function runGodotScript(opts) {
  const godot = findGodotExecutable(opts.godot || "");
  if (!godot) {
    const msg =
      "未找到 Godot 4.x。请设置环境变量 GODOT（指向 console 版 exe），或把 Godot 加到 PATH。";
    if (opts.required === false) {
      console.warn(msg + "（已跳过）");
      return 0;
    }
    console.error(msg);
    return 1;
  }
  const userArgs = opts.userArgs || [];
  const args = ["--headless", "--path", PROJECT_ROOT, "-s", opts.scriptRes];
  if (userArgs.length) args.push("--", ...userArgs);

  console.log(`godot: ${godot}`);
  console.log(`  -s ${opts.scriptRes}${userArgs.length ? " -- " + userArgs.join(" ") : ""}`);

  const r = spawnSync(godot, args, {
    cwd: PROJECT_ROOT,
    stdio: "inherit",
    shell: false,
    env: process.env,
  });
  if (r.error) {
    console.error("启动 Godot 失败:", r.error.message);
    return 1;
  }
  return r.status ?? 1;
}
