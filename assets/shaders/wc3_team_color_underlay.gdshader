shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

// WC3：Layer0=TeamColor（不透明）+ Layer1=漫反射 Blend。
// 漫反射 alpha 处透出队伍色；整体按不透明写深度（避免建筑透视）。

uniform sampler2D diffuse_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D team_color_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 team_color_fallback : source_color = vec4(0.12, 0.27, 0.71, 1.0);
uniform bool use_team_texture = true;

void fragment() {
	vec4 diff = texture(diffuse_tex, UV);
	vec3 team = use_team_texture
		? texture(team_color_tex, UV).rgb
		: team_color_fallback.rgb;
	ALBEDO = mix(team, diff.rgb, diff.a);
	ALPHA = 1.0;
}
