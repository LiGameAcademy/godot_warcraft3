extends Node
var failures := 0
func _ready() -> void:
	var doc = preload("res://editor/scripts/map_document.gd").new()
	var args := OS.get_cmdline_user_args()
	var map_path := args[0] if args.size() > 0 else "res://tests/fixtures/editor/ramp-user-111.wc3map.json"
	if doc.load_json(map_path) != OK:
		get_tree().quit(1)
		return
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
	camera.position = center + Vector3(3.5, 5, -4)
	camera.look_at(center)
	camera.current = true
	var map: MapLoader = preload("res://scenes/map/map_root.tscn").instantiate()
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
