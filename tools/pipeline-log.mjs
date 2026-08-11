/**
 * 管线日志：控制台简略，完整内容写入 gitignore 的进度文档。
 *
 * 默认文件：logs/pipeline-progress.md
 * 环境变量 PIPELINE_LOG 可覆盖路径。
 *
 * 用法：
 *   import { beginSession, getLog } from "../pipeline-log.mjs";
 *   const log = beginSession("asset-convert");
 *   log.progress("[models] 100/200 ...");
 *   log.warnOnce("miss:Foo.blp", "缺少贴图 Foo.blp → 占位");
 *   log.error("失败 Bar.mdx", err);
 *   log.endSession({ converted: 1 });
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");

export const DEFAULT_PROGRESS_LOG = path.join(REPO_ROOT, "logs", "pipeline-progress.md");

/** @type {PipelineLog | null} */
let _active = null;

function ts() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

function iso() {
  return new Date().toISOString();
}

export class PipelineLog {
  /**
   * @param {{ logPath?: string, session?: string, consoleProgress?: boolean }} [opts]
   */
  constructor(opts = {}) {
    this.logPath = path.resolve(
      opts.logPath || process.env.PIPELINE_LOG || DEFAULT_PROGRESS_LOG,
    );
    this.session = opts.session || "pipeline";
    this.consoleProgress = opts.consoleProgress !== false;
    /** @type {Map<string, { count: number, brief: string }>} */
    this._warnCounts = new Map();
    this._errorCount = 0;
    this._warnPrinted = 0;
    this._startedAt = Date.now();
    fs.mkdirSync(path.dirname(this.logPath), { recursive: true });
    process.env.PIPELINE_LOG = this.logPath;
  }

  /** 开始新会话（追加写入文档）。 */
  begin() {
    const block = [
      "",
      `## ${this.session} — ${iso()}`,
      "",
      `| 字段 | 值 |`,
      `|---|---|`,
      `| cwd | \`${process.cwd()}\` |`,
      `| node | ${process.version} |`,
      "",
      "",
    ].join("\n");
    fs.appendFileSync(this.logPath, block, "utf8");
    if (this.consoleProgress) {
      console.log(`[log] 进度文档: ${path.relative(REPO_ROOT, this.logPath) || this.logPath}`);
    }
    return this;
  }

  /**
   * @param {"PROGRESS"|"INFO"|"WARN"|"ERROR"|"FATAL"} level
   * @param {string} message
   * @param {string} [detail]
   */
  _append(level, message, detail) {
    const lines = [`- **${ts()}** \`${level}\` ${message}`];
    if (detail) {
      const indented = String(detail)
        .trimEnd()
        .split(/\r?\n/)
        .map((l) => `  ${l}`)
        .join("\n");
      lines.push("  ```", indented, "  ```");
    }
    lines.push("");
    try {
      fs.appendFileSync(this.logPath, `${lines.join("\n")}\n`, "utf8");
    } catch {
      // 日志写失败不阻断主流程
    }
  }

  /** 进度：控制台原样 + 写入文档 */
  progress(message) {
    const msg = String(message);
    if (this.consoleProgress) console.log(msg);
    this._append("PROGRESS", msg);
  }

  /** 一般信息：控制台原样 + 写入文档 */
  info(message) {
    const msg = String(message);
    if (this.consoleProgress) console.log(msg);
    this._append("INFO", msg);
  }

  /**
   * 非致命警告（去重）：
   * - 首次：控制台简略一行
   * - 重复：只记文档 + 计数，结束时汇总
   * @param {string} key 去重键
   * @param {string} brief 控制台简略文案
   * @param {string} [detail] 文档详情（默认 = brief）
   */
  warnOnce(key, brief, detail) {
    const k = String(key || brief);
    const prev = this._warnCounts.get(k);
    if (prev) {
      prev.count += 1;
      this._append("WARN", `${brief} (×${prev.count})`, detail || undefined);
      return;
    }
    this._warnCounts.set(k, { count: 1, brief: String(brief) });
    this._warnPrinted += 1;
    // 控制台：前若干条完整打，之后只提示「同类已折叠」
    if (this._warnPrinted <= 8) {
      console.warn(`  ⚠ ${brief}`);
    } else if (this._warnPrinted === 9) {
      console.warn(`  ⚠ …后续同类警告已折叠，详见 ${path.relative(REPO_ROOT, this.logPath)}`);
    }
    this._append("WARN", String(brief), detail || undefined);
  }

