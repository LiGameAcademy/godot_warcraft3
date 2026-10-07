import assert from 'node:assert/strict';
import {Document} from '@gltf-transform/core';
import {compileAnimations} from './mdx-gltf-animation.js';

const document = new Document();
const buffer = document.createBuffer();
const bones = [0, 1].map(ObjectId => ({ObjectId, Parent: null, Name: 'Bone' + ObjectId, PivotPoint: [0, 0, 0]}));
const joints = bones.map(bone => document.createNode(bone.Name));
const sequence = {Name: 'Stand', Interval: [0, 1000], NonLooping: false};
compileAnimations({Sequences: [sequence], Nodes: bones}, document, buffer, sequence, 0, 1000,
  bones, joints, bones, new Map(bones.map((bone, i) => [bone.ObjectId, joints[i]])), new Map());
const channels = document.getRoot().listAnimations()[0].listChannels();
assert.equal(channels.length, 6);
const sample = (node, property) => channels.find(channel => channel.getTargetNode() === node && channel.getTargetPath() === property).getSampler();
for (const property of ['translation', 'rotation', 'scale']) {
  const left = sample(joints[0], property);
  const right = sample(joints[1], property);
  assert.equal(left.getInput(), right.getInput());
  assert.equal(left.getOutput(), right.getOutput());
  assert.deepEqual([...left.getInput().getArray()], [0, 1]);
  const expected = property === 'translation' ? [0, 0, 0] : property === 'scale' ? [1, 1, 1] : [0, 0, 0, 1];
  assert.deepEqual([...left.getOutput().getArray()].map(value => value === 0 ? 0 : value), [...expected, ...expected]);
}
assert.notEqual(sample(joints[0], 'translation').getOutput(), sample(joints[0], 'scale').getOutput());
console.log('PASS: identical animation payloads shared across independent targets; timelines and transforms preserved');
