shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, fog_disabled;

/// HiveWE / mdx-m3-viewer 水体：动画水面贴图 × 顶点深度色。
/// 贴图循环在 shader 内用 TIME 推进（不在 GDScript 里切帧）。

uniform sampler2DArray water_frames : source_color, filter_linear_mipmap, repeat_enable;
uniform int frame_count = 1;
/// Water.slk texRate ≈ 每秒帧数（viewer 每渲染帧 += texRate/60，60fps 下等价于每秒 texRate 帧）
uniform float tex_rate = 15.0;

varying vec4 v_depth_color;

void vertex() {
	v_depth_color = COLOR;
}

void fragment() {
	float frames = max(float(frame_count), 1.0);
	// TIME 是秒 → 直接 * tex_rate；不要再 /60（/60 是「按帧累加」写法）
	float idx = floor(mod(TIME * tex_rate, frames));
	vec4 tex = texture(water_frames, vec3(UV, idx));
	vec4 c = tex * v_depth_color;
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
