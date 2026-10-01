extends Node
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _ready() -> void:
	var doc = preload("res://documents/map_document.gd").new()
	doc.create_from_options({"width": 8, "height": 8, "ground_tilesets": ["Ldrt","Lgrs"], "cliff_tilesets": ["CLdi","CLgr"]})
	var map: MapLoader = preload("res://packages/map/scenes/map/map_root.tscn").instantiate()
	map.auto_load_on_ready = false
	map.place_units = false
	map.place_doodads = false
	map.status_path = NodePath("")
	add_child(map)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(2.5,5,3.5)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var hf: Wc3Heightfield = doc.heightfield
	var points := [Vector2i(3,3),Vector2i(4,3),Vector2i(3,4),Vector2i(4,4)]
	for levels in [[2,3,3,2],[2,4,3,2]]:
		hf.layer_heights.fill(2)
		hf.heights.fill(0.0)
		hf.flags_packed.fill(0)
		for i in range(4):
			var index: int = points[i].y*hf.width+points[i].x
			hf.layer_heights[index] = levels[i]
			hf.heights[index] = (levels[i]-2)*128.0
			hf.flags_packed[index] = 4
		var before := hf.flags_packed.duplicate()
		await map.reload_from_hf(doc.as_build_dict(),doc.info,"res://")
		var ctx := MapBuildContext.create("res://",doc.as_build_dict(),doc.info,map.get_tiles(),map.get_id_catalog(),map._cache,map.get_cliff_catalog())
		ctx.ensure_ramp_surface_plan()
		var plan: Dictionary = ctx.ramp_surface_plan
		check(plan.fallback_tiles.has(Vector2i(3,3)), "unsupported full ramp uses fallback")
		var terrain: MapTerrainLayer = map.get_node("Terrain")
		check(terrain._cell_first_vertex[3*8+3] >= 0, "fallback emits textured terrain")
		var first: int = terrain._cell_first_vertex[3*8+3]
		var vertices: PackedVector3Array = terrain._ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var corners := {}
		for index in range(first, first + 6):
			var v := vertices[index]
			var tile := (Vector2(v.x,-v.z)/0.01 - hf.center_offset)/128.0
			corners[Vector2i(roundi(tile.x),roundi(tile.y))] = v.y
		check(corners.size() == 4, "fallback has four explicit boundary corners")
		for index in [first, first+3]:
			check((vertices[index+1]-vertices[index]).cross(vertices[index+2]-vertices[index]).length() > 0.0001, "fallback triangles are nondegenerate")
		var cliffs: MapCliffLayer = map.get_node("Cliffs")
		for instance in cliffs._instances:
			check(instance.ix != 3 or instance.iy != 3, "fallback does not overlap a straight cliff")
		var edge_samples := 0
		for instance in cliffs._instances:
			var mesh: Mesh = instance.mm.mesh
			for surface in range(mesh.get_surface_count()):
				for vertex in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					var world: Vector3 = instance.xf * vertex
					var tile := (Vector2(world.x,-world.z)/0.01 - hf.center_offset)/128.0
					if tile.x < 2.999 or tile.x > 4.001 or tile.y < 2.999 or tile.y > 4.001:
						continue
					if minf(minf(absf(tile.x-3),absf(tile.x-4)),minf(absf(tile.y-3),absf(tile.y-4))) > 0.001:
						continue
					var expected := lerpf(lerpf(corners[Vector2i(3,3)],corners[Vector2i(4,3)],tile.x-3),lerpf(corners[Vector2i(3,4)],corners[Vector2i(4,4)],tile.x-3),tile.y-3)
					check(absf(world.y-expected) < 0.001, "cliff perimeter agrees with emitted fallback ground")
					edge_samples += 1
		check(edge_samples >= 8, "fallback seam inspected on neighboring models")
		check(hf.flags_packed == before, "render policy leaves saved flags untouched")
		var total := 0
		for count in plan.routes.values():
			total += int(count)
		check(total == 64, "each cell has one route")
		print("fallback ", levels, " routes=", plan.routes)
	map.set_view_grid_level(0)
	map.set_show_ramp_debug(false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tmp/ramp-fallback.png")
	hf.flags_packed.fill(0)
	await map.reload_from_hf(doc.as_build_dict(),doc.info,"res://")
	var restored: MapTerrainLayer = map.get_node("Terrain")
	check(restored._cell_first_vertex[3*8+3] < 0, "erasing ramp flags removes fallback ground")
	var has_cliff := false
	for instance in (map.get_node("Cliffs") as MapCliffLayer)._instances:
		if instance.ix == 3 and instance.iy == 3:
			has_cliff = true
	check(has_cliff, "erasing fallback restores original cliff")
	print("selftest_ramp_fallback: %s failures=%d" % ["PASS" if failures == 0 else "FAIL",failures])
	get_tree().quit(0 if failures == 0 else 1)
