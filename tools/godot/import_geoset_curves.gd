extends RefCounted
## Single Blend surfaces: independent layer alpha, Geoset alpha and RGB curves.
## The adapter's color vectors are already in RGB order (MDL parsing reverses BGR).
static func compile(mesh: MeshInstance3D, player: AnimationPlayer, entry: Dictionary, sequences: Array) -> Dictionary:
	var result: Dictionary = {"ok": false, "surfaces": 0, "tracks": 0}
	var alpha: Dictionary = entry.get("alpha", {}) if entry.get("alpha") is Dictionary else {}
	var color: Dictionary = entry.get("color", {}) if int(entry.get("flags", 0)) & 2 and entry.get("color") is Dictionary else {}
	if not _supported(alpha, 1) or not _supported(color, 3):
		return result
	for surface: int in range(mesh.mesh.get_surface_count()):
		var original: Material = mesh.get_active_material(surface)
		if original is ShaderMaterial and original.has_meta("import_fx_material"):
			continue
		if not original is StandardMaterial3D or int(original.get_meta("import_filter_mode", -1)) != 2:
			return result
	for surface: int in range(mesh.mesh.get_surface_count()):
		var original: Material = mesh.get_active_material(surface)
		var material: ShaderMaterial = original if original is ShaderMaterial else _material(original)
		mesh.set_surface_override_material(surface, material)
		var prefix: String = str(player.get_parent().get_path_to(mesh)) + ":surface_material_override/%d:" % surface
		for sequence: Dictionary in sequences:
			var animation: Animation = player.get_animation(str(sequence.name))
			# Move the layer track to its independent uniform, preserving its keys.
			for track: int in range(animation.get_track_count()):
				if str(animation.track_get_path(track)) == prefix + "albedo_color:a":
					animation.track_set_path(track, NodePath(prefix + "shader_parameter/layer_alpha"))
			var alpha_initial: Variant = _add_track(animation, sequence, alpha, prefix + "shader_parameter/geoset_alpha", false)
			var color_initial: Variant = _add_track(animation, sequence, color, prefix + "shader_parameter/geoset_color", true)
			if sequence == sequences[0]:
				material.set_shader_parameter("geoset_alpha", alpha_initial)
				material.set_shader_parameter("geoset_color", color_initial)
			result.tracks += 2
		result.surfaces += 1
	mesh.visible = true
	result.ok = true
	return result

static func _supported(curve: Dictionary, dimensions: int) -> bool:
	var global_sequence: Variant = curve.get("global_seq_id")
	if (global_sequence != null and int(global_sequence) >= 0) or int(curve.get("line_type", 0)) not in [0, 1]:
		return false
	var values: Array = [curve.static] if curve.has("static") else []
	for key: Dictionary in curve.get("keys", []):
		values.append(key.vector)
	for value: Variant in values:
		var components: Array = value if value is Array else [value]
		if components.size() != dimensions:
			return false
		for component: Variant in components:
			if not (component is float or component is int) or not is_finite(float(component)) or float(component) < 0.0 or float(component) > 1.0:
				return false
	return true

static func _value(value: Variant, color: bool) -> Variant:
	if color:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return float(value[0]) if value is Array else float(value)

static func _add_track(animation: Animation, sequence: Dictionary, curve: Dictionary, path: String, color: bool) -> Variant:
	var initial: Variant = Vector3.ONE if color else 1.0
	var start: float = float(sequence.interval[0])
	var end: float = float(sequence.interval[1])
	var keys: Array[Dictionary] = []
	var carry: Variant = null
	for key: Dictionary in curve.get("keys", []):
		if float(key.frame) < start:
			carry = _value(key.vector, color)
		elif float(key.frame) <= end:
			keys.append(key)
	if curve.has("static"):
		initial = _value(curve.static, color)
	elif not keys.is_empty():
		initial = _value(keys[0].vector, color) if float(keys[0].frame) == start or carry == null else carry
	var index: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(index, NodePath(path))
	var stepped: bool = int(curve.get("line_type", 0)) == 0
	animation.value_track_set_update_mode(index, Animation.UPDATE_DISCRETE if stepped else Animation.UPDATE_CONTINUOUS)
	animation.track_set_interpolation_type(index, Animation.INTERPOLATION_NEAREST if stepped else Animation.INTERPOLATION_LINEAR)
	animation.track_set_interpolation_loop_wrap(index, false)
	animation.track_insert_key(index, 0.0, initial)
	for key: Dictionary in keys:
		animation.track_insert_key(index, (float(key.frame) - start) / 1000.0, _value(key.vector, color))
	return initial

static func _material(original: StandardMaterial3D) -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, %s;
uniform sampler2D diffuse_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_texture = false;
uniform vec3 base_color = vec3(1.0);
uniform float layer_alpha = 1.0;
uniform float geoset_alpha = 1.0;
uniform vec3 geoset_color = vec3(1.0);
void fragment() {
 vec4 texel = has_texture ? texture(diffuse_tex, UV) : vec4(1.0);
 ALBEDO = texel.rgb * base_color * geoset_color;
 ALPHA = texel.a * layer_alpha * geoset_alpha;
 ROUGHNESS = 1.0;
 SPECULAR = 0.0;
}
""" % (("cull_disabled" if original.cull_mode == BaseMaterial3D.CULL_DISABLED else "cull_back") + (", unshaded" if original.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED else ""))
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.resource_local_to_scene = true
	material.set_shader_parameter("diffuse_tex", original.albedo_texture)
	material.set_shader_parameter("has_texture", original.albedo_texture != null)
	material.set_shader_parameter("base_color", Vector3(original.albedo_color.r, original.albedo_color.g, original.albedo_color.b))
	material.set_shader_parameter("layer_alpha", original.albedo_color.a)
	material.set_meta("import_geoset_curves", true)
	for key: StringName in original.get_meta_list():
		material.set_meta(key, original.get_meta(key))
	return material
