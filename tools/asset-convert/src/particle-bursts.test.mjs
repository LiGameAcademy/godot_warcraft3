import test from 'node:test';
import assert from 'node:assert/strict';
import {particlePayload} from './mdx-fx-ir.js';

test('Squirt retains positive source event counts at exact times, not sampled rate changes', () => {
  const model = {Nodes: [], GlobalSequences: [], Sequences: [{Name: 'Birth', Interval: [1000, 2000]}],
    ParticleEmitters2: [{ObjectId: 0, PivotPoint: [0, 0, 0], TextureID: 0, Visibility: 1,
      EmissionRate: {LineType: 0, Keys: [
        {Frame: 800, Vector: [99]}, {Frame: 1000, Vector: [-25]},
        {Frame: 1800, Vector: [35]}, {Frame: 1933, Vector: [0]},
      ]}}]};
  const payload = particlePayload(model, {emitters: [{squirt: true}]}, [{uri: 'spark.png'}]);
  assert.deepEqual(payload.emitters[0].clips[0].bursts, [{time: 0.8, count: 35}]);
  assert.ok(payload.emitters[0].clips[0].keys.length > 30);
  assert.deepEqual(payload.emitters[0].unsupported, []);
});
