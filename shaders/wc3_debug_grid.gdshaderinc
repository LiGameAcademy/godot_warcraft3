// 寻路调试线框（RTS 三级，混入地表 ALBEDO）：
//   小=灰  tile/4 （32u）— 4×4 组成中级
//   中=白  tile   （128u）— 4×4 组成大级
//   大=黄  tile*4 （512u）
// 调用方须在 vertex() 内写：dbg_wc3_xy = vec2(world.x, -world.z) / world_scale;

uniform bool dbg_grid_tile = false;
uniform bool dbg_grid_path = false;
uniform bool dbg_grid_fine = false;
uniform float dbg_tile_size = 128.0;
uniform vec2 dbg_center_offset = vec2(0.0);
uniform float dbg_line_px = 1.2;
uniform vec4 dbg_color_tile = vec4(1.0, 0.92, 0.12, 0.98);
uniform vec4 dbg_color_path = vec4(0.95, 0.95, 0.98, 0.78);
uniform vec4 dbg_color_fine = vec4(0.62, 0.62, 0.65, 0.50);

varying vec2 dbg_wc3_xy;

float dbg_line_mask(vec2 map_xy, float cell, float px) {
	vec2 uv = map_xy / cell;
	vec2 fw = fwidth(uv);
	vec2 g = abs(fract(uv - 0.5) - 0.5) / max(fw, vec2(1e-6));
	return 1.0 - smoothstep(0.0, px, min(g.x, g.y));
}

vec3 dbg_apply_grid(vec3 albedo) {
	if (!(dbg_grid_tile || dbg_grid_path || dbg_grid_fine)) {
		return albedo;
	}
	vec2 map_xy = dbg_wc3_xy - dbg_center_offset;
	vec3 out_c = albedo;
	if (dbg_grid_fine) {
		float m = dbg_line_mask(map_xy, dbg_tile_size / 4.0, dbg_line_px);
		out_c = mix(out_c, dbg_color_fine.rgb, m * dbg_color_fine.a);
	}
	if (dbg_grid_path) {
		float m = dbg_line_mask(map_xy, dbg_tile_size, dbg_line_px * 1.15);
		out_c = mix(out_c, dbg_color_path.rgb, m * dbg_color_path.a);
	}
	if (dbg_grid_tile) {
		float m = dbg_line_mask(map_xy, dbg_tile_size * 4.0, dbg_line_px * 1.45);
		out_c = mix(out_c, dbg_color_tile.rgb, m * dbg_color_tile.a);
	}
	return out_c;
}
