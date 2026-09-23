extends SceneTree
const PE2 := preload("res://addons/rts_map/presentation/effects/wc3_pe2_particles.gd")
const BAKE := preload("res://tools/godot/wc3_scn_pe2.gd")
const RIBBON := preload("res://addons/rts_map/presentation/wc3_model/wc3_ribbon_emitter.gd")
const DEPS := preload("res://tools/godot/wc3_scn_dependencies.gd")
const TEMP := "res://tests/.fx_bake_test/"
var failures := 0

class BurstProbe extends GPUParticles3D:
	var received: Array[int] = []
	func emit_burst(count: int) -> void:
		received.append(count)


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP)
	_test_roundtrip()
	_test_spaces_and_materials()
	_test_rate_and_burst_tracks()
	_test_burst_playback()
	_test_dependencies()
	# Only remove explicitly created test files, never asset directories.
	for file in ["ribbon.scn", "model.gltf", "model.ribbon.json", "model.scn", "model.scn.bake.json"]:
		DirAccess.remove_absolute(TEMP + file)
	DirAccess.remove_absolute(TEMP)
	print("selftest_fx_bake_fidelity: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


func _test_roundtrip() -> void:
	var root := Node3D.new()
	var ribbon := RIBBON.new()
	ribbon.name = "Ribbon"
	ribbon.configure(1.7, 17.0, 8.0, 12.0, Color(0.8, 0.2, 0.1, 0.6), null)
	root.add_child(ribbon)
	ribbon.owner = root
	var pe2 := PE2._make_emitter({"speed": 20, "gravity": 10, "life_span": 2, "emission_rate": 15, "particle_scaling": [4, 6, 0], "rows": 4, "columns": 8, "life_span_uv": [0, 7, 1], "decay_uv": [16, 31, 2]}, 0, {})
	root.add_child(pe2)
	pe2.owner = root
	var packed := PackedScene.new()
	_check(packed.pack(root) == OK, "pack scene")
	_check(ResourceSaver.save(packed, TEMP + "ribbon.scn") == OK, "save scene")
	root.free()
	var loaded := ResourceLoader.load(TEMP + "ribbon.scn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_check(loaded != null, "reload saved scene")
	if loaded == null:
		return
	var instance := loaded.instantiate()
	var restored := instance.get_node("Ribbon")
	_check(is_equal_approx(restored.life_span, 1.7), "Ribbon lifetime survives disk roundtrip")
	_check(is_equal_approx(restored.emission_rate, 17.0), "Ribbon rate survives disk roundtrip")
	_check(is_equal_approx(restored.half_height, 10.0), "Ribbon height survives disk roundtrip")
	_check(restored.ribbon_color.is_equal_approx(Color(0.8, 0.2, 0.1, 0.6)), "Ribbon color survives disk roundtrip")
	var particle := instance.get_child(1) as GPUParticles3D
	_check(particle.get("model_gravity") == Vector3(0, -10, 0), "PE2 unscaled gravity survives disk roundtrip")
	var mat := particle.draw_pass_1.surface_get_material(0) as ShaderMaterial
	_check(mat != null and mat.get_shader_parameter("decay_uv") == Vector3(16, 31, 2), "decay atlas survives disk roundtrip")
	instance.free()


func _test_spaces_and_materials() -> void:
	var root := Node3D.new()
	root.scale = Vector3.ONE * 0.01
	get_root().add_child(root)
	for local in [false, true]:
		var p := PE2._make_emitter({"flags": PE2.FLAG_MODEL_SPACE if local else 0, "gravity": 100, "particle_scaling": [20, 10, 0], "speed": 50, "emission_rate": 10, "life_span": 1}, 0, {})
		root.add_child(p)
		var material := p.process_material as ParticleProcessMaterial
		_check(p.local_coords == local, "ModelSpace flag respected")
		_check(is_equal_approx(material.gravity.y, -100.0 if local else -1.0), "gravity uses simulation units")
		_check(is_equal_approx(material.scale_min, 20.0 if local else 0.2), "particle size uses simulation units")
		_check(is_equal_approx(material.initial_velocity_min, 50.0), "emission transform owns velocity conversion")
		p.free()
	root.free()
	for mode in range(5):
		var p := PE2._make_emitter({"filter_mode": mode, "flags": PE2.FLAG_SORT_FAR_Z, "priority_plane": 4}, mode, {})
		var mat := p.draw_pass_1.surface_get_material(0) as ShaderMaterial
		var expected := "blend_add" if mode == 1 or mode == 4 else ("blend_mul" if mode == 2 or mode == 3 else "blend_mix")
		_check(mat.shader.code.contains(expected), "PE2 blend mode %d" % mode)
		_check(mat.render_priority == 4 and p.draw_order == GPUParticles3D.DRAW_ORDER_VIEW_DEPTH, "PE2 sorting metadata respected")
		if mode == 3:
			_check(is_equal_approx(mat.get_shader_parameter("rgb_multiplier"), 2.0), "Modulate2x doubles source")
		p.free()


func _test_rate_and_burst_tracks() -> void:
	var host := Node3D.new()
	get_root().add_child(host)
	var p := PE2._make_emitter({"emission_rate": 100, "life_span": 2, "emission_rate_interpolation": 1, "emission_rate_keys": [{"frame": 1000, "value": 0}, {"frame": 2000, "value": 100}], "active_sequences": ["Birth"]}, 0, {})
	host.add_child(p)
	var ap := AnimationPlayer.new()
	host.add_child(ap)
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 1.0
	library.add_animation("Birth", animation)
	ap.add_animation_library("", library)
	BAKE._inject_rate_and_bursts(animation, p, NodePath(p.name), "Birth", Vector2(1000, 2000))
	ap.play("Birth")
	ap.seek(0.5, true)
	_check(absf(p.amount_ratio - 0.5) < 0.02, "rate ramp reaches half density without restarting particles")
	_check(p.amount == 200, "capacity remains constant")
	p.set_meta("pe2_timeline_baked", true)
	p.emitting = true
	PE2._sync_active_seqs_node(p, {str(p.name): {"active_sequences": ["Birth"]}})
	_check(p.emitting, "metadata refresh preserves the baked timeline state")
	p.emitting = false
	PE2.apply_sequence(host, "Birth")
	_check(not p.emitting, "sequence helper does not override delayed timeline gate")
	p.set_meta("pe2_squirt", true)
	p.set_meta(PE2.META_RATE_KEYS, [{"frame": 1100, "value": 12}, {"frame": 1700, "value": 7}])
	var burst_anim := Animation.new()
	burst_anim.length = 1.0
	BAKE._inject_rate_and_bursts(burst_anim, p, NodePath(p.name), "Birth", Vector2(1000, 2000))
	_check(burst_anim.track_get_type(0) == Animation.TYPE_METHOD and burst_anim.track_get_key_count(0) == 2, "each squirt key becomes one burst")
	_check(is_equal_approx(burst_anim.track_get_key_time(0, 0), 0.1), "burst retains sequence-relative timing")
	_check(burst_anim.track_get_key_value(0, 1)["args"][0] == 7, "burst retains source count")
	host.free()


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(TEMP + path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _test_burst_playback() -> void:
	var host := Node3D.new()
	get_root().add_child(host)
	var p := BurstProbe.new()
	p.name = "Burst"
	host.add_child(p)
	p.set_meta("pe2_squirt", true)
	p.set_meta(PE2.META_ALWAYS_ON, true)
	p.set_meta(PE2.META_RATE_KEYS, [{"frame": 1000, "value": 12}, {"frame": 1500, "value": 7}])
	var animation := Animation.new()
	animation.length = 1.0
	BAKE._inject_rate_and_bursts(animation, p, NodePath("Burst"), "Birth", Vector2(1000, 2000))
	var library := AnimationLibrary.new()
	library.add_animation("Birth", animation)
	var ap := AnimationPlayer.new()
	ap.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	host.add_child(ap)
	ap.add_animation_library("", library)
	ap.play("Birth")
	ap.seek(0.0, true)
	ap.advance(0.01)
	_check(p.received == [12], "t=0 burst fires once after project play/seek sequence")
	ap.advance(0.6)
	_check(p.received == [12, 7], "later burst fires once and preserves earlier burst")
	host.free()


func _test_dependencies() -> void:
	_write("model.gltf", "{}")
	_write("model.ribbon.json", '{"ribbons": []}')
	_write("model.scn", "synthetic scene bytes")
	var deps := DEPS.new()
	var signature := deps.signature(TEMP + "model.gltf")
	_check(deps.record(TEMP + "model.scn", signature) == OK, "record bake signature")
	_check(DEPS.new().is_current(TEMP + "model.scn", DEPS.new().signature(TEMP + "model.gltf")), "unchanged bake is current")
	_write("model.ribbon.json", '{"ribbons": [{"life_span": 2}]}')
	_check(not DEPS.new().is_current(TEMP + "model.scn", DEPS.new().signature(TEMP + "model.gltf")), "Ribbon edit invalidates bake even within same second")
	DirAccess.remove_absolute(TEMP + "model.ribbon.json")
	_check(signature != DEPS.new().signature(TEMP + "model.gltf"), "removed sidecar invalidates bake")
