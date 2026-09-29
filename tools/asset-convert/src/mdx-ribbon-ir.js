import { evaluateNodeWorldMatrices, sampleAnimVectorInSequence, sequenceBakeDurationMs, wc3SequenceToAnimName } from './anim.js';
import { wc3ToGltfVec3 } from './mat4.js';

// Ribbon width follows the emitter's source Y axis, not a camera-facing strip.
export function ribbonPayload(model, textures) {
  return {version: 1, sample_hz: 30, emitters: (model.RibbonEmitters ?? []).map(source => {
    const layers = model.Materials[source.MaterialID]?.Layers ?? [];
    const layer = layers[0] ?? {};
    const unsupported = [];
    if (layers.length !== 1) unsupported.push('material_layers');
    if (![2, 3, 4].includes(layer.FilterMode)) unsupported.push('filter_mode');
    if (typeof layer.TextureID !== 'number' || layer.TVertexAnimId != null) unsupported.push('texture_animation');
    if (typeof layer.Alpha !== 'number') unsupported.push('layer_alpha_animation');
    if (source.Gravity) unsupported.push('gravity');
    if (Object.values(source).some(v => v?.GlobalSeqId != null && v.GlobalSeqId >= 0)) unsupported.push('global_controls');
    const clips = model.Sequences.map(seq => {
      const [start, end] = seq.Interval;
      const duration = sequenceBakeDurationMs(start, end, !seq.NonLooping, model.Nodes, model.GlobalSequences ?? []);
      const times = new Set([0, duration]);
      for (let t = 0; t < duration; t += 1000 / 30) times.add(t);
      for (const field of ['Visibility', 'HeightAbove', 'HeightBelow', 'Alpha', 'TextureSlot']) {
        for (const key of source[field]?.Keys ?? []) {
          if (key.Frame < start || key.Frame > end) continue;
          for (let offset = 0; offset < duration; offset += Math.max(1, end-start)) {
            const t = key.Frame-start+offset;
            if (t <= duration) { times.add(t); if (t > 0) times.add(t-0.001); }
          }
        }
      }
      const keys = [...times].sort((a,b)=>a-b).map(time => {
        const wrapped = time % Math.max(1, end-start);
        const frame = seq.NonLooping ? start+time : time > 0 && wrapped < 0.000001 ? end : start+wrapped;
        const scalar = (field, fallback) => typeof source[field] === 'number' ? source[field] :
          Number(sampleAnimVectorInSequence(source[field], frame, start, end, [fallback])[0]);
        const matrix = evaluateNodeWorldMatrices(model.Nodes, frame, start, end, model.GlobalSequences ?? [], time)[source.ObjectId];
        const endpoint = height => {
          const p = Array.from(source.PivotPoint); p[1] += height;
          const world = [0,1,2].map(axis=>matrix[axis]*p[0]+matrix[axis+4]*p[1]+matrix[axis+8]*p[2]+matrix[axis+12]);
          return wc3ToGltfVec3(...world).map(v=>v*0.01);
        };
        return {time:time/1000, below:endpoint(-scalar('HeightBelow',0)), above:endpoint(scalar('HeightAbove',0)),
          emitting:scalar('Visibility',1)>0, alpha:scalar('Alpha',1), slot:scalar('TextureSlot',0)};
      });
      return {name:wc3SequenceToAnimName(seq.Name), keys};
    });
    return {name:source.Name, life_span:source.LifeSpan, emission_rate:source.EmissionRate,
      color:Array.from(source.Color), rows:source.Rows, columns:source.Columns,
      filter_mode:layer.FilterMode, layer_alpha:layer.Alpha, texture_uri:textures[layer.TextureID]?.uri,
      unsupported, clips};
  })};
}
