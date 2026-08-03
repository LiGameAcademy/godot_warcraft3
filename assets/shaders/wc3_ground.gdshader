shader_type spatial;
render_mode cull_back, unshaded, fog_disabled;

/// WC3 地表过渡贴图（与悬崖同为 unshaded，避免方向光把两者亮度拉开）。
/// CUSTOM0 = 四层 tileset 索引（0-based，-1=无）；CUSTOM1 = 对应图集编号（fill 或 bitmask 0..31）。
/// 图集为统一 512×256（8×4 格）；256×256 素材垫在左半。

#include "res://assets/shaders/wc3_debug_grid.gdshaderinc"

uniform sampler2DArray tilesets : source_color, filter_linear, repeat_disable;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;
uniform float albedo_scale : hint_range(0.5, 1.5) = 1.0;
uniform float world_scale = 0.01;

varying flat vec4 v_tex;
varying flat vec4 v_var;
varying vec2 v_local;

vec2 get_cell(float variation) {
	if (variation < 16.0) {
		return vec2(mod(variation, 4.0), floor(variation / 4.0));
	}
	float v = variation - 16.0;
	return vec2(4.0 + mod(v, 4.0), floor(v / 4.0));
}

vec2 atlas_uv(vec2 local_pos, float variation) {
	vec2 cell = get_cell(variation);
	vec2 cell_size = vec2(0.125, 0.25);
	vec2 uv = vec2(local_pos.x, 1.0 - local_pos.y);
	vec2 pixel = vec2(1.0 / 512.0, 1.0 / 256.0);
	vec2 min_uv = cell * cell_size + pixel;
	vec2 max_uv = (cell + vec2(1.0)) * cell_size - pixel;
	return clamp((cell + uv) * cell_size, min_uv, max_uv);
}

void vertex() {
	v_tex = CUSTOM0;
	v_var = CUSTOM1;
	v_local = UV;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dbg_wc3_xy = vec2(world_pos.x, -world_pos.z) / world_scale;
}

vec4 sample_layer(float layer, float variation, vec2 local_pos) {
	if (layer < -0.5) {
		return vec4(0.0);
	}
	vec2 uv = atlas_uv(local_pos, variation);
	return texture(tilesets, vec3(uv, layer));
}

void fragment() {
	vec4 color = sample_layer(v_tex.x, v_var.x, v_local);

	vec4 o1 = sample_layer(v_tex.y, v_var.y, v_local);
	color = mix(color, o1, o1.a);

	vec4 o2 = sample_layer(v_tex.z, v_var.z, v_local);
	color = mix(color, o2, o2.a);

	vec4 o3 = sample_layer(v_tex.w, v_var.w, v_local);
	color = mix(color, o3, o3.a);

	ALBEDO = dbg_apply_pathing(dbg_apply_grid(color.rgb * albedo_scale));
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}
