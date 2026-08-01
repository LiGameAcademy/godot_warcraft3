class_name MapMinimapUtils
extends RefCounted
## 小地图工具函数：坐标转换 + 视口梯形。纯函数，无状态。

## 黄框投影用等效 FOV（不改真实编辑相机）。手测可调。
const DEFAULT_EFFECTIVE_FOV_DEG := 50.0
## 等效 FOV 启用时默认不再二次收缩；需要再缩可 < 1。
const DEFAULT_FOOTPRINT_SCALE := 1.0


## WC3 世界坐标 → 小地图 UV [0,1]（北朝上，含 heightfield centerOffset）。
static func world_to_minimap_uv(world: Vector3, hf: Wc3Heightfield) -> Vector2:
	# world: Godot (X=WC3.X, Y=WC3.Z, Z=-WC3.Y)
	var wc3_x: float = world.x / Wc3Coords.WORLD_SCALE
	var wc3_y: float = -world.z / Wc3Coords.WORLD_SCALE
	var u: float = (wc3_x - hf.center_offset.x) / (hf.width - 1) / hf.tile_size if hf.width > 1 else 0.0
	var v: float = (wc3_y - hf.center_offset.y) / (hf.height - 1) / hf.tile_size if hf.height > 1 else 0.0
	# v 翻转：图像 y 向下，地图 y 向上
	return Vector2(u, 1.0 - v)


## 小地图 UV → Godot 世界坐标（Y 保持 world_y 或地面高度）。
static func minimap_uv_to_world(uv: Vector2, hf: Wc3Heightfield, world_y: float = 0.0) -> Vector3:
	var ix: float = uv.x * float(maxi(hf.width - 1, 1))
	var iy: float = (1.0 - uv.y) * float(maxi(hf.height - 1, 1))
	var wc3_x: float = hf.center_offset.x + ix * hf.tile_size
	var wc3_y: float = hf.center_offset.y + iy * hf.tile_size
	return Vector3(wc3_x * Wc3Coords.WORLD_SCALE, world_y, -wc3_y * Wc3Coords.WORLD_SCALE)


## 地面纹理 ID → 大致颜色（调试 / 无 Catalog 时 fallback）。
static func ground_tex_to_color(gtex: int) -> Color:
	match gtex:
		0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15:
			return Color(0.28, 0.52, 0.22)
		16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31:
			return Color(0.55, 0.45, 0.30)
		32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47:
			return Color(0.85, 0.88, 0.90)
		48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
			return Color(0.40, 0.38, 0.35)
		_:
			return Color(0.50, 0.50, 0.50)


## 层高 + 标志 → 颜色（旧高度伪彩；实时光栅已改走贴图色，保留备用）。
static func layer_height_to_color(
	lv: int, is_water: bool, _is_ramp: bool, _gtex: int = -1, min_lv: int = 0, max_lv: int = 14
) -> Color:
	if is_water:
		var depth_t: float = clampf(
			float(lv - min_lv) / maxf(float(max_lv - min_lv), 1.0), 0.0, 1.0
		)
		return Color(0.15, 0.35, 0.72).lerp(Color(0.35, 0.55, 0.9), depth_t)
	var height_t: float = clampf(
		float(lv - min_lv) / maxf(float(max_lv - min_lv), 1.0), 0.0, 1.0
	)
	return Color(0.18 + height_t * 0.55, 0.42 + height_t * 0.35, 0.22 + height_t * 0.15)


static func compute_height_range(hf: Wc3Heightfield) -> Vector2i:
	var min_l := 99
	var max_l := 0
	for i in range(hf.layer_heights.size()):
		var lv: int = int(hf.layer_heights[i])
		min_l = mini(min_l, lv)
		max_l = maxi(max_l, lv)
	return Vector2i(min_l, max_l)


