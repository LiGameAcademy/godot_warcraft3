import assert from 'node:assert/strict';
import fs from 'node:fs';
import { ModelRenderer } from 'war3-model';
import { parseModel } from './convert-mdx.js';
import { sampleAnimVector, sampleAnimVectorInSequence } from './anim.js';
import { Document } from '@gltf-transform/core';
import { compileAnimations } from './mdx-gltf-animation.js';

const keys = [
  {Frame: 0, Vector: [0], OutTan: [8]},
  {Frame: 100, Vector: [4], InTan: [-4]},
];
assert.equal(sampleAnimVector({Keys:keys, LineType:0},99,[0])[0],0);
assert.equal(sampleAnimVector({Keys:keys, LineType:0},100,[0])[0],4);
assert.equal(sampleAnimVector({Keys:keys, LineType:1},50,[0])[0],2);
assert.equal(sampleAnimVector({Keys:keys, LineType:2},50,[0])[0],3.5);
assert.equal(sampleAnimVector({Keys:keys, LineType:3},50,[0])[0],2);

// Check the emitted glTF, not just the sampler: a step must remain a step,
// and a looping clip's last key must retain its authored end pose.
const document = new Document();
const buffer = document.createBuffer();
const joint = document.createNode('Bone');
const sequence = {Name:'Stand',Interval:[0,100],NonLooping:false};
const bone = {ObjectId:0,Parent:null,PivotPoint:[0,0,0],Translation:{LineType:0,Keys:[
  {Frame:0,Vector:[0,0,0]}, {Frame:50,Vector:[5,0,0]}, {Frame:100,Vector:[10,0,0]},
]}};
compileAnimations({Sequences:[sequence],Nodes:[bone]},document,buffer,sequence,0,100,[bone],[joint],[bone],new Map([[0,joint]]),new Map());
const channel = document.getRoot().listAnimations()[0].listChannels().find(c=>c.getTargetPath()==='translation');
const sampler = channel.getSampler();
const times = Array.from(sampler.getInput().getArray());
const values = sampler.getOutput().getArray();
assert.equal(values[values.length-3],10,'The end pose must not be replaced by the first pose');
const jump = times.findIndex(t=>Math.abs(t-0.05)<0.0000001);
assert.ok(jump>0 && times[jump]-times[jump-1]<0.000002);
assert.equal(values[(jump-1)*3],0);
assert.equal(values[jump*3],5);

// Independent reference: the installed source-format renderer's interpolator,
// not another path through our own world-matrix evaluator.
const source = new URL('../../../.cache/wc3-assets/Abilities/Weapons/PriestMissile/PriestMissile.mdx', import.meta.url);
const model = parseModel(fs.readFileSync(source), 'PriestMissile.mdx');
const reference = new ModelRenderer(model);
let comparisons = 0;
let maximumError = 0;
for (let sequence = 0; sequence < model.Sequences.length; sequence++) {
  reference.setSequence(sequence);
  const [start, end] = model.Sequences[sequence].Interval;
  for (const node of model.Nodes) {
    for (const property of ['Translation', 'Rotation', 'Scaling']) {
      const track = node[property];
      if (!track) continue;
      const scoped = track.Keys.filter(k=>k.Frame >= start && k.Frame <= end);
      for (let i = 1; i < scoped.length; i++) {
        for (const fraction of [0,0.25,0.5,0.75,1]) {
          const frame = scoped[i-1].Frame + (scoped[i].Frame-scoped[i-1].Frame)*fraction;
          reference.rendererData.frame = frame;
          const expected = property === 'Rotation' ? reference.interp.quat(new Float32Array(4),track) : reference.interp.vec3(new Float32Array(3),track);
          const actual = sampleAnimVectorInSequence(track,frame,start,end,[]);
          const error = Math.hypot(...actual.map((value,index)=>value-expected[index]));
          maximumError = Math.max(maximumError,error);
          assert.ok(error < 0.00001,`${node.Name}.${property} at ${frame}: ${error}`);
          comparisons++;
        }
      }
    }
  }
}
assert.ok(comparisons > 1000);
console.log(`Interpolation PASS: ${comparisons} real-source comparisons, maximum error ${maximumError}`);
