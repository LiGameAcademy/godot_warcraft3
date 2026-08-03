shader_type spatial;
render_mode cull_disabled, unshaded, fog_disabled;

/// WC3 悬崖：与官方 viewer 一样直接输出贴图色（不做方向光），
/// 避免顶缘法线朝上被照得比地面雪更亮。
/// 调试栅格与地面共用 wc3_debug_grid（世界 XZ 投影，立面也会出现竖向栅格线）。

#include "res://assets/shaders/wc3_debug_grid.gdshaderinc"

uniform sampler2D cliff_albedo : source_color, filter_linear_mipmap;
uniform sampler2D height_map : filter_nearest, hint_default_black;
uniform vec2 center_offset;
uniform vec2 map_size;
uniform float world_scale = 0.01;

/// 可选：整体压暗/提亮（1=贴图像素原色）
uniform float albedo_scale : hint_range(0.5, 1.5) = 1.0;

vec2 tp_uv(vec2 tp) {
	return (tp + vec2(0.5)) / map_size;
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 wc3_xy = vec2(world_pos.x, -world_pos.z) / world_scale;
	dbg_wc3_xy = wc3_xy;
	vec2 tp = (wc3_xy - center_offset) / 128.0;
	vec2 tp0 = floor(tp);
	vec2 f = clamp(tp - tp0, vec2(0.0), vec2(1.0));

	float h00 = texture(height_map, tp_uv(tp0)).r;
	float h10 = texture(height_map, tp_uv(tp0 + vec2(1.0, 0.0))).r;
	float h01 = texture(height_map, tp_uv(tp0 + vec2(0.0, 1.0))).r;
	float h11 = texture(height_map, tp_uv(tp0 + vec2(1.0, 1.0))).r;
	float h = mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);

	VERTEX.y += h * 128.0;
}

void fragment() {
	vec3 albedo = texture(cliff_albedo, UV).rgb * albedo_scale;
	ALBEDO = dbg_apply_pathing(dbg_apply_grid(albedo));
}
