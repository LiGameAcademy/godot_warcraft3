shader_type spatial;
// 集结旗反馈层：与 team_color_underlay 同视觉，但关掉深度测试，避免被地形/建筑挡住。
render_mode blend_mix, depth_draw_opaque, depth_test_disabled, cull_disabled, diffuse_burley, specular_disabled;

uniform sampler2D diffuse_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D team_color_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D glow_mask_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 team_color_fallback : source_color = vec4(0.12, 0.27, 0.71, 1.0);
uniform vec4 team_glow : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform bool use_team_texture = true;
uniform float use_glow : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 diff = texture(diffuse_tex, UV);
	vec3 team = use_team_texture
		? texture(team_color_tex, UV).rgb
		: team_color_fallback.rgb;
	ALBEDO = mix(team, diff.rgb, diff.a);
	ALPHA = 1.0;

	EMISSION = vec3(0.0);
	if (use_glow > 0.5 && team_glow.a > 0.0) {
		float glow_mask = texture(glow_mask_tex, UV).r;
		EMISSION = team_glow.rgb * glow_mask * team_glow.a;
	}
}
