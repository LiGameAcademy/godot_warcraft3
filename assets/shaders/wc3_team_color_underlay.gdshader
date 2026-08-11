shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

// WC3 team color + team glow 整合：
// - Layer0=TeamColor（不透明）：被 player color 替换（diffuse_tex alpha 处透出 team_color）
// - Layer2=TeamGlow（加色 emissive）：player color 叠加发光（glow_mask 控权重）
// 整体按不透明写深度（避免建筑透视）。
//
// D-2 扩展：加 team_glow uniform + use_glow 开关 + glow_mask sampler。
//   D-3 export_model_scenes 在 kind=teamcolor/glow 的 mesh 上调 set_shader_parameter。

uniform sampler2D diffuse_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D team_color_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D glow_mask_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 team_color_fallback : source_color = vec4(0.12, 0.27, 0.71, 1.0);
uniform vec4 team_glow : source_color = vec4(0.0, 0.0, 0.0, 0.0);  // 0..1 加色，0=关闭
uniform bool use_team_texture = true;
uniform float use_glow : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 diff = texture(diffuse_tex, UV);
	vec3 team = use_team_texture
		? texture(team_color_tex, UV).rgb
		: team_color_fallback.rgb;
	ALBEDO = mix(team, diff.rgb, diff.a);
	ALPHA = 1.0;

	// Team glow：emissive 加色（不走 diffuse，alpha 用 glow_mask R 通道）
	EMISSION = vec3(0.0);
	if (use_glow > 0.5 && team_glow.a > 0.0) {
		float glow_mask = texture(glow_mask_tex, UV).r;
		EMISSION = team_glow.rgb * glow_mask * team_glow.a;
	}
}
