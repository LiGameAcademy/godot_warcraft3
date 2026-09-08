shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// 现代飞弹光核：程序径向 soft-orb（朝相机），替代 WC3 Additive 少面糊球。
// 层：presentation / assets/shaders

uniform vec4 core_color : source_color = vec4(1.0, 0.82, 0.35, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.28, 0.04, 1.0);
uniform float intensity : hint_range(0.4, 8.0) = 2.4;
uniform float softness : hint_range(1.0, 6.0) = 2.6;
uniform float pulse_amp : hint_range(0.0, 0.5) = 0.1;
uniform float pulse_hz : hint_range(0.0, 20.0) = 5.5;
uniform bool use_billboard = true;

void vertex() {
	if (use_billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz), 0.0),
			vec4(INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz), 0.0),
			vec4(INV_VIEW_MATRIX[2].xyz * length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(MODEL_MATRIX[3].xyz, 1.0)
		);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float pulse = 1.0 + pulse_amp * sin(TIME * pulse_hz * TAU);
	float core = pow(clamp(1.0 - r, 0.0, 1.0), softness) * pulse;
	float rim = pow(clamp(1.0 - r, 0.0, 1.0), softness * 0.42) * 0.65;
	float w = clamp(core + rim, 0.0, 1.0);
	vec3 col = mix(rim_color.rgb, core_color.rgb, clamp(core * 1.4, 0.0, 1.0));
	ALBEDO = col * w * intensity;
	ALPHA = w;
}
