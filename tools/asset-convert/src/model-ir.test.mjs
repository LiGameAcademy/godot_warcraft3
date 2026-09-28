import assert from "node:assert/strict";
import test from "node:test";
import { createModelIr, validateModelIr } from "./model-ir.js";

test("creates and validates the versioned Model IR envelope", () => {
  const ir = createModelIr({
    asset_id: "units/human/footman/footman",
    logical_path: "Units/Human/Footman/Footman.mdx",
    source_format: "mdx",
    profile: "fidelity",
    feature_status: {
      geometry: "parsed",
      attachments: "consumed",
    },
  });
  const result = validateModelIr(ir);
  assert.equal(result.ok, true, result.errors.join("; "));
  assert.equal(ir.schema_version, 1);
  assert.equal(ir.profile, "fidelity");
});

test("rejects missing identity and unknown feature status", () => {
  const result = validateModelIr({
    schema_version: 1,
    identity: {},
    profile: "fidelity",
    dependencies: [],
    diagnostics: [],
    feature_status: { particles: "lost" },
  });
  assert.equal(result.ok, false);
  assert.ok(result.errors.some((error) => error.includes("asset_id")));
  assert.ok(result.errors.some((error) => error.includes("invalid status")));
});
