import assert from "node:assert/strict";
import {
  isAlternateOrMorphSequenceName,
  sampleAnimVectorCarryIn,
  sampleAnimVectorInSequence,
} from "./anim.js";

const fallback = new Float32Array([1, 1, 1]);

assert.equal(isAlternateOrMorphSequenceName("Alternate Stand - 1"), true);
assert.equal(isAlternateOrMorphSequenceName("Morph Alternate"), true);
assert.equal(isAlternateOrMorphSequenceName("Attack Slam Alternate"), true);
assert.equal(isAlternateOrMorphSequenceName("Stand - 1"), false);

/** 山丘之王式：变身缩放只写在部分 Alternate 段，其余段无 key。 */
const boxScale = {
  Keys: [
    { Frame: 6133, Vector: new Float32Array([1, 1, 1]) },
    { Frame: 7400, Vector: new Float32Array([1.247, 1.247, 1.247]) },
    { Frame: 83333, Vector: new Float32Array([1.247, 1.247, 1.247]) },
  ],
};

const altStand1 = sampleAnimVectorInSequence(
  boxScale,
  65167,
  65167,
  66667,
  fallback,
);
assert.deepEqual(
  [...altStand1],
  [...fallback],
  "无 carryIn：Alternate Stand-1 应回 bind（旧行为，保大门）",
);

const altStand1Carry = sampleAnimVectorInSequence(
  boxScale,
  65167,
  65167,
  66667,
  fallback,
  { carryIn: true },
);
assert.ok(
  Math.abs(altStand1Carry[0] - 1.247) < 1e-3,
  "carryIn：Alternate Stand-1 应保持变身缩放",
);

const carry = sampleAnimVectorCarryIn(boxScale, 65167, fallback);
assert.ok(Math.abs(carry[0] - 1.247) < 1e-3);

const door = {
  Keys: [{ Frame: 5000, Vector: new Float32Array([0, 2, 0]) }],
};
const standDoor = sampleAnimVectorInSequence(door, 100, 0, 1000, fallback);
assert.deepEqual(
  [...standDoor],
  [...fallback],
  "普通 Stand 无 key 仍 bind（大门不被全局 hold 打开）",
);

console.log("anim_morph_alternate.test: PASS");
