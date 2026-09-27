import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { parseModel } from "./convert-mdx.js";

export const SCHEMA_VERSION = 1;
export const RULES = {
  parse_failed: ["P0", "源解析", "模型解析失败"],
  missing_texture: ["P0", "源依赖", "源纹理与转换纹理均缺失"],
  generated_invalid: ["P0", "生成依赖", "转换模型或特效描述无法解析"],
  generated_dependency: ["P0", "生成依赖", "glTF 引用的本地依赖缺失或路径无效"],
  feature_export_gap: ["P1", "转换产物", "源特征与导出描述数量不一致或描述缺失"],
  source_unavailable: ["P1", "来源", "没有原始模型，无法检查数据是否丢失"],
  source_collision: ["P1", "来源", "同一逻辑身份有多个源文件，需确认覆盖顺序"],
  source_manifest_mismatch: ["P1", "来源", "源内容与解包清单哈希不一致"],
  not_converted: ["P1", "生成", "尚无转换模型"],
  not_baked: ["P1", "生成", "尚无烘焙场景"],
  multilayer: ["P1", "材质", "多层材质需核查，当前主要选取单层"],
  texture_animation: ["P1", "动画消费", "纹理动画已可导出，Godot 消费待补全"],
  geoset_color: ["P1", "动画消费", "Geoset 颜色轨消费待核查"],
  geoset_fade: ["P2", "动画消费", "Geoset 透明渐变可能被简化为显隐"],
  layer_animation: ["P1", "材质", "材质层透明度／纹理切换轨待核查"],
  pe2_tracks: ["P1", "转换", "PE2 动态参数被标量化，需保留动画轨"],
  pe1: ["P1", "特效", "第一代粒子发射器的映射待核查"],
  ribbon: ["P2", "特效", "Ribbon 高度、颜色、材质与姿态有已知映射限制"],
  tail: ["P2", "特效", "粒子 Tail 当前使用近似几何"],
  global_fx: ["P2", "时钟", "特效全局序列时钟需验证"],
  team_glow: ["P1", "光晕", "队伍光晕需分类验证朝向、挂点、深度与强度"],
  presenter: ["P1", "增强分离", "此路径可能触发现有自动外观改造，需核查实际 bake"],
  unknown_chunk: ["P1", "源解析", "发现未纳入经典能力表的 MDX 块"],
  modern_model: ["P1", "源解析", "非经典模型版本，支持范围需单独验证"],
};
const clean = (value) => String(value ?? "").replace(/\0/g, "").trim().replace(/\\/g, "/");
export const modelKey = (value) => clean(value).replace(/\.(mdx|mdl|gltf|glb|scn)$/i, "").toLowerCase();
export const hash = (data) => crypto.createHash("sha256").update(data).digest("hex");
const tracked = (value) => Boolean(value && Array.isArray(value.Keys) && value.Keys.length);
const count = (model, key) => model[key]?.length ?? 0;
const KNOWN_CHUNKS = new Set("VERS MODL SEQS GLBS MTLS TEXS TXAN GEOS GEOA BONE LITE HELP ATCH PIVT PREM PRE2 RIBB CAMS EVTS CLID".split(" "));

export function inventory(root) {
  const result = [];
  if (!fs.existsSync(root)) return result;
  const visit = (folder) => {
    for (const entry of fs.readdirSync(folder, { withFileTypes: true })) {
      if (entry.isSymbolicLink()) continue;
      const full = path.join(folder, entry.name);
      if (entry.isDirectory()) visit(full);
      else if (entry.isFile()) result.push(path.relative(root, full).replace(/\\/g, "/"));
    }
  };
  visit(root);
  return result.sort();
}

export function inspectChunks(bytes, logical) {
  if (/\.mdl$/i.test(logical)) return [];
  if (bytes.toString("ascii", 0, 4) !== "MDLX") throw new Error("Invalid MDLX header");
  const chunks = [];
  for (let offset = 4; offset < bytes.length;) {
    if (offset + 8 > bytes.length) throw new Error(`Truncated chunk header at ${offset}`);
    const tag = bytes.toString("ascii", offset, offset + 4);
    const size = bytes.readUInt32LE(offset + 4);
    if (offset + 8 + size > bytes.length) throw new Error(`Truncated ${tag} chunk at ${offset}`);
    chunks.push({ tag, offset, size, known: KNOWN_CHUNKS.has(tag) });
    offset += size + 8;
  }
  return chunks;
}

