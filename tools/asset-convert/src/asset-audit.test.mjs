import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { inspectModel, inspectChunks, inspectGenerated, chooseSamples, summarize } from "./asset-audit.js";
import { runAudit, parseOptions } from "./audit-cli.mjs";

test("animated parameters are distinguished from valid zero scalars; mixed FX keep multiple categories", () => {
  const track = { LineType: 1, Keys: [{ Frame: 0, Vector: [0] }, { Frame: 1000, Vector: [10] }] };
  const result = inspectModel({ ParticleEmitters2: [{ Name: "Emitter", Speed: track, Gravity: 0, FrameFlags: 3 }], Textures: [{ ReplaceableId: 2 }], TextureAnims: [{}], Materials: [{ Layers: [{}, {}] }] }, "Abilities/Weapons/Test.mdx");
  assert.deepEqual(result.issues.find((issue) => issue.id === "pe2_tracks").evidence.map((item) => item.field), ["Speed"]);
  assert.equal(result.features.tail_emitters, 1);
  assert.deepEqual(result.categories.map((item) => item.name), ["projectile", "team_glow_unclassified", "particles"]);
  assert.equal(result.issues.some((issue) => issue.id === "texture_animation"), true);
});

test("chunk validation rejects truncated payloads and reports unknown chunks without swallowing them", () => {
  const bytes = Buffer.alloc(12);
  bytes.write("MDLXTEST");
  assert.equal(inspectChunks(bytes, "test.mdx")[0].known, false);
  bytes.writeUInt32LE(5, 8);
  assert.throws(() => inspectChunks(bytes, "test.mdx"), /Truncated TEST/);
  assert.throws(() => inspectChunks(Buffer.from("junk"), "test.mdx"), /header/);
});

test("unit references resolve MDL logical paths to MDX samples and deduplicate reasons", () => {
  const rows = [{ id: "abilities/weapons/priestmissile/priestmissile", logical_path: "Abilities/Weapons/PriestMissile/PriestMissile.mdx", issues: [], features: {} }];
  const result = chooseSamples(rows, [{ unit_id: "hmpr", field: "Missileart", model: "Abilities\\Weapons\\PriestMissile\\PriestMissile.mdl", source: "Units/HumanUnitFunc.txt" }]);
  assert.equal(result.length, 1);
  assert.match(result[0].reasons[0], /hmpr/);
});

test("issue totals count affected models once and hero samples exclude portraits", () => {
  const rows = ["heroarchmage_portrait", "heroarchmage"].map((name) => ({ id: "units/human/heroarchmage/" + name, logical_path: "Units/Human/HeroArchMage/" + name + ".mdx", features: { team_glow_textures: 1 }, severity: "P0", issues: [{ id: "generated_dependency" }, { id: "generated_dependency" }] }));
  assert.equal(summarize(rows).issues.generated_dependency, 2);
  assert.equal(chooseSamples(rows, [])[0].id, "units/human/heroarchmage/heroarchmage");
});

test("full audit continues after malformed source, includes converted-only models, and resumes deterministically", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "wc3-asset-audit-"));
  try {
    const source = path.join(root, "source");
    const converted = path.join(root, "converted");
    const slk = path.join(root, "slk");
    fs.mkdirSync(source); fs.mkdirSync(converted); fs.mkdirSync(slk);
    fs.writeFileSync(path.join(source, "valid.mdl"), 'Version { FormatVersion 800, } Model "Test" { BlendTime 150, }');
    fs.writeFileSync(path.join(source, "broken.mdx"), "broken");
    fs.writeFileSync(path.join(converted, "orphan.scn"), "catalog presence only");
    const out = path.join(root, "out");
    const options = parseOptions(["--source", source, "--converted", converted, "--manifest", path.join(root, "absent.json"), "--slk", slk, "--out", out]);
    const first = runAudit(options);
    assert.equal(first.report.summary.parse_failed, 1);
    const report = JSON.parse(fs.readFileSync(path.join(out, "report.json")));
    assert.equal(report.summary.models, 3);
    assert.equal(report.summary.parsed, 1);
    assert.equal(report.summary.parse_failed, 1);
    assert.equal(report.records.find((row) => row.id === "orphan").parse_status, "source_unavailable");
    const second = runAudit(options);
    assert.equal(second.cacheHits, 1);
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(out, "report.json"))).records, report.records);
    assert.equal(fs.readFileSync(path.join(converted, "orphan.scn"), "utf8"), "catalog presence only");
  } finally { removeFixture(root); }
});

test("audit detects missing glTF buffers and distinguishes retained tracks from absent sidecars", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "wc3-asset-audit-"));
  try {
    fs.writeFileSync(path.join(root, "model.gltf"), JSON.stringify({ buffers: [{ uri: "missing.bin" }], images: [{ uri: "data:image/png;base64,ignored" }] }));
    fs.writeFileSync(path.join(root, "model.animkeys.json"), JSON.stringify({ texture_anims: [{}] }));
    const result = inspectGenerated(root, { id: "model", converted_path: "model.gltf", features: { TextureAnims: 1, ParticleEmitters2: 2 } }, new Map([["model.animkeys.json", "model.animkeys.json"]]));
    assert.equal(result.issues.filter((issue) => issue.id === "generated_dependency").length, 1);
    assert.equal(result.capabilities.find((item) => item.feature === "TextureAnims").export_status, "count_matches_not_fidelity_proof");
    assert.equal(result.capabilities.find((item) => item.feature === "ParticleEmitters2").exported_count, null);
    assert.equal(result.issues.filter((issue) => issue.id === "feature_export_gap").length, 1);
  } finally { removeFixture(root); }
});

function removeFixture(root) {
  const relative = path.relative(fs.realpathSync(os.tmpdir()), fs.realpathSync(root));
  assert.ok(!relative.startsWith("..") && !path.isAbsolute(relative) && relative.startsWith("wc3-asset-audit-"));
  fs.rmSync(root, { recursive: true, force: true });
}
