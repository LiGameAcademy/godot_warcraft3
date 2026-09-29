import { evaluateNodeWorldMatrices, sampleAnimVectorInSequence, wc3SequenceToAnimName } from './anim.js';
import { wc3ToGltfVec3, mat4Identity } from './mat4.js';
import { extraHelperNodes, uniqueJointName, transformMat4Wc3ToGltf } from './mdx-skeleton.js';

// Explicit camera-facing bones include static nodes, omitted by animkeys.json.
export function billboardPayload(model) {
  const used = new Set();
  return [...(model.Bones ?? []), ...extraHelperNodes(model, model.Bones ?? [])].map(node => ({
    name: uniqueJointName(node, used), flags: node.Flags,
    pivot: wc3ToGltfVec3(...node.PivotPoint),
  })).filter(node => node.flags & 0x78);
}

// Development adapter samples emitter motion/controls, including parent motion.
// Runtime scenes consume baked tracks, never source JSON or an installed editor.
export function particlePayload(model, normalized, textures) {
  const emitters = normalized.emitters.map((em, index) => {
    const source = model.ParticleEmitters2[index];
    const clips = model.Sequences.map(seq => {
      const [start, end] = seq.Interval;
      const times = new Set([start, end]);
      for (let frame = start; frame < end; frame += 1000 / 30) times.add(frame);
      for (const key of ['Visibility', 'EmissionRate', 'Width', 'Length']) {
        for (const k of source[key]?.Keys ?? []) if (k.Frame >= start && k.Frame <= end) times.add(k.Frame);
      }
      const scalar = (key, frame, fallback) => typeof source[key] === 'number' ? source[key] :
        Number(sampleAnimVectorInSequence(source[key], frame, start, end, [fallback])[0]);
      const keys = [...times].sort((a,b) => a-b).map(frame => {
        const matrix = evaluateNodeWorldMatrices(model.Nodes, frame, start, end, model.GlobalSequences ?? [], frame-start)[source.ObjectId] ?? mat4Identity();
        const pivot = source.PivotPoint;
        const position = [0,1,2].map(axis => matrix[axis]*pivot[0]+matrix[axis+4]*pivot[1]+matrix[axis+8]*pivot[2]+matrix[axis+12]);
        const trs = transformMat4Wc3ToGltf(matrix);
        return {time: (frame-start)/1000, position: wc3ToGltfVec3(...position).map(v=>v*0.01), rotation: trs.r, scale: trs.s,
          visible: scalar('Visibility', frame, 1) >= 0.5, rate: scalar('EmissionRate', frame, 0),
          width: scalar('Width', frame, 0), length: scalar('Length', frame, 0)};
      });
      return {name: wc3SequenceToAnimName(seq.Name), keys};
    });
    const unsupported = ['Speed','Variation','Latitude','Gravity'].filter(key=>typeof source[key] === 'object');
    if (Object.values(source).some(track=>track?.GlobalSeqId != null)) unsupported.push('global_sequence_controls');
    return {...em, texture_uri: textures[source.TextureID].uri, clips, unsupported};
  });
  return {version: 1, sample_hz: 30, emitters};
}
