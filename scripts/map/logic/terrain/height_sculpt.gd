extends RefCounted
## Height tools change ground height only; cliff layers and water planes stay intact.
enum Tool { RAISE, LOWER, PLATEAU, NOISE, SMOOTH }
const STEP := 16.0


static func apply(hf: Wc3Heightfield, points: Array, tool: int, plateau_offset: float = 0.0) -> bool:
	if hf == null or not hf.is_valid() or tool < Tool.RAISE or tool > Tool.SMOOTH:
		return false
	# Smooth reads one immutable stamp, independent of point iteration order.
	var previous: Array = hf.heights.duplicate()
	var changed := false
	var seen := {}
	for point: Vector2i in points:
		if not hf.in_bounds(point.x, point.y):
			continue
		var index := hf.index_at(point.x, point.y)
		if seen.has(index):
			continue
		seen[index] = true
		var height := float(previous[index])
		var layer := int(hf.layer_heights[index])
		var base := float(layer - 2) * 128.0
		var next := height
		match tool:
			Tool.RAISE: next += STEP
			Tool.LOWER: next -= STEP
			Tool.PLATEAU: next = base + plateau_offset
			Tool.NOISE: next += randf_range(-STEP, STEP)
			Tool.SMOOTH:
				var total := 0.0
				var count := 0
				for y in range(point.y - 1, point.y + 2):
					for x in range(point.x - 1, point.x + 2):
						if hf.in_bounds(x, y):
							var neighbor := hf.index_at(x, y)
							if int(hf.layer_heights[neighbor]) == layer:
								total += float(previous[neighbor])
								count += 1
				if count > 0:
					next = lerpf(height, total / count, 0.5)
		# Respect the imported unsigned 16-bit groundHeightRaw range (w3e parser).
		next = clampf(next, base - 2048.0, base + 14335.75)
		if not is_equal_approx(next, height):
			hf.heights[index] = next
			changed = true
	return changed
