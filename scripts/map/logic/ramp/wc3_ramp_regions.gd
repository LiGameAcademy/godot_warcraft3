extends RefCounted
## Eight-connected active ramp cells: a shared corner is also a seam dependency.
## Ordinary terrain and incomplete flags are deliberately not flood-fill candidates.
static func build(candidates: Dictionary, seeds: Dictionary) -> Array:
	var visited := {}
	var regions: Array = []
	for start in candidates:
		if visited.has(start):
			continue
		var queue: Array[Vector2i] = [start]
		visited[start] = true
		var index := 0
		var seeded := false
		var members := {}
		while index < queue.size():
			var tile := queue[index]
			index += 1
			members[tile] = true
			seeded = seeded or seeds.has(tile)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var next := tile + Vector2i(dx,dy)
					if candidates.has(next) and not visited.has(next):
						visited[next] = true
						queue.append(next)
		if not seeded:
			continue
		var boundary: Array = []
		for tile in members:
			for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				if not members.has(tile+direction):
					boundary.append({"tile": tile, "direction": direction})
		regions.append({"cells": members, "boundary": boundary})
	return regions
