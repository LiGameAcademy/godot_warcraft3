shader_type spatial;
// 单位披风/肩饰 _fm2_rep1 常是单面壳（Priest Geoset_1）。
// 勿写 ALPHA（即便 1.0）：Godot 会整进透明队列 → 与袍体 MASK 深度/排序打架，
// 表现为「侧面能见队色披挂、正面胸口镂空」。复合色已是不透明，走 opaque 管线。
// cull_disabled：MDX 常不标 TwoSided，单面壳正面需可见。
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, fog_disabled;

// WC3 team color + team glow 整合：
// - Layer0=TeamColor（不透明 Unshaded）：player color 垫底
// - Layer1=漫反射 Blend：alpha 处透出队色 → mix(team, diff, a)
// - Layer2=TeamGlow（可选 emissive）
//
// D-2 扩展：加 team_glow uniform + use_glow 开关 + glow_mask sampler。

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
	// 故意不写 ALPHA → 留在 opaque 管线，深度与 G0 MASK 正确交互。

	EMISSION = vec3(0.0);
	if (use_glow > 0.5 && team_glow.a > 0.0) {
		float glow_mask = texture(glow_mask_tex, UV).r;
		EMISSION = team_glow.rgb * glow_mask * team_glow.a;
	}
}
