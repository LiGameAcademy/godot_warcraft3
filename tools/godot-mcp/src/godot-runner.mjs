/**
 * Headless Godot 运行器：捕获 stdout/stderr，供 MCP 与 CLI 复用。
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  PROJECT_ROOT,
  findGodotExecutable,
} from "../../lib/godot-cli.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** @returns {string} */
export function defaultGodotLogPath() {
  const app = process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming");
  return path.join(app, "Godot", "app_userdata", "godot_warcraft3", "logs", "godot.log");
}

/** @returns {{ godot: string, projectRoot: string }} */
export function resolveEnv() {
  const godot = findGodotExecutable(process.env.GODOT || process.env.GODOT_BIN || "");
  return { godot, projectRoot: PROJECT_ROOT };
}

/**
 * @param {object} opts
 * @param {string[]} opts.args  Godot CLI args（不含 exe / --path）
 * @param {number} [opts.timeoutMs]
 * @param {string} [opts.godot]
 * @returns {{ exitCode: number, stdout: string, stderr: string, combined: string, durationMs: number }}
 */
export function runGodot({ args, timeoutMs = 300_000, godot = "" }) {
  const bin = findGodotExecutable(godot || process.env.GODOT || "");
  if (!bin) {
    return {
      exitCode: 127,
      stdout: "",
      stderr: "未找到 Godot。设置环境变量 GODOT 指向 console 版 exe。",
      combined: "未找到 Godot。设置环境变量 GODOT 指向 console 版 exe。",
      durationMs: 0,
    };
  }

  const fullArgs = ["--headless", "--path", PROJECT_ROOT, ...args];
  const started = Date.now();
  const r = spawnSync(bin, fullArgs, {
    cwd: PROJECT_ROOT,
    encoding: "utf8",
    shell: false,
    env: process.env,
    timeout: timeoutMs,
    maxBuffer: 32 * 1024 * 1024,
  });
  const durationMs = Date.now() - started;
  const stdout = String(r.stdout ?? "");
  const stderr = String(r.stderr ?? "");
  const errMsg = r.error ? `\n${r.error.message}` : "";
  const combined = stdout + stderr + errMsg;

  return {
    exitCode: r.status ?? (r.error ? 1 : 0),
    stdout,
    stderr: stderr + errMsg,
    combined,
    durationMs,
  };
}

/** @param {string} scriptRes  res://... */
export function runScript(scriptRes, userArgs = [], opts = {}) {
  const args = ["-s", scriptRes];
  if (userArgs.length) args.push("--", ...userArgs);
  return runGodot({ ...opts, args });
}

/** @param {number} [seconds] */
export function warmupQuitAfter(seconds = 1, opts = {}) {
  return runGodot({ ...opts, args: [`--quit-after`, String(seconds)] });
}

/** @param {number} [seconds] */
export function runMainScene(seconds = 3, opts = {}) {
  return runGodot({ ...opts, args: [`--quit-after`, String(seconds)] });
}

/**
 * @param {string} pattern  文件名片段，如 ability_blizzard
 * @returns {string[]} res:// 路径
 */
export function findSelftests(pattern = "") {
  const testsRoot = path.join(PROJECT_ROOT, "tests");
  const out = [];
  /** @param {string} dir */
  function walk(dir) {
    if (!fs.existsSync(dir)) return;
    for (const name of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, name.name);
      if (name.isDirectory()) walk(p);
      else if (name.name.startsWith("selftest_") && name.name.endsWith(".gd")) {
        if (!pattern || name.name.includes(pattern)) {
          const rel = path.relative(PROJECT_ROOT, p).replace(/\\/g, "/");
          out.push(`res://${rel}`);
        }
      }
    }
  }
  walk(testsRoot);
  out.sort();
  return out;
}

/** @param {string} resPath */
export function runSelftest(resPath, opts = {}) {
  return runScript(resPath, [], opts);
}

/**
 * @param {string} text
 * @returns {{ pass: boolean, summary: string, details: Record<string, number> }}
 */
export function summarizeOutput(text) {
  const details = {
    unicode_nul: (text.match(/Unicode parsing error/g) ?? []).length,
    script_errors: (text.match(/SCRIPT ERROR/g) ?? []).length,
    push_errors: (text.match(/^ERROR:/gm) ?? []).length,
    warnings: (text.match(/^WARNING:/gm) ?? []).length,
    pass_lines: (text.match(/: PASS\b/g) ?? []).length,
    fail_lines: (text.match(/: FAIL\b/g) ?? []).length,
  };
  const pass =
    details.script_errors === 0 &&
    details.fail_lines === 0 &&
    !/\bFAIL\s*\(\d+\)/.test(text) &&
    (details.pass_lines > 0 || !/selftest_/.test(text));
  const parts = [];
  if (details.pass_lines) parts.push(`PASS×${details.pass_lines}`);
  if (details.fail_lines) parts.push(`FAIL×${details.fail_lines}`);
  if (details.script_errors) parts.push(`SCRIPT_ERROR×${details.script_errors}`);
  if (details.unicode_nul) parts.push(`UnicodeNUL×${details.unicode_nul}`);
  if (details.warnings) parts.push(`WARN×${details.warnings}`);
  return {
    pass,
    summary: parts.length ? parts.join(", ") : "无 PASS/FAIL 标记",
    details,
  };
}

/**
 * @param {object} [opts]
 * @param {number} [opts.tailLines]
 * @param {string} [opts.logPath]
 */
export function analyzeGodotLog(opts = {}) {
  const logPath = opts.logPath || defaultGodotLogPath();
  if (!fs.existsSync(logPath)) {
    return {
      logPath,
      exists: false,
      lines: 0,
      patterns: {},
      tail: "",
    };
  }
  const raw = fs.readFileSync(logPath, "utf8");
  const lines = raw.split(/\r?\n/);
  const tailN = opts.tailLines ?? 400;
  const tail = lines.slice(-tailN).join("\n");

  const patterns = {
    unicode_nul: (tail.match(/Unicode parsing error/g) ?? []).length,
    script_errors: (tail.match(/SCRIPT ERROR/g) ?? []).length,
    parse_errors: (tail.match(/Parse Error/g) ?? []).length,
    failed_load: (tail.match(/Failed to load/g) ?? []).length,
    invalid_uid: (tail.match(/invalid UID/g) ?? []).length,
    bone_index: (tail.match(/Bone index -1/g) ?? []).length,
    vertex_amount: (tail.match(/Vertex amount|Too few vertices/g) ?? []).length,
  };

  return {
    logPath,
    exists: true,
    lines: lines.length,
    mtime: fs.statSync(logPath).mtime.toISOString(),
    patterns,
    tail,
  };
}
