shader_type spatial;
// 朝向由 MeshInstance3D.transform 决定（局部 +Z = 朝岸）。
// 顶点弧度 + 横向摇摆 + 每实例相位/周期错开。
render_mode cull_disabled, unshaded, blend_add, depth_draw_never, depth_test_disabled, fog_disabled;

uniform sampler2D foam_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform float travel_meters = 1.8;
uniform float cycle_seconds = 4.5;
uniform float alpha_boost = 1.35;
uniform float quad_meters = 3.2;

instance uniform float phase = 0.0;
instance uniform float size_mul = 1.0;
instance uniform float travel_mul = 1.0;
instance uniform float cycle_mul = 1.0;
instance uniform float arc_mul = 0.7;
instance uniform float sway_mul = 1.0;

varying float v_pulse;

void vertex() {
	float cycle = max(cycle_seconds * max(cycle_mul, 0.35), 0.5);
	float t = fract(TIME / cycle + phase);
	float half_w = max(quad_meters * 0.5, 0.01);
	float nx = clamp(VERTEX.x / half_w, -1.0, 1.0); // 沿岸 -1..1
	float ny = clamp(VERTEX.y / half_w, -1.0, 1.0);

	// 新月弧：中间朝岸（+Z）鼓起，两端收；略抬高两侧形成弯弧轮廓
	float crescent = (1.0 - nx * nx);
	float arc = arc_mul * half_w * 0.55;
	VERTEX.z += crescent * arc;
	VERTEX.y += (nx * nx) * arc * 0.22; // 两端上扬一点，打破平直线

	// 生长缩放：沿岸更宽、朝岸稍扁
	float grow;
	if (t < 0.4) {
		grow = mix(0.42, 1.0, t / 0.4);
	} else {
		grow = mix(1.0, 0.82, (t - 0.4) / 0.6);
	}
	float sm = max(size_mul, 0.2) * grow;
	VERTEX.x *= sm * 1.15;
	VERTEX.y *= sm * 0.72;

	// 朝岸漂移 + 横向正弦摆动（每实例相位不同 → 彼此岔开）
	float travel = t * travel_meters * max(travel_mul, 0.2);
	float sway = sin((t + phase) * TAU * 1.15) * half_w * 0.18 * max(sway_mul, 0.0);
	VERTEX.x += sway;
	VERTEX.z += travel;
	// 轻微起伏，增加层次感
	VERTEX.y += sin((t * 2.0 + phase) * TAU) * half_w * 0.06 * max(sway_mul, 0.0);

	if (t < 0.1) {
		v_pulse = mix(0.0, 1.0, t / 0.1);
	} else if (t < 0.5) {
		v_pulse = 1.0;
	} else {
		v_pulse = mix(1.0, 0.0, (t - 0.5) / 0.5);
	}
	// 边缘稍淡，减少「铁丝边」感
	v_pulse *= mix(0.55, 1.0, crescent);
	v_pulse *= mix(0.75, 1.0, 1.0 - abs(ny) * 0.5);
}

void fragment() {
	vec4 tex = texture(foam_albedo, UV);
	float a = tex.a * v_pulse * alpha_boost;
	ALBEDO = tex.rgb * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
