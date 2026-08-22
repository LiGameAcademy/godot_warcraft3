extends Node3D

## Present 弹道壳：与 Logic 同速制导追目标；不改生命。

const TRACER_RADIUS := 0.06
const TRACER_COLOR := Color(1.0, 0.85, 0.35, 1.0)
const IMPACT_LIFETIME := 1.1
const IMPACT_SCALE_BOOST := 2.75
const MISSILE_SCALE := 1.35
## 与 ProjectileService.HIT_RADIUS_WC3 对齐（经 WORLD_SCALE）
const HIT_RADIUS_GODOT := 32.0 * Wc3Coords.WORLD_SCALE

var _pos: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _speed_godot: float = 9.0
var _max_life: float = 6.0
var _elapsed: float = 0.0
var _show_tracer: bool = true
var _impact_art: String = ""
var _missile_art: String = ""
var _arc: float = 0.0
var _path_u: float = 0.0 ## 0→1 近似进度，用于弧高
var _cache: MapModelCache = null
var _target: Node3D = null
var _impact_z_wc3: float = 60.0
var _mi: MeshInstance3D = null
var _missile_root: Node3D = null
var _impact_done: bool = false
var _finished: bool = false


func play(
	from_wc3: Vector3,
	to_wc3: Vector3,
	duration: float,
	show_tracer: bool = true,
	impact_art: String = "",
	cache: MapModelCache = null,
	target: Node3D = null,
	missile_art: String = "",
	arc: float = 0.0,
	speed_wc3: float = 900.0
) -> void:
	_pos = Wc3Coords.wc3_to_godot(from_wc3)
	_to = Wc3Coords.wc3_to_godot(to_wc3)
	_speed_godot = maxf(speed_wc3, 1.0) * Wc3Coords.WORLD_SCALE
	_max_life = maxf(duration * 3.0, 2.0)
	_max_life = minf(_max_life, 6.0)
	_elapsed = 0.0
	_path_u = 0.0
	_show_tracer = show_tracer
	_impact_art = impact_art.strip_edges()
	_missile_art = missile_art.strip_edges()
	_arc = clampf(arc, 0.0, 1.0)
	_cache = cache
	_target = target
	_impact_z_wc3 = to_wc3.z
	_impact_done = false
	_finished = false
	global_position = _apply_arc(_pos, 0.0)
	if _show_tracer:
		if not _missile_art.is_empty():
			_ensure_missile_model()
		else:
			_ensure_tracer_sphere()
		_face_dir(_to - _pos)
	set_process(true)


func _ensure_tracer_sphere() -> void:
	if _mi != null:
		return
	_mi = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = TRACER_RADIUS
	mesh.height = TRACER_RADIUS * 2.0
	_mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = TRACER_COLOR
	mat.emission_enabled = true
	mat.emission = TRACER_COLOR
	mat.emission_energy_multiplier = 1.6
	_mi.material_override = mat
	add_child(_mi)


func _ensure_missile_model() -> void:
	if _missile_root != null:
		return
	var art_path := RuntimeAssets.converted_path(_missile_art)
	var inst: Node3D = null
	if _cache != null:
		inst = _cache.instance_glb(art_path)
	if inst == null and ResourceLoader.exists(art_path):
		var packed := load(art_path)
		if packed is PackedScene:
			inst = (packed as PackedScene).instantiate() as Node3D
	if inst == null:
		var scn := art_path.get_basename() + ".scn"
		if ResourceLoader.exists(scn):
			var packed2 := load(scn)
			if packed2 is PackedScene:
				inst = (packed2 as PackedScene).instantiate() as Node3D
	if inst == null:
		_ensure_tracer_sphere()
		return
	_missile_root = Node3D.new()
	_missile_root.name = "MissileModel"
	_missile_root.scale = Vector3.ONE * MISSILE_SCALE
	add_child(_missile_root)
	_missile_root.add_child(inst)
	Wc3Pe2Particles.attach_to(inst, art_path)
	Wc3Pe2Particles.apply_sequence(inst, "Stand")
	_restart_particles(inst)
	var ap := AnimPlayback.find_animation_player(inst)
	if ap != null:
		var stand := AnimPlayback.resolve(inst, "Stand", ap)
		if stand.is_empty():
			stand = AnimPlayback.resolve(inst, "Birth", ap)
		if not stand.is_empty():
			AnimPlayback.play(inst, stand, 0.0, _cache, 0, ap)


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	_refresh_aim()
	var prev := global_position
	var dist := _pos.distance_to(_to)
	var step := _speed_godot * delta
	if dist <= HIT_RADIUS_GODOT or dist <= step or _elapsed >= _max_life:
		_pos = _to
		global_position = _apply_arc(_pos, 1.0)
		_finish()
		return
	# 进度：本帧移动占「当前剩余+已走」的近似
	_path_u = clampf(_path_u + step / maxf(dist + step, 0.001) * (1.0 - _path_u), 0.0, 0.99)
	_pos = _pos.move_toward(_to, step)
	global_position = _apply_arc(_pos, _path_u)
	if _show_tracer:
		_face_dir(global_position - prev)


