extends RefCounted
const Runtime: GDScript = preload("import_ribbon_runtime.gd")

static func compile(scene: Node3D, ir: Dictionary, texture_base: String) -> Dictionary:
	var result: Dictionary = {"ribbons": 0, "diagnostics": []}
	var payload: Dictionary = ir.get("ribbons", {}).get("payload", {})
	var players: Array[Node] = scene.find_children("*", "AnimationPlayer", true, false)
	if int(ir.get("ribbons", {}).get("count", 0)) > 0 and payload.is_empty():
		result.diagnostics.append({"code": "ribbon_payload_missing", "severity": "warning"})
	for em: Dictionary in payload.get("emitters", []):
		if not em.unsupported.is_empty() or players.size() != 1 or float(em.life_span) <= 0.0 or float(em.emission_rate) * float(em.life_span) > 4096:
			result.diagnostics.append({"code": "ribbon_controls_pending", "severity": "warning", "emitter": em.name, "fields": em.unsupported})
			continue
		var image: Image = Image.load_from_file(texture_base.path_join(str(em.texture_uri)).simplify_path())
		if image == null:
			result.diagnostics.append({"code": "ribbon_texture_missing", "severity": "warning", "emitter": em.name})
			continue
		var script: GDScript = GDScript.new()
		script.source_code = Runtime.source_code
		if script.reload() != OK:
			result.diagnostics.append({"code": "ribbon_script_invalid", "severity": "error"})
			continue
		var ribbon: MeshInstance3D = MeshInstance3D.new()
		ribbon.set_script(script)
		ribbon.name = str(em.name)
		ribbon.set("life_span", float(em.life_span))
		ribbon.set("emission_rate", float(em.emission_rate))
		ribbon.set("rows", maxi(1, int(em.rows)))
		ribbon.set("columns", maxi(1, int(em.columns)))
		ribbon.set("tint", Color(em.color[0], em.color[1], em.color[2], float(em.layer_alpha)))
		ribbon.material_override = _material(em, ImageTexture.create_from_image(image))
		ribbon.set_meta("import_ribbon", true)
		scene.add_child(ribbon)
		ribbon.owner = scene
		_tracks(players[0] as AnimationPlayer, ribbon, em)
		result.ribbons += 1
		result.diagnostics.append({"code": "ribbon_sampling_approximation", "severity": "info", "emitter": em.name, "message": "30 Hz endpoint tracks; world-space history freezes on pause and resets on loop, clip change or seek > 0.25s. No synthetic points or extra fade."})
	return result

static func _tracks(player: AnimationPlayer, ribbon: MeshInstance3D, em: Dictionary) -> void:
	var root: Node = player.get_node(player.root_node)
	var path: String = str(root.get_path_to(ribbon))
	for item: Dictionary in em.clips:
		if not player.has_animation(str(item.name)):
			continue
		var animation: Animation = player.get_animation(str(item.name))
		for field: String in ["below", "above", "emitting", "alpha", "slot", "time", "clip"]:
			var property: String = {"alpha": "ribbon_alpha", "time": "clock"}.get(field, field)
			var track: int = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(track, NodePath(path + ":" + property))
			animation.track_set_interpolation_loop_wrap(track, false)
			if field in ["emitting", "slot", "clip"]:
				animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
				animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
			for key: Dictionary in item.keys:
				var value: Variant = item.name if field == "clip" else key[field]
				if field in ["below", "above"]:
					value = Vector3(value[0], value[1], value[2])
				animation.track_insert_key(track, minf(float(key.time), animation.length), value)

static func _material(em: Dictionary, texture: Texture2D) -> ShaderMaterial:
	var shader: Shader = Shader.new()
	var blend: String = "blend_mix" if int(em.filter_mode) == 2 else "blend_add"
	shader.code = """shader_type spatial;
render_mode unshaded, %s, cull_disabled, depth_draw_never;
uniform sampler2D diffuse_tex : source_color, filter_linear, repeat_disable;
uniform bool color_add = false;
void fragment() {
 vec4 texel = texture(diffuse_tex, UV) * COLOR;
 if (texel.a < 0.001) discard;
 ALBEDO = color_add ? texel.rgb * texel.rgb : texel.rgb;
 ALPHA = color_add ? 1.0 : texel.a;
}
""" % blend
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.resource_local_to_scene = true
	material.set_shader_parameter("diffuse_tex", texture)
	material.set_shader_parameter("color_add", int(em.filter_mode) == 3)
	return material