  /** 非去重警告（少用） */
  warn(brief, detail) {
    console.warn(`  ⚠ ${brief}`);
    this._append("WARN", String(brief), detail || undefined);
  }

  /**
   * 非致命错误：控制台只打一行摘要，堆栈进文档
   * @param {string} brief
   * @param {unknown} [errOrDetail]
   */
  error(brief, errOrDetail) {
    this._errorCount += 1;
    let detail = "";
    if (errOrDetail instanceof Error) {
      detail = errOrDetail.stack || errOrDetail.message;
    } else if (errOrDetail != null) {
      detail = String(errOrDetail);
    }
    console.error(`  ✖ ${brief}`);
    this._append("ERROR", String(brief), detail || undefined);
  }

  /** 致命：控制台 + 文档后由调用方 exit */
  fatal(brief, errOrDetail) {
    let detail = "";
    if (errOrDetail instanceof Error) {
      detail = errOrDetail.stack || errOrDetail.message;
    } else if (errOrDetail != null) {
      detail = String(errOrDetail);
    }
    console.error(`❌ ${brief}`);
    this._append("FATAL", String(brief), detail || undefined);
  }

  /**
   * 结束会话：写出汇总（警告去重计数等）
   * @param {Record<string, unknown>} [extra]
   */
  endSession(extra = {}) {
    const elapsedSec = ((Date.now() - this._startedAt) / 1000).toFixed(1);
    const topWarns = [...this._warnCounts.entries()]
      .sort((a, b) => b[1].count - a[1].count)
      .slice(0, 30);

    const lines = [
      "### 会话汇总",
      "",
      `- 耗时: ${elapsedSec}s`,
      `- 非致命错误: ${this._errorCount}`,
      `- 警告种类: ${this._warnCounts.size}`,
      `- 警告总次数: ${[...this._warnCounts.values()].reduce((s, w) => s + w.count, 0)}`,
    ];
    for (const [k, v] of Object.entries(extra)) {
      lines.push(`- ${k}: ${v}`);
    }
    if (topWarns.length) {
      lines.push("", "高频警告（最多 30）:", "");
      for (const [, w] of topWarns) {
        lines.push(`- ×${w.count} — ${w.brief}`);
      }
    }
    lines.push("", "---", "");
    fs.appendFileSync(this.logPath, `${lines.join("\n")}\n`, "utf8");

    if (this._warnCounts.size > 0 || this._errorCount > 0) {
      console.log(
        `[log] 汇总: errors=${this._errorCount} warnKinds=${this._warnCounts.size} → ${path.relative(REPO_ROOT, this.logPath)}`,
      );
      for (const [, w] of topWarns.slice(0, 5)) {
        if (w.count > 1) console.log(`  · ×${w.count} ${w.brief}`);
      }
    }
  }
}

/**
 * @param {string} session
 * @param {{ logPath?: string }} [opts]
 */
export function beginSession(session, opts = {}) {
  _active = new PipelineLog({ ...opts, session }).begin();
  return _active;
}

/** @returns {PipelineLog} */
export function getLog() {
  if (!_active) {
    _active = new PipelineLog({ session: "ad-hoc" }).begin();
  }
  return _active;
}

/** 无会话时也安全的进度写入（bootstrap 子进程前可用） */
export function appendRaw(level, message, detail) {
  const logPath = path.resolve(process.env.PIPELINE_LOG || DEFAULT_PROGRESS_LOG);
  fs.mkdirSync(path.dirname(logPath), { recursive: true });
  const lines = [`- **${ts()}** \`${level}\` ${message}`];
  if (detail) {
    lines.push("  ```", String(detail).trimEnd(), "  ```");
  }
  lines.push("");
  fs.appendFileSync(logPath, `${lines.join("\n")}\n`, "utf8");
}
