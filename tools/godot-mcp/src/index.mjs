#!/usr/bin/env node
/**
 * godot-warcraft3 专用 MCP：headless 跑 selftest / 主场景 / 读日志。
 *
 * Cursor：项目根 `.cursor/mcp.json` 已配置；改 GODOT 环境变量即可。
 */
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import {
  analyzeGodotLog,
  findSelftests,
  resolveEnv,
  runGodot,
  runMainScene,
  runScript,
  runSelftest,
  summarizeOutput,
  warmupQuitAfter,
} from "./godot-runner.mjs";
import { PROJECT_ROOT } from "../../lib/godot-cli.mjs";

const server = new Server(
  { name: "godot-warcraft3", version: "0.1.0" },
  { capabilities: { tools: {} } },
);

/** @type {import("@modelcontextprotocol/sdk/types.js").Tool[]} */
const TOOLS = [
  {
    name: "godot_status",
    description:
      "检查本机 Godot 可执行文件与项目路径。改 GODOT 环境变量后可用此工具确认。",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "godot_warmup",
    description:
      "Headless 启动项目并 --quit-after N 秒，刷新 global class 缓存（新建 class_name 后建议先跑）。",
    inputSchema: {
      type: "object",
      properties: {
        seconds: { type: "number", description: "默认 1", default: 1 },
      },
    },
  },
  {
    name: "godot_list_selftests",
    description: "列出 tests/**/selftest_*.gd；可选 pattern 过滤文件名。",
    inputSchema: {
      type: "object",
      properties: {
        pattern: {
          type: "string",
          description: "文件名片段，如 ability_blizzard",
        },
      },
    },
  },
  {
    name: "godot_run_selftest",
    description:
      "Headless 运行单个 selftest（res://tests/.../selftest_xxx.gd 或文件名 pattern）。返回 stdout/stderr 摘要。",
    inputSchema: {
      type: "object",
      properties: {
        test: {
          type: "string",
          description: "res:// 路径或 selftest 文件名片段（必填）",
        },
        timeout_ms: { type: "number", description: "默认 120000", default: 120000 },
      },
      required: ["test"],
    },
  },
  {
    name: "godot_run_selftests",
    description: "批量运行多个 selftest（pattern 匹配文件名，或 tests 数组）。",
    inputSchema: {
      type: "object",
      properties: {
        pattern: { type: "string", description: "匹配 selftest 文件名" },
        tests: {
          type: "array",
          items: { type: "string" },
          description: "显式 res:// 或文件名列表",
        },
        warmup: {
          type: "boolean",
          description: "批量前先 warmup（默认 true）",
          default: true,
        },
        timeout_ms: { type: "number", default: 120000 },
      },
    },
  },
  {
    name: "godot_run_main_scene",
    description:
      "Headless 加载 run/main_scene（game_main），运行若干秒后退出；用于抓启动期 ERROR/Unicode。",
    inputSchema: {
      type: "object",
      properties: {
        seconds: { type: "number", default: 5 },
        timeout_ms: { type: "number", default: 180000 },
      },
    },
  },
  {
    name: "godot_run_script",
    description: "Headless 运行 res:// 下任意 GDScript（-s），可传 -- 后参数。",
    inputSchema: {
      type: "object",
      properties: {
        script: { type: "string", description: "如 res://scripts/tool/export_pe2_scenes.gd" },
        args: { type: "array", items: { type: "string" } },
        timeout_ms: { type: "number", default: 300000 },
      },
      required: ["script"],
    },
  },
  {
    name: "godot_analyze_log",
    description:
      "分析 user:// 同步到磁盘的 godot.log（Windows: %APPDATA%/Godot/app_userdata/godot_warcraft3/logs/godot.log）。",
    inputSchema: {
      type: "object",
      properties: {
        tail_lines: { type: "number", default: 400 },
        log_path: { type: "string", description: "可选绝对路径" },
      },
    },
  },
];

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

/**
 * @param {string} test
 * @returns {string|null}
 */
function resolveSelftestPath(test) {
  const t = test.trim().replace(/\\/g, "/");
  if (t.startsWith("res://")) return t;
  if (t.endsWith(".gd")) {
    const byName = findSelftests(t.replace(/^selftest_/, "").replace(/\.gd$/, ""));
    const hit = byName.find((p) => p.endsWith("/" + t) || p.endsWith(t));
    return hit ?? null;
  }
  const matches = findSelftests(t);
  if (matches.length === 1) return matches[0];
  if (matches.length > 1) {
    throw new Error(
      `匹配到多个 selftest，请指定完整路径：\n${matches.join("\n")}`,
    );
  }
  return null;
}

/** @param {unknown} data */
function textResult(data) {
  const body = typeof data === "string" ? data : JSON.stringify(data, null, 2);
  return { content: [{ type: "text", text: body }] };
}