## 视锥四角 → 小地图 UV 梯形。
## effective_fov_deg：用较窄 FOV 估黄框（默认 50）；≤0 则用相机真实 FOV。
## footprint_scale：朝观察点再收缩（默认 1=不缩）。
static func compute_camera_minimap_uv_quad(
	cam: Camera3D,
	camera_rig: Node3D,
	hf: Wc3Heightfield,
	footprint_scale: float = DEFAULT_FOOTPRINT_SCALE,
	effective_fov_deg: float = DEFAULT_EFFECTIVE_FOV_DEG,
) -> PackedVector2Array:
	var out := PackedVector2Array()
	if cam == null or hf == null:
		return out
	var look: Vector3 = camera_rig.global_position
	if camera_rig.has_method("get_look_at"):
		look = camera_rig.get_look_at()
	var h_wc3: float = hf.interpolated_height(
		look.x / Wc3Coords.WORLD_SCALE, -look.z / Wc3Coords.WORLD_SCALE
	)
	var plane_y: float = h_wc3 * Wc3Coords.WORLD_SCALE
	var vp: Viewport = cam.get_viewport()
	var sz: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(1280, 720)
	var corners: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(sz.x, 0.0),
		Vector2(sz.x, sz.y),
		Vector2(0.0, sz.y),
	]
	var fov_scale: float = effective_fov_screen_scale(cam.fov, effective_fov_deg)
	var center_scr: Vector2 = sz * 0.5
	for scr in corners:
		var sample_scr: Vector2 = center_scr + (scr - center_scr) * fov_scale
		var hit: Variant = _ray_to_ground(cam, sample_scr, plane_y)
		if hit == null:
			hit = _ray_to_ground(cam, sample_scr, look.y)
		if hit == null:
			out.clear()
			break
		out.append(world_to_minimap_uv(hit as Vector3, hf))
	if out.size() != 4:
		out = PackedVector2Array()
		var rect: Rect2 = _fallback_uv_rect(
			cam, camera_rig, hf, look, sz, effective_fov_deg
		)
		out.append(rect.position)
		out.append(Vector2(rect.end.x, rect.position.y))
		out.append(rect.end)
		out.append(Vector2(rect.position.x, rect.end.y))
	var scale: float = clampf(footprint_scale, 0.15, 1.0)
	if scale < 0.999:
		var center_uv: Vector2 = world_to_minimap_uv(look, hf)
		for i in range(out.size()):
			out[i] = center_uv.lerp(out[i], scale)
	return out


static func compute_camera_minimap_uv_rect(
	cam: Camera3D,
	camera_rig: Node3D,
	hf: Wc3Heightfield,
	footprint_scale: float = DEFAULT_FOOTPRINT_SCALE,
	effective_fov_deg: float = DEFAULT_EFFECTIVE_FOV_DEG,
) -> Rect2:
	var quad := compute_camera_minimap_uv_quad(
		cam, camera_rig, hf, footprint_scale, effective_fov_deg
	)
	if quad.size() < 2:
		return Rect2()
	var min_u := quad[0].x
	var min_v := quad[0].y
	var max_u := quad[0].x
	var max_v := quad[0].y
	for i in range(1, quad.size()):
		min_u = minf(min_u, quad[i].x)
		min_v = minf(min_v, quad[i].y)
		max_u = maxf(max_u, quad[i].x)
		max_v = maxf(max_v, quad[i].y)
	return Rect2(min_u, min_v, max_u - min_u, max_v - min_v)


## tan(eff/2)/tan(cam/2)：把屏幕角点往中心收，等价于较窄 FOV。
static func effective_fov_screen_scale(cam_fov_deg: float, effective_fov_deg: float) -> float:
	if effective_fov_deg <= 0.0:
		return 1.0
	var cam_h: float = maxf(cam_fov_deg, 1.0)
	var eff: float = minf(effective_fov_deg, cam_h)
	var t_cam: float = tan(deg_to_rad(cam_h * 0.5))
	var t_eff: float = tan(deg_to_rad(eff * 0.5))
	if t_cam < 0.0001:
		return 1.0
	return clampf(t_eff / t_cam, 0.15, 1.0)


static func _fallback_uv_rect(
	cam: Camera3D,
	camera_rig: Node3D,
	hf: Wc3Heightfield,
	look: Vector3,
	sz: Vector2,
	effective_fov_deg: float = DEFAULT_EFFECTIVE_FOV_DEG,
) -> Rect2:
	var center_uv: Vector2 = world_to_minimap_uv(look, hf)
	var dist: float = 15.0
	if camera_rig.has_method("get_orbit_distance"):
		dist = float(camera_rig.get_orbit_distance())
	var use_fov: float = cam.fov
	if effective_fov_deg > 0.0:
		use_fov = minf(effective_fov_deg, cam.fov)
	var half_world: float = dist * tan(deg_to_rad(use_fov * 0.5))
	var aspect: float = sz.x / maxf(sz.y, 1.0)
	var tile_g: float = hf.tile_size * Wc3Coords.WORLD_SCALE
	var span_x: float = float(maxi(hf.width - 1, 1)) * tile_g
	var span_y: float = float(maxi(hf.height - 1, 1)) * tile_g
	var hu: float = (half_world * aspect) / maxf(span_x, 0.001)
	var hv: float = half_world / maxf(span_y, 0.001)
	return Rect2(center_uv.x - hu, center_uv.y - hv, hu * 2.0, hv * 2.0)


static func _ray_to_ground(cam: Camera3D, screen: Vector2, plane_y: float) -> Variant:
	var from: Vector3 = cam.project_ray_origin(screen)
	var dir: Vector3 = cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return null
	var t: float = (plane_y - from.y) / dir.y
	if t < 0.05:
		return null
	return from + dir * t
