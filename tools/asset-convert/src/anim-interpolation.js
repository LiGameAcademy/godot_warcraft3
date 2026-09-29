/** Sample MDX keys without changing DontInterp/Hermite/Bezier semantics. */
export function sampleAnimVector(anim, frame, fallback) {
  if (!anim?.Keys?.length) return fallback;
  const keys = anim.Keys;
  if (frame <= keys[0].Frame) return keys[0].Vector;
  if (frame >= keys.at(-1).Frame) return keys.at(-1).Vector;
  let index = 1;
  while (keys[index].Frame < frame) index += 1;
  const right = keys[index];
  if (right.Frame === frame) return right.Vector;
  const left = keys[index - 1];
  const type = anim.LineType ?? 1;
  if (type === 0) return left.Vector;
  const t = (frame - left.Frame) / (right.Frame - left.Frame);
  if (left.Vector.length === 4) {
    const endpoints = slerp(left.Vector, right.Vector, t);
    if (type === 2 || type === 3) {
      const controls = slerp(left.OutTan, right.InTan, t);
      return slerp(endpoints, controls, 2 * t * (1 - t));
    }
    return endpoints;
  }
  return Float32Array.from(left.Vector, (value, component) => {
    const end = right.Vector[component];
    if (type === 2) {
      return (2*t*t*t - 3*t*t + 1)*value + (t*t*t - 2*t*t + t)*left.OutTan[component]
        + (t*t*t - t*t)*right.InTan[component] + (-2*t*t*t + 3*t*t)*end;
    }
    if (type === 3) {
      return (1-t)**3*value + 3*(1-t)**2*t*left.OutTan[component]
        + 3*(1-t)*t*t*right.InTan[component] + t**3*end;
    }
    return value + (end - value)*t;
  });
}

function slerp(left, right, t) {
  let dot = left.reduce((sum, value, index) => sum + value * right[index], 0);
  const sign = dot < 0 ? -1 : 1;
  dot = Math.min(1, Math.abs(dot));
  const angle = Math.acos(dot);
  const a = dot > 0.999999 ? 1-t : Math.sin((1-t)*angle)/Math.sin(angle);
  const b = dot > 0.999999 ? t : Math.sin(t*angle)/Math.sin(angle);
  const result = Float32Array.from(left, (value, index) => a*value + b*right[index]*sign);
  const length = Math.hypot(...result) || 1;
  return result.map(value => value/length);
}
