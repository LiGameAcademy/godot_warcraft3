import assert from "node:assert/strict";
import test from "node:test";
import { createBakeTask, validateBakeTask, validateWorkerResult } from "./bake-task.js";

test("validates a deterministic Godot bake task", () => {
  const task = createBakeTask({
    asset_id: "units/human/footman/footman",
    ir_path: "Units/Human/Footman/Footman.ir.json",
    geometry_path: "Units/Human/Footman/Footman.gltf",
    output_scene: "Units/Human/Footman/Footman.fidelity.scn",
    profile: "fidelity",
    rules_version: "rules-v1",
  });
  const result = validateBakeTask(task);
  assert.equal(result.ok, true, result.errors.join("; "));
  assert.equal(task.task_version, 1);
});

test("requires output scene for a successful worker result", () => {
  const result = validateWorkerResult({
    result_version: 1,
    ok: true,
    asset_id: "foo",
    diagnostics: [],
  });
  assert.equal(result.ok, false);
  assert.ok(result.errors.includes("successful result requires output_scene"));
});
