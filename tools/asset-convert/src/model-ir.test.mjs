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

test("retains source portrait cameras without requiring them on older IR", () => {
  const cameras = {cameras: [{name: "Camera01", position: [6, 2, 1], target: [0, 1, 0],
    fov_y_deg: 36, near: 0.08, far: 10, translation: {frames: [77000], values: [[0, 0, 0]]}}]};
  assert.deepEqual(createModelIr({cameras}).cameras, cameras);
  assert.deepEqual(createModelIr().cameras, {});
});
