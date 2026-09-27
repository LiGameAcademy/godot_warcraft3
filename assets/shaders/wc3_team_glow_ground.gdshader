shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Ground hero aura: depth testing remains enabled so terrain/buildings can occlude it.
uniform sampler2D glow_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 team_color : source_color = vec4(1.0, 0.1, 0.1, 1.0);
uniform float intensity : hint_range(0.1, 8.0) = 2.4;

void fragment() {
	vec4 tex = texture(glow_tex, UV);
	ALBEDO = team_color.rgb * tex.rgb * intensity;
	ALPHA = tex.a;
}
