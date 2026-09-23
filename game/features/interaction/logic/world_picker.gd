class_name WorldPicker
extends RefCounted
var camera: RtsCamera
var navigation: NavigationModule
var _heightfield: Wc3Heightfield:
	get:
		return navigation.heightfield if is_instance_valid(navigation) else null

func configure(value: RtsCamera, nav: NavigationModule) -> void:
	camera = value
	navigation = nav

func ground_at_screen(screen_pos: Vector2) -> Vector3:
	if camera == null:
		return Vector3.INF
	var cam := camera.get_camera()
	if cam == null:
		return Vector3.INF
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if dir.length_squared() < 1e-8:
		return Vector3.INF
	dir = dir.normalized()
	if _heightfield != null and _heightfield.is_valid():
		var hit := ray_heightfield(from, dir)
		if hit != Vector3.INF:
			return hit
	# 回退：物理射线（排除无 heightfield 时）
	var space := cam.get_world_3d().direct_space_state
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 20000.0)
		q.collision_mask = 0xFFFFFFFF
		var hit2 := space.intersect_ray(q)
		if not hit2.is_empty():
			return hit2.get("position", Vector3.INF)
	if absf(dir.y) < 1e-5:
		return Vector3.INF
	var t := -from.y / dir.y
	if t < 0.0:
		return Vector3.INF
	return from + dir * t


func ray_heightfield(from: Vector3, dir: Vector3) -> Vector3:
	var step := 0.35
	var max_dist := 400.0
	var prev_above := true
	var d := step
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	while d <= max_dist:
		var p: Vector3 = from + dir * d
		var wx := p.x * inv
		var wy := -p.z * inv
		var gz := _heightfield.interpolated_height(wx, wy)
		var ground := Wc3Coords.wc3_xy_to_godot(wx, wy, gz)
		var above := p.y >= ground.y
		if prev_above and not above:
			# 二分细化交点，减少步进粒度带来的落点偏差。
			var lo := d - step
			var hi := d
			for _i in range(6):
				var mid := (lo + hi) * 0.5
				var pm: Vector3 = from + dir * mid
				var w2x := pm.x * inv
				var w2y := -pm.z * inv
				var gz2 := _heightfield.interpolated_height(w2x, w2y)
				var g2 := Wc3Coords.wc3_xy_to_godot(w2x, w2y, gz2)
				if pm.y >= g2.y:
					lo = mid
				else:
					hi = mid
			var final_d := (lo + hi) * 0.5
			var pf: Vector3 = from + dir * final_d
			var wfx := pf.x * inv
			var wfy := -pf.z * inv
			var gzf := _heightfield.interpolated_height(wfx, wfy)
			return Wc3Coords.wc3_xy_to_godot(wfx, wfy, gzf)
		prev_above = above
		d += step
	return Vector3.INF
