shader_type spatial;
// 对齐 HiveWE ParticleEmitter2：
//   frag = tex * vertex_color
//   Additive = glBlendFunc(SRC_ALPHA, ONE) ≈ premult + blend_add
// 形状只信 tex.a（勿用 max(a,rgb)，透明像素 RGB 常非零）。
render_mode cull_disabled, unshaded, blend_add, depth_draw_never, fog_disabled;

uniform sampler2D foam_albedo : source_color, filter_linear, repeat_disable;
uniform float life_span = 4.5;
uniform float speed_mps = 0.30;
uniform vec3 scale_mps = vec3(0.30, 0.80, 0.70);
/// MDX Alpha 段 /255：start, middle, end（Shoreline 主 PE2 多为 0,1,0）
uniform vec3 alpha_seg = vec3(0.0, 1.0, 0.0);
uniform float time_middle = 0.5;
/// 1=保留贴图色（原作偏青）；0=按亮度抽成白沫
uniform float keep_tint = 0.35;

varying float v_alpha;
varying float v_life_t;

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float speed_mul = INSTANCE_CUSTOM.y > 0.01 ? INSTANCE_CUSTOM.y : 1.0;
	float scale_mul = INSTANCE_CUSTOM.z > 0.01 ? INSTANCE_CUSTOM.z : 1.0;

	float t = fract(TIME / max(life_span, 0.001) + phase);
	float age = t * life_span;
	v_life_t = t;

	float sc;
	float a;
	if (t < time_middle) {
		float f = t / max(time_middle, 0.001);
		sc = mix(scale_mps.x, scale_mps.y, f);
		a = mix(alpha_seg.x, alpha_seg.y, f);
	} else {
		float f = (t - time_middle) / max(1.0 - time_middle, 0.001);
		sc = mix(scale_mps.y, scale_mps.z, f);
		a = mix(alpha_seg.y, alpha_seg.z, f);
	}
	sc *= scale_mul;
	v_alpha = a;

	VERTEX.x *= sc;
	VERTEX.z *= sc;
	VERTEX.z += speed_mps * speed_mul * age;
	VERTEX.y += 0.04;
}

void fragment() {
	vec4 tex = texture(foam_albedo, UV);
	float mask = tex.a;
	if (mask * v_alpha < 0.004) {
		discard;
	}
	float lum = max(tex.r, max(tex.g, tex.b));
	vec3 rgb = mix(vec3(lum), tex.rgb, keep_tint);
	// HiveWE Additive：src.rgb * src.a + dst  → 预乘后 blend_add(ONE,ONE)
	float a = mask * v_alpha;
	ALBEDO = rgb * a;
	ALPHA = 1.0;
}
