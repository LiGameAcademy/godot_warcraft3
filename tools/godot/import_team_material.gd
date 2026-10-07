extends RefCounted
## Opaque team-color base and alpha-blended top with per-layer lighting/culling.
static func supported(layers: Array, textures: Array) -> bool:
	if layers.size() != 2:
		return false
	var base: Dictionary = layers[0]
	var top: Dictionary = layers[1]
	if base.get("TextureID") is Dictionary or top.get("TextureID") is Dictionary:
		return false
	var index: int = int(base.get("TextureID", -1))
	var top_index: int = int(top.get("TextureID", -1))
	if index < 0 or index >= textures.size() or top_index < 0 or top_index >= textures.size():
		return false
	# Per-axis wrapping requires a separate sampler implementation.
	if int(textures[index].get("Flags", 0)) not in [0, 3] or int(textures[top_index].get("Flags", 0)) not in [0, 3]:
		return false
	return int(textures[index].get("ReplaceableId", 0)) == 1 and int(textures[top_index].get("ReplaceableId", 0)) == 0 and base.get("Alpha", 1) == 1 and int(base.get("FilterMode", 0)) in [0, 1] and int(top.get("FilterMode", 0)) == 2 and (not int(top.get("Shading", 0)) & 16 or int(base.get("Shading", 0)) & 16)

static func compile(original: StandardMaterial3D, layers: Array, textures: Array, texture_base: String) -> ShaderMaterial:
	var entry: Dictionary = textures[int(layers[0].TextureID)]
	if str(entry.get("uri", "")).is_empty() or str(entry.uri).contains("_placeholders/"):
		return null
	var image: Image = Image.load_from_file(texture_base.path_join(str(entry.uri)).simplify_path())
	if image == null or original.albedo_texture == null:
		return null
	# Alpha-tested team layers are equivalent to opaque only with an opaque source.
	if int(layers[0].get("FilterMode", 0)) == 1 and image.detect_alpha() != Image.ALPHA_NONE:
		return null
	image.generate_mipmaps()
	var material: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	var cull: String = "cull_disabled" if int(layers[0].get("Shading", 0)) & 16 else "cull_back"
	# No ALPHA write: the composite is opaque, avoiding transparent sorting holes.
	shader.code = """shader_type spatial;
render_mode depth_draw_opaque, %s;
uniform sampler2D diffuse_tex : source_color, filter_linear_mipmap, %s;
uniform sampler2D team_color_tex : source_color, filter_linear_mipmap, %s;
uniform vec4 team_color_fallback : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform bool use_team_texture = true;
uniform float layer_alpha = 1.0;
void fragment() {
 vec4 diff = texture(diffuse_tex, UV);
 vec3 team = use_team_texture ? texture(team_color_tex, UV).rgb : team_color_fallback.rgb;
 float a = %s ? clamp(diff.a * layer_alpha, 0.0, 1.0) : 0.0;
 vec3 base = team * (1.0 - a);
 vec3 top = diff.rgb * a;
 ALBEDO = %s + %s;
 EMISSION = %s + %s;
 ROUGHNESS = 1.0;
 SPECULAR = 0.0;
}
""" % [cull, _repeat(textures[int(layers[1].TextureID)]), _repeat(entry), "true" if int(layers[1].get("Shading", 0)) & 16 else "FRONT_FACING", _lit(layers[0], "base"), _lit(layers[1], "top"), _unlit(layers[0], "base"), _unlit(layers[1], "top")]
	material.shader = shader
	material.set_shader_parameter("diffuse_tex", original.albedo_texture)
	material.set_shader_parameter("team_color_tex", ImageTexture.create_from_image(image))
	material.set_shader_parameter("layer_alpha", 1.0 if layers[1].get("Alpha", 1) is Dictionary else float(layers[1].get("Alpha", 1)))
	material.set_meta("import_team_underlay", true)
	return material

static func _lit(layer: Dictionary, expression: String) -> String:
	return "vec3(0.0)" if int(layer.get("Shading", 0)) & 1 else expression

static func _unlit(layer: Dictionary, expression: String) -> String:
	return expression if int(layer.get("Shading", 0)) & 1 else "vec3(0.0)"

static func _repeat(texture: Dictionary) -> String:
	return "repeat_enable" if int(texture.get("Flags", 0)) == 3 else "repeat_disable"