func _apply_arc(flat: Vector3, u: float) -> Vector3:
	if _arc <= 0.001:
		return flat
	var out := flat
	var horiz := Vector2(flat.x - _to.x, flat.z - _to.z).length()
	var lift := _arc * maxf(horiz, 0.5) * 0.35
	out.y += lift * 4.0 * u * (1.0 - u)
	return out


func _refresh_aim() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var xy := Wc3Coords.godot_to_wc3_xy(_target.global_position)
	_to = Wc3Coords.wc3_to_godot(Vector3(xy.x, xy.y, _impact_z_wc3))


func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_process(false)
	_spawn_impact()
	queue_free()


func _spawn_impact() -> void:
	if _impact_done or _impact_art.is_empty():
		return
	_impact_done = true
	_refresh_aim()
	var host := get_parent()
	if host == null:
		return
	var art_path := RuntimeAssets.converted_path(_impact_art)
	var inst: Node3D = null
	if _cache != null:
		inst = _cache.instance_glb(art_path)
	if inst == null and ResourceLoader.exists(art_path):
		var packed := load(art_path)
		if packed is PackedScene:
			inst = (packed as PackedScene).instantiate() as Node3D
	if inst == null:
		var scn := art_path.get_basename() + ".scn"
		if ResourceLoader.exists(scn):
			var packed2 := load(scn)
			if packed2 is PackedScene:
				inst = (packed2 as PackedScene).instantiate() as Node3D
	if inst == null:
		_spawn_fallback_flash(host, _to)
		return
	var fx := Node3D.new()
	fx.name = "CombatImpactFx"
	host.add_child(fx)
	fx.global_position = _to
	fx.scale = Vector3.ONE * IMPACT_SCALE_BOOST
	fx.add_child(inst)
	Wc3Pe2Particles.attach_to(inst, art_path)
	Wc3Pe2Particles.apply_sequence(inst, "Birth")
	_restart_particles(inst)
	var ap := AnimPlayback.find_animation_player(inst)
	if ap != null:
		var birth := AnimPlayback.resolve(inst, "Birth", ap)
		if not birth.is_empty():
			AnimPlayback.play(inst, birth, 0.0, _cache, 0, ap)
	var tree := host.get_tree()
	if tree != null:
		tree.create_timer(IMPACT_LIFETIME).timeout.connect(fx.queue_free)


func _spawn_fallback_flash(host: Node, at: Vector3) -> void:
	var fx := MeshInstance3D.new()
	fx.name = "CombatImpactFallback"
	host.add_child(fx)
	fx.global_position = at
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	fx.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.35, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.2)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fx.material_override = mat
	var tree := host.get_tree()
	if tree != null:
		tree.create_timer(0.35).timeout.connect(fx.queue_free)


func _restart_particles(root: Node) -> void:
	if root == null:
		return
	if root is GPUParticles3D:
		var p := root as GPUParticles3D
		p.restart()
		p.emitting = true
	for c in root.get_children():
		_restart_particles(c)


func _face_dir(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	look_at(global_position + dir.normalized(), Vector3.UP)
