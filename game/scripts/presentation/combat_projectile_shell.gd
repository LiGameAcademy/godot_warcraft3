extends Node3D

## Present 弹道壳：可选曳光 + 命中模型（RifleImpact 等）。不改生命。

const TRACER_RADIUS := 0.06
const TRACER_COLOR := Color(1.0, 0.85, 0.35, 1.0)
const IMPACT_LIFETIME := 1.1
## RTS 相机下 0.01 模型内粒子偏小，命中再放大一截
const IMPACT_SCALE_BOOST := 2.75

var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _duration: float = 0.2
var _elapsed: float = 0.0
var _show_tracer: bool = true
var _impact_art: String = ""
var _cache: MapModelCache = null
var _target: Node3D = null
var _impact_z_wc3: float = 60.0
var _mi: MeshInstance3D = null
var _impact_done: bool = false


func play(
	from_wc3: Vector3,
	to_wc3: Vector3,
	duration: float,
	show_tracer: bool = true,
	impact_art: String = "",
	cache: MapModelCache = null,
	target: Node3D = null
) -> void:
	_from = Wc3Coords.wc3_to_godot(from_wc3)
	_to = Wc3Coords.wc3_to_godot(to_wc3)
	_duration = maxf(duration, 0.05)
	_elapsed = 0.0
	_show_tracer = show_tracer
	_impact_art = impact_art.strip_edges()
	_cache = cache
	_target = target
	_impact_z_wc3 = to_wc3.z
	_impact_done = false
	global_position = _from
	if _show_tracer:
		_ensure_tracer()
		_face_dir(_to - _from)
	set_process(true)


func _ensure_tracer() -> void:
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


func _process(delta: float) -> void:
	_elapsed += delta
	_refresh_aim()
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	if _show_tracer:
		global_position = _from.lerp(_to, t)
		_face_dir(_to - _from)
	if t >= 1.0:
		_spawn_impact()
		queue_free()


func _refresh_aim() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var xy := Wc3Coords.godot_to_wc3_xy(_target.global_position)
	_to = Wc3Coords.wc3_to_godot(Vector3(xy.x, xy.y, _impact_z_wc3))


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
		# 兜底：可见闪光，避免加载失败时「完全没特效」
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
