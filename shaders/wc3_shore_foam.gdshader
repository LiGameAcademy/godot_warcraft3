shader_type spatial;
// Shoreline PE2 近似：XYQuad + Additive；保留深度测试（防透视）。
render_mode cull_disabled, unshaded, blend_add, depth_draw_never, fog_disabled;

uniform sampler2D foam_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform float life_span = 4.5;
uniform float speed_mps = 0.30;
uniform vec3 scale_mps = vec3(0.30, 0.80, 0.70);
uniform float alpha_mul = 0.82;

varying float v_alpha;

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float speed_mul = max(INSTANCE_CUSTOM.y, 0.05);
	float scale_mul = max(INSTANCE_CUSTOM.z, 0.05);

	float t = fract(TIME / max(life_span, 0.001) + phase);
	float age = t * life_span;
	// 官方 Time=0.5：前半 30→80，后半 80→70；Alpha 0→1→0
	float sc;
	float a;
	if (t < 0.5) {
		float f = t * 2.0;
		sc = mix(scale_mps.x, scale_mps.y, f);
		a = mix(0.0, 1.0, f);
	} else {
		float f = (t - 0.5) * 2.0;
		sc = mix(scale_mps.y, scale_mps.z, f);
		a = mix(1.0, 0.0, f);
	}
	sc *= scale_mul;
	v_alpha = a * alpha_mul;

	VERTEX.x *= sc;
	VERTEX.z *= sc;
	VERTEX.z += speed_mps * speed_mul * age;
	VERTEX.y += 0.025;
}

void fragment() {
	vec4 tex = texture(foam_albedo, UV);
	float a = tex.a * v_alpha;
	ALBEDO = tex.rgb * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
