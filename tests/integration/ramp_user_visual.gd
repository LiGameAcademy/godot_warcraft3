extends Node
var failures := 0
func _ready() -> void:
	var doc = preload("res://documents/map_document.gd").new()
	var args := OS.get_cmdline_user_args()
	var map_path := args[0] if args.size() > 0 else "res://tests/fixtures/editor/ramp-user-111.wc3map.json"
	if doc.load_json(map_path) != OK:
		get_tree().quit(1)
		return
	var turns := int(args[1]) if args.size() > 1 else 0
	if turns > 0:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(map_path))
		var data: Dictionary = raw.terrain
		var width := int(data.tilepointWidth)
		assert(width == int(data.tilepointHeight))
		for turn in range(turns):
			for key in data:
				if data[key] is Array and data[key].size() == width * width:
					var rotated: Array = data[key].duplicate()
					for y in range(width):
						for x in range(width):
							rotated[x * width + width - 1 - y] = data[key][y * width + x]
					data[key] = rotated
		doc.heightfield = Wc3Heightfield.from_dict(data)
		doc._rebind_logic()
	var hf: Wc3Heightfield = doc.heightfield
	var average := Vector2.ZERO
	var count := 0
	for i in range(hf.flags_packed.size()):
		if int(hf.flags_packed[i]) & Wc3Coords.FLAG_RAMP:
			average += Vector2(i % hf.width, i / hf.width)
			count += 1
	average /= maxf(count, 1)
	var xy := hf.center_offset + average * hf.tile_size
	var center := Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, 0)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = center + (Vector3(3.5, 5, 4) if map_path.contains("222") else Vector3(3.5, 5, -4))
	camera.look_at(center)
	camera.current = true
	var map: MapLoader = preload("res://packages/map/scenes/map/map_root.tscn").instantiate()
	map.auto_load_on_ready = false
	map.place_units = false
	map.place_doodads = false
	map.status_path = NodePath("")
	add_child(map)
	await get_tree().process_frame
	await map.reload_from_hf(doc.as_build_dict(), doc.info, "res://")
	var cliff_layer: MapCliffLayer = map.get_node("Cliffs")
	var terrain: MapTerrainLayer = map.get_node("Terrain")
	var ctx := MapBuildContext.create("res://", doc.as_build_dict(), doc.info, map.get_tiles(), map.get_id_catalog(), map._cache, map.get_cliff_catalog())
	ctx.ensure_ramp_topology()
	if map_path.contains("222"):
		# The original CliffTrans edge at these two low-side midpoints is -64 WC3,
		# while the saved terrain is -128. Assert actual mounted geometry agrees.
		var samples := {Vector2i(28, 27): -0.5, Vector2i(30, 26): -0.5}
		for turn in range(turns):
			var rotated := {}
			for point in samples:
				rotated[Vector2i(hf.width - 1 - point.y, point.x)] = samples[point]
			samples = rotated
		for point in samples:
			var ramp_count := 0
			var cliff_count := 0
			for node in map.get_node("Ramps").get_children():
				if node is MeshInstance3D:
					ramp_count += _check_sample(node.mesh, node.transform, point, samples[point], hf)
			for instance in cliff_layer._instances:
				cliff_count += _check_sample(instance.mm.mesh, instance.xf, point, samples[point], hf)
			if ramp_count == 0 or cliff_count == 0:
				failures += 1
				push_error("222 boundary was not checked on both models at %s" % point)
	# The continued 111 fixture exposed a non-linear rock edge against linear ramp ground.
	if map_path.contains("continued") or map_path.contains("repaired"):
		var edge_count := 0
		for instance in cliff_layer._instances:
			if instance.ix != 34 or instance.iy != 30:
				continue
			var mesh: Mesh = instance.mm.mesh
			for surface in range(mesh.get_surface_count()):
				for vertex in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					var world: Vector3 = instance.xf * vertex
					var tile := (Vector2(world.x, -world.z) / Wc3Coords.WORLD_SCALE - hf.center_offset) / hf.tile_size
					if absf(tile.y - 30.0) < 0.001 and tile.x >= 33.999 and tile.x <= 35.001:
						edge_count += 1
						if absf(world.y / 1.28 - (1.0 - 0.5 * (tile.x - 34.0))) > 0.001:
							failures += 1
							push_error("Continued ramp shared edge is open at %s" % tile)
		if edge_count < 4:
			failures += 1
			push_error("Continued ramp seam was not exercised")
	for y in range(hf.height - 1):
		for x in range(hf.width - 1):
			var ids := [y * hf.width + x, y * hf.width + x + 1, (y + 1) * hf.width + x, (y + 1) * hf.width + x + 1]
			var levels: Array[int] = []
			var marked := true
			for id in ids:
				levels.append(int(hf.layer_heights[id]))
				marked = marked and (int(hf.flags_packed[id]) & 4) != 0
			var entrance := marked and not (levels[0] == levels[3] and levels[1] == levels[2])
			var cliff: bool = levels.min() != levels.max()
			var should_exist: bool = not ((cliff or ctx.ramp.romp[ids[0]] != 0) and not entrance)
			if (terrain._cell_first_vertex[y * (hf.width - 1) + x] >= 0) != should_exist:
				failures += 1
				push_error("User map ground differs from HiveWE at %d,%d" % [x, y])
	map.set_view_grid_level(0)
	map.set_show_ramp_debug(false)
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tmp/ramp-user-111-fixed.png")
	print("ramp_user_visual: rendered user map, %d coverage/seam failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_sample(mesh: Mesh, xf: Transform3D, point: Vector2i, expected: float, hf: Wc3Heightfield) -> int:
	var count := 0
	for surface in range(mesh.get_surface_count()):
		for vertex in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var world: Vector3 = xf * vertex
			var tile := (Vector2(world.x, -world.z) / 0.01 - hf.center_offset) / 128.0
			if tile.distance_to(Vector2(point)) < 0.001:
				count += 1
				if absf(world.y / 1.28 - expected) > 0.001:
					failures += 1
					push_error("222 seam height mismatch at %s: %s vs %s" % [point, world.y / 1.28, expected])
	return count
