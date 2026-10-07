extends RefCounted
const ParticleMaterial: GDScript = preload("res://packages/map/presentation/wc3_model/wc3_pe2_material.gd")

static func compile(scene: Node3D, ir: Dictionary, texture_base: String) -> Dictionary:
	var result: Dictionary = {"emitters": 0, "tracks": 0, "diagnostics": []}
	var payload: Dictionary = ir.get("particles", {}).get("payload", {})
	var players: Array[Node] = scene.find_children("*", "AnimationPlayer", true, false)
	if int(ir.get("particles", {}).get("count", 0)) > 0 and payload.is_empty():
		result.diagnostics.append({"code": "particle_payload_missing", "severity": "warning"})
	for em: Dictionary in payload.get("emitters", []):
		if bool(em.get("squirt", false)) or not em.get("unsupported", []).is_empty() or players.size() != 1:
			result.diagnostics.append({"code": "particle_controls_pending", "severity": "warning", "emitter": em.name, "fields": em.get("unsupported", [])})
			continue
		var image: Image = Image.load_from_file(texture_base.path_join(str(em.texture_uri)).simplify_path())
		if image == null:
			result.diagnostics.append({"code": "particle_texture_missing", "severity": "warning", "emitter": em.name})
			continue
		image.generate_mipmaps()
		var particle: GPUParticles3D = _build(em, ImageTexture.create_from_image(image))
		scene.add_child(particle)
		particle.owner = scene
		result.tracks += _tracks(players[0], particle, em)
		result.emitters += 1
		result.diagnostics.append({"code": "particle_simulation_approximation", "severity": "info", "emitter": em.name, "message": "Godot native simulation; motion/controls sampled at 30 Hz, tail uses velocity-aligned quads"})
	return result

static func _build(em: Dictionary, texture: Texture2D) -> GPUParticles3D:
	var particle: GPUParticles3D = GPUParticles3D.new()
	particle.name = str(em.name)
	particle.lifetime = maxf(0.01, float(em.life_span))
	var peak: float = float(em.emission_rate)
	for clip: Dictionary in em.clips:
		for key: Dictionary in clip.keys:
			peak = maxf(peak, float(key.rate))
	particle.amount = clampi(ceili(peak * particle.lifetime), 1, 4096)
	particle.local_coords = int(em.flags) & 0x80000 != 0
	particle.emitting = false
	particle.use_fixed_seed = true
	particle.seed = 42
	particle.visibility_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
	particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particle.set_meta("import_particle", true)
	var tail: bool = int(em.frame_flags) & 2 != 0
	var quad: QuadMesh = QuadMesh.new()
	quad.material = ParticleMaterial.build(em, texture, tail)
	quad.size = Vector2(1.0, clampf(float(em.tail_length) * maxf(absf(float(em.speed)), 1.0) / maxf(float(em.particle_scaling[1]), 0.1), 1.0, 8.0) if tail else 1.0)
	particle.draw_pass_1 = quad
	if int(em.frame_flags) == 3:
		var head: QuadMesh = QuadMesh.new()
		head.material = ParticleMaterial.build(em, texture, false)
		particle.draw_passes = 2
		particle.draw_pass_2 = head
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.resource_local_to_scene = true
	process.direction = Vector3.UP if float(em.speed) >= 0.0 else Vector3.DOWN
	process.spread = clampf(float(em.latitude), 0.0, 180.0)
	var speed: float = absf(float(em.speed)) * 0.01
	var variation: float = clampf(float(em.variation), 0.0, 1.0)
	process.initial_velocity_min = speed * (1.0 - variation)
	process.initial_velocity_max = speed * (1.0 + variation)
	process.gravity = Vector3(0.0, -float(em.gravity) * 0.01, 0.0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(float(em.width), 0.0, float(em.length)) * 0.005
	process.particle_flag_align_y = tail
	var sizes: Array = em.particle_scaling
	var maximum: float = maxf(maxf(float(sizes[0]), float(sizes[1])), maxf(float(sizes[2]), 0.001))
	process.scale_min = maximum * 0.01
	process.scale_max = maximum * 0.01
	var middle: float = clampf(float(em.time_middle), 0.001, 0.999)
	var curve: Curve = Curve.new()
	for index: int in range(3):
		curve.add_point(Vector2([0.0, middle, 1.0][index], float(sizes[index]) / maximum), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	var scale_texture: CurveTexture = CurveTexture.new()
	scale_texture.curve = curve
	process.scale_curve = scale_texture
	var gradient: Gradient = Gradient.new()
	var colors: PackedColorArray = []
	for index: int in range(3):
		var color: Array = em.segment_color[index]
		colors.append(Color(color[0], color[1], color[2], float(em.alpha[index]) / 255.0))
	gradient.offsets = PackedFloat32Array([0.0, middle, 1.0])
	gradient.colors = colors
	var color_texture: GradientTexture1D = GradientTexture1D.new()
	color_texture.gradient = gradient
	process.color_ramp = color_texture
	particle.process_material = process
	return particle

static func _tracks(player: AnimationPlayer, particle: GPUParticles3D, em: Dictionary) -> int:
	var count: int = 0
	var path: String = str(player.get_parent().get_path_to(particle))
	for clip: Dictionary in em.clips:
		if not player.has_animation(str(clip.name)):
			continue
		var animation: Animation = player.get_animation(str(clip.name))
		var position: int = _track(animation, path, Animation.TYPE_POSITION_3D)
		var rotation: int = _track(animation, path, Animation.TYPE_ROTATION_3D)
		var scale: int = _track(animation, path, Animation.TYPE_SCALE_3D)
		var emitting: int = _track(animation, path + ":emitting", Animation.TYPE_VALUE)
		var ratio: int = _track(animation, path + ":amount_ratio", Animation.TYPE_VALUE)
		var box: int = _track(animation, path + ":process_material:emission_box_extents", Animation.TYPE_VALUE)
		for track: int in [emitting, ratio, box]:
			animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
			animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
		for key: Dictionary in clip.keys:
			var time: float = minf(float(key.time), animation.length)
			animation.track_insert_key(position, time, _vec(key.position))
			animation.track_insert_key(rotation, time, Quaternion(key.rotation[0], key.rotation[1], key.rotation[2], key.rotation[3]))
			animation.track_insert_key(scale, time, _vec(key.scale))
			animation.track_insert_key(emitting, time, bool(key.visible) and float(key.rate) > 0.0)
			animation.track_insert_key(ratio, time, clampf(float(key.rate) * particle.lifetime / particle.amount, 0.0, 1.0))
			animation.track_insert_key(box, time, Vector3(float(key.width), 0.0, float(key.length)) * 0.005)
		count += 6
	return count

static func _track(animation: Animation, path: String, type: int) -> int:
	var index: int = animation.add_track(type)
	animation.track_set_path(index, NodePath(path))
	animation.track_set_interpolation_loop_wrap(index, false)
	return index

static func _vec(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
