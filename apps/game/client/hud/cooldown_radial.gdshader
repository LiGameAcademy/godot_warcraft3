shader_type canvas_item;
render_mode blend_mix, unshaded;

## 命令格技能冷却扇形遮罩（Present）。
## progress = 剩余比例（1=刚进 CD，0=可放）；自 12 点顺时针扫过的暗区。

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 overlay_color : source_color = vec4(0.02, 0.02, 0.06, 0.78);
uniform float edge_soft : hint_range(0.0, 0.05) = 0.014;

void fragment() {
	if (progress <= 0.001) {
		COLOR = vec4(0.0);
		return;
	}
	vec2 uv = UV - vec2(0.5);
	// Godot atan(y, x)；0 在正上，顺时针增大到 1
	float ang = atan(uv.x, -uv.y);
	float t = ang / TAU + 0.5;
	float p = clamp(progress, 0.0, 1.0);
	float cover = 1.0 - smoothstep(p - edge_soft, p + edge_soft, t);
	// 不乘入站 COLOR（ColorRect 顶点色），避免白底把扇形冲成白框
	COLOR = vec4(overlay_color.rgb, overlay_color.a * cover);
}
