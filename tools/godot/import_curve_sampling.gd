extends RefCounted
## Sequence-scoped WC3 step, linear, Hermite and Bezier vectors, in source units.
static func sample(keys: Array, frame: float, kind: int, fallback: Array) -> Array:
	if keys.is_empty():
		return fallback
	var left: Dictionary = keys[0]
	for right: Dictionary in keys:
		if float(right.frame) <= frame:
			left = right
			continue
		var span: float = float(right.frame) - float(left.frame)
		var t: float = clampf((frame - float(left.frame)) / span, 0.0, 1.0) if span > 0.0 else 0.0
		var values: Array[float] = []
		for axis: int in range(fallback.size()):
			var a: float = float(left.vector[axis])
			var b: float = float(right.vector[axis])
			var out_tangent: float = float(left.get("out_tan", left.vector)[axis])
			var in_tangent: float = float(right.get("in_tan", right.vector)[axis])
			match kind:
				1:
					values.append(lerpf(a, b, t))
				2:
					values.append(a*(2*t*t*t-3*t*t+1) + out_tangent*(t*t*t-2*t*t+t) + b*(-2*t*t*t+3*t*t) + in_tangent*(t*t*t-t*t))
				3:
					values.append(a*pow(1-t, 3) + out_tangent*3*t*pow(1-t, 2) + in_tangent*3*t*t*(1-t) + b*pow(t, 3))
				_:
					values.append(a)
		return values
	return left.vector
