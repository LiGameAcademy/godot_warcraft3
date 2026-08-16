// 寻路调试线框（RTS 三级，混入地表 ALBEDO）：
//   小=灰  tile/4 （32u）— 4×4 组成中级
//   中=白  tile   （128u）— 4×4 组成大级
//   大=黄  tile*4 （512u）
// 调用方须在 vertex() 内写：dbg_wc3_xy = vec2(world.x, -world.z) / world_scale;
//
// View→路径-地面：在最小寻路格上叠色（红不可走 / 蓝不可建 / 品红两者）。

uniform bool dbg_grid_tile = false;
uniform bool dbg_grid_path = false;
uniform bool dbg_grid_fine = false;
uniform float dbg_tile_size = 128.0;
uniform vec2 dbg_center_offset = vec2(0.0);
uniform float dbg_line_px = 1.2;
uniform vec4 dbg_color_tile = vec4(1.0, 0.92, 0.12, 0.98);
uniform vec4 dbg_color_path = vec4(0.95, 0.95, 0.98, 0.78);
uniform vec4 dbg_color_fine = vec4(0.62, 0.62, 0.65, 0.50);

uniform bool pathing_ground = false;
uniform sampler2D pathing_map_tex : source_color, filter_nearest, repeat_disable;
uniform vec2 pathing_origin = vec2(0.0);
uniform vec2 pathing_size_cells = vec2(1.0);
uniform float pathing_cell = 32.0;
uniform float pathing_alpha = 0.55;

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

vec3 dbg_apply_pathing(vec3 albedo) {
	if (!pathing_ground) {
		return albedo;
	}
	if (pathing_size_cells.x < 0.5 || pathing_size_cells.y < 0.5 || pathing_cell < 1.0) {
		return albedo;
	}
	vec2 local = dbg_wc3_xy - pathing_origin;
	vec2 cell = floor(local / pathing_cell);
	if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= pathing_size_cells.x || cell.y >= pathing_size_cells.y) {
		return albedo;
	}
	// 贴图 y=0 在顶；写入时已按 pathing 行翻转
	vec2 uv = (cell + vec2(0.5)) / pathing_size_cells;
	uv.y = 1.0 - uv.y;
	vec4 tint = texture(pathing_map_tex, uv);
	if (tint.a < 0.01) {
		return albedo;
	}
	return mix(albedo, tint.rgb, tint.a * pathing_alpha);
}
