import assert from "node:assert/strict";
import {
  animGlobalSeqId,
  sampleAnimVectorInSequence,
  sampleAnimVectorOnClock,
  sequenceBakeDurationMs,
  wrapGlobalSeqTime,
} from "./anim.js";

const fallback = new Float32Array([0, 0, 0, 1]);
const flagRot = {
  GlobalSeqId: 0,
  Keys: [
    { Frame: 0, Vector: new Float32Array([0, 0, 0, 1]) },
    { Frame: 1000, Vector: new Float32Array([0, 0, 1, 0]) },
  ],
};

assert.equal(animGlobalSeqId(flagRot), 0);
assert.equal(animGlobalSeqId({ GlobalSeqId: -1 }), -1);
assert.equal(animGlobalSeqId(null), -1);
assert.equal(animGlobalSeqId({ GlobalSeqId: null }), -1);
assert.equal(animGlobalSeqId({}), -1);
assert.equal(wrapGlobalSeqTime(2500, 1000), 500);
assert.equal(wrapGlobalSeqTime(-250, 1000), 750);

const scoped = sampleAnimVectorInSequence(flagRot, 61800, 61667, 62000, fallback);
assert.deepEqual([...scoped], [...fallback], "Stand 区间不含 GlobalSeq keys → bind");

const mid = sampleAnimVectorOnClock(flagRot, 250, 1000, fallback);
assert.ok(Math.abs(mid[2]) > 0.1, "GlobalSeq 时钟应插值到非 bind");

const loopShort = sequenceBakeDurationMs(
  61667,
  62000,
  true,
  [{ Rotation: flagRot }],
  [1433, 80000],
);
assert.equal(loopShort, 1433);
assert.equal(
  sequenceBakeDurationMs(
    61667,
    62000,
    true,
    [{ Rotation: { GlobalSeqId: 1, Keys: [] } }],
    [1433, 80000],
  ),
  333,
  "80s 时针不拉长 Stand",
);

const birth = sequenceBakeDurationMs(0, 60000, false, [{ Rotation: flagRot }], [1433]);
assert.equal(birth, 60000);

const bellRot = {
  GlobalSeqId: null,
  Keys: [
    { Frame: 161667, Vector: new Float32Array([-0.2036, 0.0928, 0, 0.9746]) },
    { Frame: 162687, Vector: new Float32Array([-0.1434, 0.0654, 0, -0.9875]) },
    { Frame: 163667, Vector: new Float32Array([-0.2036, 0.0928, 0, 0.9746]) },
  ],
};
const q0 = sampleAnimVectorInSequence(bellRot, 161667, 161667, 163667, fallback);
const q1 = sampleAnimVectorInSequence(bellRot, 162687, 161667, 163667, fallback);
let dot = q0[0] * q1[0] + q0[1] * q1[1] + q0[2] * q1[2] + q0[3] * q1[3];
if (dot < 0) dot = -dot;
assert.ok(dot < 0.98, "铃铛施工段旋转应变化（null≠GlobalSeq 0）");

console.log("anim_global_seq.test: PASS");
