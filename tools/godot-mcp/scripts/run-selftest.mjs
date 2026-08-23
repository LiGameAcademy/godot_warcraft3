#!/usr/bin/env node
/**
 * CLI：headless 跑 selftest（不经过 MCP，便于本地/CI）。
 *
 *   node tools/godot-mcp/scripts/run-selftest.mjs ability_blizzard
 *   node tools/godot-mcp/scripts/run-selftest.mjs --warmup ability_blizzard hero_skill
 *   node tools/godot-mcp/scripts/run-selftest.mjs --list ability
 */
import {
  findSelftests,
  runSelftest,
  summarizeOutput,
  warmupQuitAfter,
} from "../src/godot-runner.mjs";

const argv = process.argv.slice(2);
let warmup = false;
let listMode = false;
/** @type {string[]} */
const tests = [];

for (const a of argv) {
  if (a === "--warmup" || a === "-w") warmup = true;
  else if (a === "--list" || a === "-l") listMode = true;
  else tests.push(a);
}

if (listMode) {
  const pattern = tests[0] ?? "";
  const all = findSelftests(pattern);
  console.log(all.join("\n"));
  process.exit(0);
}

if (!tests.length) {
  console.error(
    "用法: run-selftest.mjs [--warmup] <pattern|res://...> [...]\n       run-selftest.mjs --list [pattern]",
  );
  process.exit(2);
}

if (warmup) {
  const w = warmupQuitAfter(1);
  console.error("[warmup]", summarizeOutput(w.combined).summary, "exit", w.exitCode);
}

/** @param {string} t */
function resolve(t) {
  if (t.startsWith("res://")) return t;
  const m = findSelftests(t);
  if (m.length === 1) return m[0];
  if (m.length > 1) {
    console.error("多个匹配:\n" + m.join("\n"));
    process.exit(2);
  }
  return null;
}

let failed = 0;
for (const t of tests) {
  const path = resolve(t);
  if (!path) {
    console.error("未找到:", t);
    failed += 1;
    continue;
  }
  const r = runSelftest(path);
  const s = summarizeOutput(r.combined);
  const ok = r.exitCode === 0 && s.pass;
  console.log(`${ok ? "PASS" : "FAIL"}\t${path}\t${s.summary}`);
  if (!ok) {
    failed += 1;
    process.stdout.write(r.combined.slice(-8000));
  }
}

process.exit(failed ? 1 : 0);
