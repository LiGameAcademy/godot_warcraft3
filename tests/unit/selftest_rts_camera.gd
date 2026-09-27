extends SceneTree

var checks := 0
var failures := 0

class ControlledCamera extends RtsCamera:
	var pan := Vector2.ZERO
	func _get_pan_input() -> Vector2:
		return pan

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var rig := ControlledCamera.new()
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	pivot.add_child(camera)
	rig.add_child(pivot)
	root.add_child(rig)
	rig.set_process(false)
	check(is_equal_approx(camera.fov, 50.0) and camera.keep_aspect == Camera3D.KEEP_HEIGHT, "explicit vertical trial FOV")
	check(is_equal_approx(rig.get_orbit_distance(), 16.5), "world scale preserves default distance")
	# A held direction starts immediately; release must not drift on the next frame.
	rig.pan = Vector2.RIGHT
	rig._process(1.0 / 60.0)
	check(is_equal_approx(rig.position.x, 0.5), "pan starts at configured speed")
	rig.pan = Vector2.ZERO
	var stopped := rig.position
	rig._process(1.0 / 60.0)
	check(rig.position == stopped, "release stops without residual movement")
	# Finite, real heightfield: a plane rising in X, in Warcraft coordinates.
	var hf := Wc3Heightfield.new()
	hf.width = 16
	hf.height = 16
	hf.center_offset = Vector2(-1024, -1024)
	for y in range(hf.height):
		for x in range(hf.width):
			hf.heights.append(400.0 + (hf.center_offset.x + x * 128.0) * 0.25)
			hf.layer_heights.append(2)
			hf.flags_packed.append(0)
	rig.set_heightfield(hf)
	rig.snap_to(Vector3.ZERO)
	check(is_equal_approx(rig.position.y, 4.0), "snap uses terrain height rather than incoming Y")
	rig.focus_on_position(Vector3(4, -100, 0))
	check(rig.position.is_equal_approx(Vector3(4, 5, 0)), "default focus is immediate and terrain relative")
	check(absf(rig.get_camera().global_position.distance_to(rig.get_look_at()) - 16.5) < 0.001, "terrain follow preserves orbit radius")
	rig.set_boundaries(Vector2(-4, -4), Vector2(4, 4))
	rig.snap_to(Vector3(100, 100, 0))
	check(rig.position.is_equal_approx(Vector3(4, 5, 0)), "snap samples height at clamped destination")
	rig.clear_boundaries()
	rig.snap_to(Vector3(100, 0, 0))
	check(rig.position.y > 6.0 and rig.position.y < 6.3, "outside terrain clamps samples instead of falling to zero")
	# Explicit animated focus updates XZ without writing a stale Y every frame.
	rig.snap_to(Vector3.ZERO)
	rig.focus_on_position(Vector3(4, 0, 0), 1.0)
	rig._focus_tween.pause()
	rig._focus_tween.custom_step(0.5)
	rig._process(0.5)
	check(rig.position.x > 0.0 and rig.position.x < 4.0 and rig.position.y > 4.0, "animated focus follows rising terrain")
	rig._focus_tween.custom_step(0.5)
	rig._process(1.0)
	check(absf(rig.position.y - 5.0) < 0.001, "focus completion retains terrain height")
	rig.focus_on_position(Vector3.ZERO, 1.0)
	rig.pan = Vector2.RIGHT
	rig._process(0.01)
	check(rig._focus_tween == null, "manual panning cancels scripted focus")
	rig.pan = Vector2.ZERO
	# A second wheel tick starts from the current interpolated pose.
	rig._adjust_zoom(1)
	check(is_equal_approx(rig.get_orbit_distance(), 16.5), "zoom does not snap on wheel input")
	rig._zoom_tween.pause()
	rig._zoom_tween.custom_step(0.06)
	var intermediate := rig.get_orbit_distance()
	check(intermediate < 16.5 and intermediate > 16.0, "zoom travels between presets")
	rig._adjust_zoom(1)
	check(is_equal_approx(rig.get_orbit_distance(), intermediate), "repeated wheel input preserves current pose")
	rig._zoom_tween.pause()
	rig._zoom_tween.custom_step(1.0)
	check(is_equal_approx(rig.get_orbit_distance(), 15.0) and is_equal_approx(pivot.rotation.x, deg_to_rad(-42)), "zoom lands on coupled distance and pitch")
	rig.zoom_duration = 0.0
	for i in range(20):
		rig._adjust_zoom(1)
	check(rig.get_zoom_index() == 5 and is_equal_approx(rig.get_orbit_distance(), 11.0), "zoom respects nearest limit")
	for i in range(20):
		rig._adjust_zoom(-1)
	check(rig.get_zoom_index() == 0 and is_equal_approx(rig.get_orbit_distance(), 16.5), "zoom respects farthest limit")
	rig.set_heightfield(null)
	rig.snap_to(Vector3.ZERO)
	var unbound_y := rig.position.y
	rig._process(0.1)
	check(is_equal_approx(rig.position.y, unbound_y), "unbound terrain remains safe")
	rig.free()
	print("selftest_rts_camera: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