/** @param {string} combined @param {number} exitCode @param {number} durationMs @param {string} label */
function formatRunReport(combined, exitCode, durationMs, label) {
  const summary = summarizeOutput(combined);
  const maxLen = 24_000;
  let output = combined;
  if (output.length > maxLen) {
    output = output.slice(-maxLen);
    output = `…(截断，仅保留末尾 ${maxLen} 字符)\n${output}`;
  }
  return {
    label,
    exit_code: exitCode,
    duration_ms: durationMs,
    ok: exitCode === 0 && summary.pass,
    summary: summary.summary,
    details: summary.details,
    output,
  };
}

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "godot_status": {
        const { godot, projectRoot } = resolveEnv();
        return textResult({
          project_root: projectRoot,
          main_scene: "res://game/scenes/game_main.tscn",
          godot_executable: godot || null,
          godot_found: Boolean(godot),
          hint: godot
            ? "可用 godot_warmup / godot_run_selftest 等工具。"
            : "请设置环境变量 GODOT=.../Godot_*_console.exe",
        });
      }

      case "godot_warmup": {
        const seconds = z.number().optional().parse(args?.seconds) ?? 1;
        const r = warmupQuitAfter(seconds);
        return textResult(formatRunReport(r.combined, r.exitCode, r.durationMs, "warmup"));
      }

      case "godot_list_selftests": {
        const pattern = z.string().optional().parse(args?.pattern) ?? "";
        const tests = findSelftests(pattern);
        return textResult({ count: tests.length, tests });
      }

      case "godot_run_selftest": {
        const test = z.string().parse(args?.test);
        const timeoutMs = z.number().optional().parse(args?.timeout_ms) ?? 120_000;
        const path = resolveSelftestPath(test);
        if (!path) {
          return textResult({ ok: false, error: `未找到 selftest: ${test}` });
        }
        const r = runSelftest(path, { timeoutMs });
        return textResult(
          formatRunReport(r.combined, r.exitCode, r.durationMs, path),
        );
      }

      case "godot_run_selftests": {
        const pattern = z.string().optional().parse(args?.pattern) ?? "";
        const explicit = z.array(z.string()).optional().parse(args?.tests) ?? [];
        const warmup = z.boolean().optional().parse(args?.warmup) ?? true;
        const timeoutMs = z.number().optional().parse(args?.timeout_ms) ?? 120_000;

        let paths = explicit
          .map((t) => resolveSelftestPath(t))
          .filter(Boolean);
        if (!paths.length && pattern) {
          paths = findSelftests(pattern);
        }
        if (!paths.length) {
          return textResult({ ok: false, error: "无匹配 selftest" });
        }

        const reports = [];
        if (warmup) {
          const w = warmupQuitAfter(1, { timeoutMs: 60_000 });
          reports.push({
            phase: "warmup",
            ...formatRunReport(w.combined, w.exitCode, w.durationMs, "warmup"),
          });
        }

        let failed = 0;
        for (const p of paths) {
          const r = runSelftest(p, { timeoutMs });
          const rep = formatRunReport(r.combined, r.exitCode, r.durationMs, p);
          reports.push({ phase: "test", ...rep });
          if (!rep.ok) failed += 1;
        }

        return textResult({
          total: paths.length,
          failed,
          passed: paths.length - failed,
          reports,
        });
      }

      case "godot_run_main_scene": {
        const seconds = z.number().optional().parse(args?.seconds) ?? 5;
        const timeoutMs = z.number().optional().parse(args?.timeout_ms) ?? 180_000;
        const r = runMainScene(seconds, { timeoutMs });
        const report = formatRunReport(
          r.combined,
          r.exitCode,
          r.durationMs,
          `main_scene quit-after ${seconds}s`,
        );
        const log = analyzeGodotLog({ tailLines: 200 });
        return textResult({ run: report, log_tail: log });
      }

      case "godot_run_script": {
        const script = z.string().parse(args?.script);
        const userArgs = z.array(z.string()).optional().parse(args?.args) ?? [];
        const timeoutMs = z.number().optional().parse(args?.timeout_ms) ?? 300_000;
        const r = runScript(script, userArgs, { timeoutMs });
        return textResult(
          formatRunReport(r.combined, r.exitCode, r.durationMs, script),
        );
      }

      case "godot_analyze_log": {
        const tailLines = z.number().optional().parse(args?.tail_lines) ?? 400;
        const logPath = z.string().optional().parse(args?.log_path);
        const log = analyzeGodotLog({
          tailLines,
          logPath,
        });
        return textResult(log);
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return {
      content: [{ type: "text", text: JSON.stringify({ ok: false, error: msg }) }],
      isError: true,
    };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error(`godot-mcp ready (project=${PROJECT_ROOT})`);
}

main().catch((e) => {
  console.error("godot-mcp fatal:", e);
  process.exit(1);
});
