shader_type spatial;
// depth_test_disabled：悬崖 mesh 会盖住岸边共面/贴边的浪；官方 PE/Add 泡沫也不靠深度遮挡
render_mode cull_disabled, unshaded, blend_add, depth_draw_never, depth_test_disabled, fog_disabled;

/// ShorelineWave：FilterMode=4（Add Alpha）+ 层 Alpha 脉冲（Stand 序列约 2.3s）。

uniform sampler2D wave_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_boost = 1.35;
uniform float pulse_seconds = 2.3;

void fragment() {
	vec4 tex = texture(wave_albedo, UV);
	// 对齐 MDX 层 Alpha：0 → ~0.8 → ~0.67 → 0
	float t = fract(TIME / max(pulse_seconds, 0.001));
	float pulse;
	if (t < 0.26) {
		pulse = mix(0.0, 0.81, t / 0.26);
	} else if (t < 0.65) {
		pulse = mix(0.81, 0.67, (t - 0.26) / 0.39);
	} else {
		pulse = mix(0.67, 0.0, (t - 0.65) / 0.35);
	}
	vec3 rgb = tex.rgb * tex.a * pulse * alpha_boost;
	ALBEDO = rgb;
	ALPHA = clamp(tex.a * pulse * alpha_boost, 0.0, 1.0);
}
