#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { inventory, modelKey, hash, parseSource, inspectGenerated, summarize, chooseSamples, RULES, SCHEMA_VERSION } from "./asset-audit.js";
import { atomicWriteBytesSync as atomicWriteSync } from "./atomic-write.js";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
export function parseOptions(args) {
  const options = { source: path.join(ROOT, ".cache/wc3-assets"), converted: path.join(ROOT, "assets/asset-converted"), manifest: path.join(ROOT, ".cache/manifest.json"), out: path.join(ROOT, ".cache/asset-audit/latest"), slk: path.join(ROOT, "assets/slk-exported") };
  for (let i = 0; i < args.length; i++) {
    const key = args[i].replace(/^--/, "");
    if (!Object.hasOwn(options, key) || !args[i + 1] || args[i + 1].startsWith("--")) throw new Error(`Unknown/missing option: ${args[i]}`);
    options[key] = path.resolve(args[++i]);
  }
  return options;
}

function readJson(file, fallback = {}) {
  if (!fs.existsSync(file)) return fallback;
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function unitReferences(options) {
  const result = [];
  for (const file of inventory(options.slk).filter((name) => /(?:^|\/)HumanUnitFunc\.txt$/i.test(name))) {
    let unit = "";
    for (const line of fs.readFileSync(path.join(options.slk, file), "utf8").split(/\r?\n/)) {
      const section = line.match(/^\[([^\]]+)\]/);
      if (section) unit = section[1];
      if (!["hmpr", "Hamg"].includes(unit)) continue;
      const value = line.match(/^(Missileart|file)=(.+)/i);
      if (value) for (const model of value[2].replace(/"/g, "").split(",")) result.push({ unit_id: unit, field: value[1], model: model.trim().replace(/\\/g, "/"), source: file, precedence: "reference_candidate_not_runtime_override_resolution" });
    }
  }
  return result;
}

export function runAudit(options) {
  const sourceFiles = inventory(options.source);
  const convertedFiles = inventory(options.converted);
  if (!sourceFiles.length && !convertedFiles.length) throw new Error("Neither source nor converted assets are available");
  const sourceIndex = new Map(sourceFiles.map((file) => [file.toLowerCase(), file]));
  const convertedIndex = new Map(convertedFiles.map((file) => [file.toLowerCase(), file]));
  const manifest = readJson(options.manifest);
  const manifestIndex = new Map(Object.entries(manifest.files ?? {}).map(([key, value]) => [key.toLowerCase(), value]));
  const catalog = new Map();
  for (const [files, kind, pattern] of [[sourceFiles, "sources", /\.(mdx|mdl)$/i], [convertedFiles, "generated", /\.(gltf|glb|scn)$/i]]) {
    for (const file of files.filter((name) => pattern.test(name))) {
      const id = modelKey(file);
      if (!catalog.has(id)) catalog.set(id, { sources: [], generated: [] });
      catalog.get(id)[kind].push(file);
    }
  }
  const parserPath = path.join(ROOT, "tools/asset-convert/node_modules/war3-model/dist/war3-model.cjs");
  const parserVersion = readJson(path.join(ROOT, "tools/asset-convert/node_modules/war3-model/package.json")).version;
  const auditSignature = hash(Buffer.concat([fs.readFileSync(fileURLToPath(import.meta.url)), fs.readFileSync(new URL("./asset-audit.js", import.meta.url)), fs.readFileSync(new URL("./convert-mdx.js", import.meta.url)), fs.readFileSync(parserPath)]));
  const cacheRoot = path.join(options.out, "parse-cache");
  fs.mkdirSync(cacheRoot, { recursive: true });
  const records = [];
  let cacheHits = 0;
  for (const [id, files] of [...catalog.entries()].sort(([a], [b]) => a.localeCompare(b))) {
    const source = files.sources[0];
    const converted = files.generated.find((file) => /\.(gltf|glb)$/i.test(file));
    const scn = files.generated.find((file) => /\.scn$/i.test(file));
    const row = { id, logical_path: source ?? converted ?? scn, source_path: source ?? "", source_candidates: files.sources, converted_path: converted ?? "", scn_path: scn ?? "", source_sha256: "", provenance: source ? (manifestIndex.get(source.toLowerCase()) ?? null) : null, parse_status: "source_unavailable", features: {}, categories: [], issues: [], profile: "legacy_unclassified", visual_status: "unverified", technical_status: "static_audit_only" };
    const add = (rule, evidence = {}) => row.issues.push({ id: rule, severity: RULES[rule][0], stage: RULES[rule][1], message: RULES[rule][2], evidence });
    if (source) {
      try {
        const bytes = fs.readFileSync(path.join(options.source, source));
        row.source_sha256 = hash(bytes);
        const cachePath = path.join(cacheRoot, hash(`${auditSignature}:${source.toLowerCase()}:${row.source_sha256}`) + ".json");
        let parsed;
        try { parsed = readJson(cachePath, null); } catch { parsed = null; }
        if (parsed) cacheHits++;
        else { parsed = parseSource(bytes, source); atomicWriteSync(cachePath, JSON.stringify(parsed)); }
        Object.assign(row, parsed, { parse_status: "parsed" });
      } catch (error) { row.parse_status = "failed"; add("parse_failed", { error: error.message }); }
      if (row.provenance?.sha256 && row.provenance.sha256 !== row.source_sha256) add("source_manifest_mismatch");
      if (files.sources.length > 1) add("source_collision", files.sources);
    } else add("source_unavailable");
    if (!converted) add("not_converted");
    if (!scn) add("not_baked");
    row.dependencies = (row.textures ?? []).filter((tex) => tex.path).map((tex) => {
      const original = tex.path.toLowerCase();
      const png = original.replace(/\.(blp|tga|dds)$/i, ".png");
      const sourcePath = sourceIndex.get(original) ?? "";
      const convertedPath = convertedIndex.get(png) ?? "";
      return { logical_path: tex.path, source_path: sourcePath, converted_path: convertedPath, available: Boolean(sourcePath || convertedPath) };
    });
    const missing = row.dependencies.filter((dep) => !dep.available);
    if (missing.length) add("missing_texture", missing.map((dep) => dep.logical_path));
    row.sidecars = {};
    for (const suffix of ["pe2", "ribbon", "animkeys", "geosetvis", "attachments", "cameras"]) row.sidecars[suffix] = convertedIndex.get(`${id}.${suffix}.json`) ?? "";
    const bakePath = convertedIndex.get(`${id}.scn.bake.json`);
    row.bake_manifest_path = bakePath ?? "";
    const generated = inspectGenerated(options.converted, row, convertedIndex);
    row.issues.push(...generated.issues);
    row.capabilities = generated.capabilities;
    row.generated_features = generated.generated_features;
    // Presence is not equivalent to fresh signatures or a successful runtime reload.
    row.severity = row.issues.map((issue) => issue.severity).sort()[0] ?? "none";
    records.push(row);
    if (records.length % 500 === 0) console.log(`Audited ${records.length}/${catalog.size}`);
  }
  const references = unitReferences(options);
  const missingManifestModels = [...manifestIndex.keys()].filter((file) => /\.(mdx|mdl)$/i.test(file) && !sourceIndex.has(file));
  const implementationFiles = ["tools/asset-convert/src/convert-mdx.js", "tools/godot/wc3_scn_animkeys.gd", "tools/godot/wc3_scn_pe2.gd", "tools/godot/wc3_scn_ribbon.gd", "packages/map/infra/map_model_cache.gd", "packages/map/presentation/wc3_model/wc3_fx_presenter.gd", "assets/shaders/wc3_team_glow.gdshader", "assets/shaders/wc3_team_glow_ground.gdshader"];
  const implementation = Object.fromEntries(implementationFiles.map((file) => [file, fs.existsSync(path.join(ROOT, file)) ? hash(fs.readFileSync(path.join(ROOT, file))) : null]));
  const report = { schema_version: SCHEMA_VERSION, generated_at: new Date().toISOString(), audit_signature: auditSignature, parser_version: parserVersion, implementation, scope: { ...options, source_files: sourceFiles.length, converted_files: convertedFiles.length, provenance_manifest_available: fs.existsSync(options.manifest), extracted_at: manifest.extractedAt ?? null, missing_manifest_models: missingManifestModels, coverage: "all available loose model files + converted-only models; not proof of complete MPQ enumeration", archive_precedence: "winning sourceMpq when present; full overwrite history unavailable" }, summary: summarize(records), unit_references: references, samples: chooseSamples(records, references), records };
  fs.mkdirSync(options.out, { recursive: true });
  atomicWriteSync(path.join(options.out, "report.json"), JSON.stringify(report, null, 2) + "\n");
  const tasks = Object.entries(report.summary.issues).sort(([a, ac], [b, bc]) => RULES[a][0].localeCompare(RULES[b][0]) || bc - ac).map(([id, affected]) => ({ id, severity: RULES[id][0], stage: RULES[id][1], title: RULES[id][2], affected, example: records.find((row) => row.issues.some((issue) => issue.id === id))?.logical_path, implementation_candidates: implementationFiles.filter((file) => id === "team_glow" ? /team_glow|map_model_cache/.test(file) : id === "presenter" ? /fx_presenter|map_model_cache/.test(file) : /convert-mdx|wc3_scn_/.test(file)), status: "needs_verification_and_fix", acceptance: "source/export/runtime/reload checks plus game reference for visual changes" }));
  atomicWriteSync(path.join(options.out, "tasks.json"), JSON.stringify(tasks, null, 2) + "\n");
  atomicWriteSync(path.join(options.out, "summary.md"), ["# 资产审计", "", `生成时间：${report.generated_at}`, `范围：${report.scope.coverage}`, "", `模型 ${records.length}；源解析成功 ${report.summary.parsed}；解析失败 ${report.summary.parse_failed}；已有 .scn ${report.summary.baked}。`, "所有模型视觉状态均为未验证；以下为静态证据或风险候选，不等于已确认的游戏画面缺陷。", "", "## 按优先级的任务", "", ...tasks.map((task) => `- ${task.severity} ${task.title}：${task.affected} 个；示例 ${task.example}`), "", "## 代表样本", "", ...report.samples.map((sample) => `- ${sample.logical_path}：${sample.reasons.join("；")}`), "", `清单中有 ${missingManifestModels.length} 个模型未出现在本次源目录，单列于 report.json。`, ""].join("\n"));
  console.log(JSON.stringify({ ...report.summary, cache_hits: cacheHits, report: path.join(options.out, "report.json") }, null, 2));
  return { report, cacheHits };
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes("--help")) console.log("Read-only full asset audit. --source DIR --converted DIR --manifest FILE --slk DIR --out DIR\nDefaults resolve from repository root. Exit 1: model parse failures (report still written); 2: command failure. Existing scenes are never changed.");
  else try { process.exitCode = runAudit(parseOptions(process.argv.slice(2))).report.summary.parse_failed ? 1 : 0; }
  catch (error) { console.error(error.stack); process.exitCode = 2; }
}
