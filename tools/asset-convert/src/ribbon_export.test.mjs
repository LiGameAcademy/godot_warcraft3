import test from "node:test";
import assert from "node:assert/strict";
import { extractRibbons } from "./convert-mdx.js";

test("Ribbon exports visibility timing, zero alpha and sampled parent motion", () => {
  const parent = { Name: "parent", ObjectId: 0, Parent: -1, PivotPoint: [0, 0, 0],
    Translation: { LineType: 1, Keys: [{ Frame: 1000, Vector: [0, 0, 0] }, { Frame: 2000, Vector: [100, 0, 0] }] } };
  const ribbon = { Name: "trail", ObjectId: 1, Parent: 0, PivotPoint: [0, 0, 0],
    LifeSpan: 0.2, HeightAbove: 10, HeightBelow: 20, Alpha: 0, Color: [1, 0, 0], EmissionRate: 30,
    Visibility: { Keys: [{ Frame: 1000, Vector: [0] }, { Frame: 1200, Vector: [1] }, { Frame: 1800, Vector: [0] }] } };
  const [output] = extractRibbons({ Nodes: [parent, ribbon], RibbonEmitters: [ribbon],
    Sequences: [{ Name: "Birth", Interval: [1000, 2000] }] });
  assert.equal(output.alpha, 0);
  assert.deepEqual(output.active_sequences, ["Birth"]);
  assert.deepEqual(output.visibility_keys.map(k => k.frame), [1000, 1200, 1800]);
  const samples = output.positions_by_sequence.Birth;
  assert.equal(samples[0].t, 0);
  assert.equal(samples.at(-1).t, 1);
  assert.equal(samples.at(-1).position[0] - samples[0].position[0], 100);
});
