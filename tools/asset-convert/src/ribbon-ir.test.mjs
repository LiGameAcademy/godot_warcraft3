import assert from 'node:assert/strict';
import fs from 'node:fs';
import {ModelRenderer} from 'war3-model';
import {parseModel} from './convert-mdx.js';
import {ribbonPayload} from './mdx-ribbon-ir.js';

const logical='Abilities/Spells/Human/Resurrect/Resurrecttarget.mdx';
const source=new URL('../../../.cache/wc3-assets/'+logical,import.meta.url);
const model=parseModel(fs.readFileSync(source),logical);
const payload=ribbonPayload(model,model.Textures.map(()=>({uri:'texture.png'})));
const reference=new ModelRenderer(model);
reference.setSequence(0);
let comparisons=0;
let maximumError=0;
for (let index=0;index<model.RibbonEmitters.length;index++) {
  const emitter=model.RibbonEmitters[index];
  assert.deepEqual(payload.emitters[index].unsupported,[]);
  for (const key of payload.emitters[index].clips[0].keys) {
    reference.rendererData.frame=key.time*1000;
    reference.rendererData.globalSequencesFrames=model.GlobalSequences.map(duration=>key.time*1000%duration);
    reference.updateNode(reference.rendererData.rootNode);
    const matrix=reference.rendererData.nodes[emitter.ObjectId].matrix;
    for (const [field,height] of [['below',-reference.interp.animVectorVal(emitter.HeightBelow,0)],['above',reference.interp.animVectorVal(emitter.HeightAbove,0)]]) {
      const point=Array.from(emitter.PivotPoint); point[1]+=height;
      const world=[0,1,2].map(axis=>matrix[axis]*point[0]+matrix[axis+4]*point[1]+matrix[axis+8]*point[2]+matrix[axis+12]);
      const expected=[world[0]*0.01,world[2]*0.01,-world[1]*0.01];
      const error=Math.hypot(...expected.map((value,axis)=>value-key[field][axis]));
      maximumError=Math.max(maximumError,error);
      assert.ok(error<0.0001,`${emitter.Name} ${field} ${key.time}: ${error}`);
      comparisons++;
    }
  }
}
// Unsupported source semantics must remain explicit rather than silently approximated.
model.RibbonEmitters[0].Gravity=1;
assert.ok(ribbonPayload(model,[]).emitters[0].unsupported.includes('gravity'));
console.log(`Ribbon source reference PASS: ${comparisons} endpoints, maximum error ${maximumError} metres`);
