shader_type spatial;
render_mode blend_add, depth_draw_never, depth_test_disabled, cull_disabled, unshaded, fog_disabled;

// WC3 Team Glow（ReplaceableId=2）
// 软边在 TeamGlowXX.png 的 RGB（边缘近黑）；Additive 下黑=不加光。
// 脚底：贴地网格；杖尖：use_billboard + 更高 intensity（见 MapModelCache）。

uniform sampler2D glow_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 team_color : source_color = vec4(1.0, 0.1, 0.1, 1.0);
uniform float intensity : hint_range(0.5, 8.0) = 2.4;
uniform bool use_billboard = false;

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
	vec4 tex = texture(glow_tex, UV);
	ALBEDO = team_color.rgb * tex.rgb * intensity;
	ALPHA = 1.0;
}
