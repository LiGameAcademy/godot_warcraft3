extends SceneTree

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MISSILE MATERIAL: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var cache := MapModelCache.new()
	for cycle in range(3):
		for art in ["Abilities/Weapons/FireBallMissile/FireBallMissile.gltf", "Abilities/Weapons/Rifle/RifleImpact.gltf"]:
			var path := RuntimeAssets.converted_path(art)
			var model := cache.instance_glb(path)
			check(model != null, "真实特效实例化")
			if model == null:
				continue
			root.add_child(model)
			cache.prepare_fx_model(model, path)
			var valid := true
			for node in model.find_children("*", "MeshInstance3D", true, false):
				var mesh_instance := node as MeshInstance3D
				if mesh_instance.mesh == null:
					continue
				for surface in mesh_instance.mesh.get_surface_count():
					valid = valid and mesh_instance.get_active_material(surface) != null
					if mesh_instance.material_override != null:
						valid = valid and mesh_instance.get_surface_override_material(surface) == null
			check(valid, "有效材质保留且不重复覆盖")
			model.queue_free()
			await process_frame
			await process_frame
			check(not is_instance_valid(model), "准备后立即释放不残留实例")
	cache = null
	print("selftest_missile_material_lifetime: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
