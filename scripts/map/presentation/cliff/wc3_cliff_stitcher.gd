class_name Wc3CliffStitcher
extends RefCounted

## Adjust only boundary vertices shared with retained ramp ground. Keep original UVs.
static func build_mesh(source: Mesh, xf: Transform3D, hf: Wc3Heightfield, entries: Dictionary, boost: PackedByteArray) -> Mesh:
	var surfaces: Array = []
	var changed := false
	for surface in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(vertices.size()):
			var world := xf * vertices[i]
			var tp := (Vector2(world.x, -world.z) / Wc3Coords.WORLD_SCALE - hf.center_offset) / hf.tile_size
			var near := Vector2i(roundi(tp.x), roundi(tp.y))
			var cell := Vector2i(floori(tp.x), floori(tp.y))
			var on_x := absf(tp.x - near.x) < 0.001
			var on_y := absf(tp.y - near.y) < 0.001
			var shared := (on_x and (entries.has(Vector2i(near.x-1, cell.y)) or entries.has(Vector2i(near.x, cell.y)))) or (on_y and (entries.has(Vector2i(cell.x, near.y-1)) or entries.has(Vector2i(cell.x, near.y))))
			if on_x and on_y:
				shared = entries.has(near) or entries.has(near + Vector2i.LEFT) or entries.has(near + Vector2i.UP) or entries.has(near + Vector2i(-1, -1))
			if not shared:
				continue
			if on_x:
				tp.x = near.x
			if on_y:
				tp.y = near.y
			var x := clampi(floori(tp.x), 0, hf.width - 2)
			var y := clampi(floori(tp.y), 0, hf.height - 2)
			var a := _height(hf, boost, x, y)
			var b := _height(hf, boost, x+1, y)
			var c := _height(hf, boost, x, y+1)
			var d := _height(hf, boost, x+1, y+1)
			var target := lerpf(lerpf(a, b, tp.x-x), lerpf(c, d, tp.x-x), tp.y-y) * Wc3Coords.WORLD_SCALE
			var local_y := (target - xf.origin.y) / xf.basis.y.y
			if absf(vertices[i].y - local_y) > 0.001:
				vertices[i].y = local_y
				changed = true
		arrays[Mesh.ARRAY_VERTEX] = vertices
		surfaces.append(arrays)
	if not changed:
		return source
	var result := ArrayMesh.new()
	for surface in range(surfaces.size()):
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface), surfaces[surface])
		result.surface_set_material(surface, source.surface_get_material(surface))
	return result

static func _height(hf: Wc3Heightfield, boost: PackedByteArray, x: int, y: int) -> float:
	var i := y * hf.width + x
	# Shader still adds the free-height component; bake only layer and ramp offset.
	return (int(hf.layer_heights[i]) - 2) * 128.0 + (64.0 if i < boost.size() and boost[i] != 0 else 0.0)
