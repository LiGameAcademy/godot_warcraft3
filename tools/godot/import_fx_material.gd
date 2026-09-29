extends RefCounted
## MDX mesh Additive = SRC_COLOR/ONE; AddAlpha = SRC_ALPHA/ONE.
## These are deliberately separate from ParticleEmitter2's filter enum.
static func build(original: StandardMaterial3D, layer: Dictionary, team_glow: bool) -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform sampler2D diffuse_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform bool team_glow = false;
uniform vec4 team_color_fallback : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform bool recolor = false;
uniform float layer_alpha = 1.0;
uniform float geoset_alpha = 1.0;
uniform vec3 geoset_color = vec3(1.0);
uniform bool color_add = false;
void fragment() {
 vec4 texel = texture(diffuse_tex, UV);
 vec3 rgb = texel.rgb;
 if (team_glow && recolor) rgb = max(max(rgb.r, rgb.g), rgb.b) * team_color_fallback.rgb;
 rgb *= geoset_color;
 float alpha = layer_alpha * geoset_alpha;
 if (alpha < 0.001) discard;
 ALBEDO = color_add ? rgb * rgb : rgb;
 ALPHA = color_add ? 1.0 : texel.a * alpha;
}
"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.resource_local_to_scene = true
	material.set_shader_parameter("diffuse_tex", original.albedo_texture)
	material.set_shader_parameter("color_add", int(layer.FilterMode) == 3)
	material.set_shader_parameter("layer_alpha", 1.0 if layer.get("Alpha") is Dictionary else float(layer.get("Alpha", 1.0)))
	material.set_shader_parameter("team_glow", team_glow)
	material.set_meta("import_fx_material", true)
	if team_glow:
		material.set_meta("import_team_glow", true)
	return material
