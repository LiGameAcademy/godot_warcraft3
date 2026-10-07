extends RefCounted
## Camera sidecar v1 vectors are Y-up/metres; their tangents remain native WC3.
static func sample(track: Variant, frame: float, start: float, end: float, scalar: bool = false) -> Vector3:
	if not track is Dictionary:
		return Vector3.ZERO
	var curve: Dictionary = track as Dictionary
	if curve.get("global_seq_id") != null and int(curve.global_seq_id) >= 0:
		return Vector3.ZERO
	var keys: Array[Dictionary] = []
	for key: Dictionary in curve.get("keys", []):
		if float(key.frame) >= start and float(key.frame) <= end:
			keys.append(key)
	if keys.is_empty():
		return Vector3.ZERO
	var left: Dictionary = keys[0]
	for right: Dictionary in keys:
		if float(right.frame) <= frame:
			left = right
			continue
		var from: Vector3 = _vector(left.vector)
		var to: Vector3 = _vector(right.vector)
		var span: float = float(right.frame) - float(left.frame)
		var t: float = clampf((frame - float(left.frame)) / span, 0.0, 1.0) if span > 0.0 else 0.0
		match int(curve.get("line_type", 0)):
			1:
				return from.lerp(to, t)
			2:
				var out_tangent: Vector3 = _tangent(left.get("out_tan", []), scalar)
				var in_tangent: Vector3 = _tangent(right.get("in_tan", []), scalar)
				return from * (2*t*t*t - 3*t*t + 1) + out_tangent * (t*t*t - 2*t*t + t) + to * (-2*t*t*t + 3*t*t) + in_tangent * (t*t*t - t*t)
			3:
				var out_tangent: Vector3 = _tangent(left.get("out_tan", []), scalar)
				var in_tangent: Vector3 = _tangent(right.get("in_tan", []), scalar)
				return from * pow(1-t, 3) + out_tangent * (3*t*pow(1-t, 2)) + in_tangent * (3*t*t*(1-t)) + to * pow(t, 3)
			_:
				return from
	return _vector(left.vector)

static func _vector(value: Array) -> Vector3:
	if value.size() == 1:
		return Vector3(float(value[0]), 0, 0)
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value.size() >= 3 else Vector3.ZERO

static func _tangent(value: Array, scalar: bool) -> Vector3:
	var raw: Vector3 = _vector(value)
	return raw if scalar else Vector3(raw.x, raw.z, -raw.y) * Wc3Coords.WORLD_SCALE