export function inspectModel(model, logical) {
  const pe2 = model.ParticleEmitters2 ?? [];
  const layers = (model.Materials ?? []).flatMap((mat) => mat.Layers ?? []);
  const geosetAnims = model.GeosetAnims ?? [];
  const dynamic = pe2.flatMap((emitter, index) =>
    ["Speed", "Variation", "Latitude", "Gravity", "Width", "Length"].filter((key) => tracked(emitter[key]))
      .map((key) => ({ emitter: index, name: clean(emitter.Name), field: key, keys: emitter[key].Keys.length })));
  const features = Object.fromEntries(["Geosets", "Bones", "Sequences", "Materials", "Textures", "GeosetAnims", "TextureAnims", "ParticleEmitters", "ParticleEmitters2", "RibbonEmitters", "Lights", "Attachments", "EventObjects", "Cameras", "GlobalSequences"].map((key) => [key, count(model, key)]));
  Object.assign(features, {
    layers: layers.length,
    multilayer_materials: (model.Materials ?? []).filter((mat) => mat.Layers?.length > 1).length,
    animated_pe2_parameters: dynamic.length,
    billboard_nodes: (model.Nodes ?? []).filter((node) => node && (node.Flags & 120)).length,
    team_glow_textures: (model.Textures ?? []).filter((tex) => tex.ReplaceableId === 2).length,
    tail_emitters: pe2.filter((emitter) => emitter.FrameFlags & 2).length,
  });
  const issues = [];
  const add = (id, evidence) => issues.push({ id, severity: RULES[id][0], stage: RULES[id][1], message: RULES[id][2], evidence });
  if (features.multilayer_materials) add("multilayer", { count: features.multilayer_materials });
  if (features.TextureAnims) add("texture_animation", { count: features.TextureAnims });
  if (geosetAnims.some((anim) => tracked(anim.Color))) add("geoset_color", {});
  if (geosetAnims.some((anim) => tracked(anim.Alpha) && (anim.Alpha.LineType !== 0 || anim.Alpha.Keys.some((key) => key.Vector?.[0] > 0 && key.Vector[0] < 1)))) add("geoset_fade", {});
  if (layers.some((layer) => tracked(layer.Alpha) || tracked(layer.TextureID))) add("layer_animation", {});
  if (dynamic.length) add("pe2_tracks", dynamic);
  if (features.ParticleEmitters) add("pe1", { count: features.ParticleEmitters });
  if (features.RibbonEmitters) add("ribbon", { count: features.RibbonEmitters });
  if (features.tail_emitters) add("tail", { count: features.tail_emitters });
  if (features.GlobalSequences && (pe2.length || features.RibbonEmitters)) add("global_fx", { certainty: "candidate: verify actual global-sequence references" });
  if (features.team_glow_textures) add("team_glow", { count: features.team_glow_textures });
  if (/^(abilities\/(weapons|spells)\/|objects\/spawnmodels\/)|\/missile/i.test(logical)) add("presenter", { certainty: "path-based candidate, not proof of replacement" });
  if (model.Version > 800) add("modern_model", { version: model.Version });
  const categories = [];
  const category = (name, confidence, evidence) => categories.push({ name, confidence, evidence });
  if (/^abilities\/weapons\//i.test(logical)) category("projectile", "medium", "logical weapon directory; unit reference checked separately");
  if (features.team_glow_textures) category("team_glow_unclassified", "high", "ReplaceableId=2; ground/socket subtype requires node and geometry review");
  if (pe2.length) category("particles", "high", "ParticleEmitters2");
  if (features.RibbonEmitters) category("ribbon", "high", "RibbonEmitters");
  if (!categories.length) category(features.Bones ? "skinned_model" : "mesh_model", "medium", "source structure");
  return { features, categories, issues, sequences: (model.Sequences ?? []).map((seq) => ({ name: clean(seq.Name), interval: Array.from(seq.Interval ?? []), non_looping: Boolean(seq.NonLooping) })), textures: (model.Textures ?? []).map((tex) => ({ path: clean(tex.Image), replaceable_id: tex.ReplaceableId ?? 0 })) };
}

export function parseSource(bytes, logical) {
  const chunks = inspectChunks(bytes, logical);
  const model = parseModel(bytes, logical);
  const result = inspectModel(model, logical);
  const unknown = chunks.filter((chunk) => !chunk.known);
  if (unknown.length) result.issues.push({ id: "unknown_chunk", severity: "P1", stage: "源解析", message: RULES.unknown_chunk[2], evidence: unknown });
  return { ...result, chunks, model_version: model.Version };
}

export function inspectGenerated(root, row, index) {
  const issues = [];
  const capabilities = [];
  const add = (id, evidence) => issues.push({ id, severity: RULES[id][0], stage: RULES[id][1], message: RULES[id][2], evidence });
  const converted = row.converted_path;
  let generatedFeatures = null;
  if (/\.gltf$/i.test(converted)) {
    try {
      const gltf = JSON.parse(fs.readFileSync(path.join(root, converted), "utf8"));
      generatedFeatures = { meshes: gltf.meshes?.length ?? 0, materials: gltf.materials?.length ?? 0, animations: gltf.animations?.length ?? 0 };
      for (const entry of [...(gltf.buffers ?? []), ...(gltf.images ?? [])]) {
        if (!entry.uri || entry.uri.startsWith("data:")) continue;
        const uri = decodeURIComponent(entry.uri).replace(/\\/g, "/");
        const logical = path.posix.normalize(path.posix.join(path.posix.dirname(converted), uri));
        if (uri.includes(":") || uri.startsWith("/") || logical.startsWith("../") || !index.has(logical.toLowerCase())) add("generated_dependency", { uri: entry.uri, resolved: logical });
      }
    } catch (error) { add("generated_invalid", { path: converted, error: error.message }); }
  }
  const sidecars = new Map();
  for (const [feature, suffix, field, consumer] of [
    ["ParticleEmitters2", "pe2", "emitters", "partial"],
    ["RibbonEmitters", "ribbon", "ribbons", "partial"],
    ["TextureAnims", "animkeys", "texture_anims", "consumer_not_found_in_current_audit"],
    ["GeosetAnims", "animkeys", "geoset_anims", "partial_visibility_only"],
  ]) {
    const sourceCount = row.features?.[feature] ?? 0;
    if (!sourceCount) continue;
    const logical = index.get(`${row.id}.${suffix}.json`);
    let exportedCount = null;
    if (logical) {
      try {
        if (!sidecars.has(logical)) sidecars.set(logical, JSON.parse(fs.readFileSync(path.join(root, logical), "utf8")));
        exportedCount = Array.isArray(sidecars.get(logical)[field]) ? sidecars.get(logical)[field].length : null;
      } catch (error) { add("generated_invalid", { path: logical, error: error.message }); }
    }
    const status = exportedCount === sourceCount ? "count_matches_not_fidelity_proof" : "missing_or_count_mismatch";
    capabilities.push({ feature, source_count: sourceCount, exported_count: exportedCount, export_status: status, consumer_status: consumer, reload_status: "unverified" });
    if (exportedCount !== sourceCount) add("feature_export_gap", { feature, source_count: sourceCount, exported_count: exportedCount, sidecar: logical ?? null });
  }
  for (const [feature, sourceCount] of Object.entries(row.features ?? {})) {
    if (!sourceCount || capabilities.some((item) => item.feature === feature)) continue;
    capabilities.push({ feature, source_count: sourceCount, export_status: "enumerated_only_not_compared", consumer_status: "unverified", reload_status: "unverified" });
  }
  return { issues, capabilities, generated_features: generatedFeatures };
}

export function summarize(records) {
  const severity = { P0: 0, P1: 0, P2: 0, P3: 0, none: 0 };
  const issues = {};
  for (const row of records) {
    severity[row.severity]++;
    for (const id of new Set(row.issues.map((issue) => issue.id))) issues[id] = (issues[id] ?? 0) + 1;
  }
  return { models: records.length, source_available: records.filter((row) => row.source_path).length, parsed: records.filter((row) => row.parse_status === "parsed").length, parse_failed: records.filter((row) => row.parse_status === "failed").length, baked: records.filter((row) => row.scn_path).length, severity, issues, visually_verified: 0 };
}

export function chooseSamples(records, references, limit = 20) {
  const selected = new Map();
  const add = (row, reason) => {
    if (!row) return;
    if (!selected.has(row.id)) selected.set(row.id, { id: row.id, logical_path: row.logical_path, reasons: [] });
    selected.get(row.id).reasons.push(reason);
  };
  for (const ref of references) add(records.find((row) => row.id === modelKey(ref.model)), `${ref.unit_id} ${ref.field} (${ref.source})`);
  const sorted = [...records].sort((a, b) => Number(Boolean(b.scn_path)) - Number(Boolean(a.scn_path)) || a.logical_path.localeCompare(b.logical_path));
  add(sorted.find((row) => row.features?.team_glow_textures > 0 && row.id === "units/human/heroarchmage/heroarchmage"), "hero glow: Archmage ground/socket review");
  add(sorted.find((row) => row.features?.team_glow_textures > 0 && row.id === "units/human/heromountainking/heromountainking"), "hero glow: second geometry reference");
  for (const id of Object.keys(RULES)) {
    if (selected.size >= limit) break;
    add(sorted.find((row) => row.issues.some((issue) => issue.id === id)), id);
  }
  for (const feature of ["Lights", "Attachments", "EventObjects", "billboard_nodes", "Geosets"]) {
    if (selected.size >= limit) break;
    add(sorted.find((row) => row.features?.[feature] > 0), feature);
  }
  return [...selected.values()];
}
