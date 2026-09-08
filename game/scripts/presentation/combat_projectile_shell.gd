extends Node3D

## Present 弹道壳：与 Logic 同速制导追目标；不改生命。

const TRACER_RADIUS := 0.14
const TRACER_COLOR := Color(1.0, 0.85, 0.35, 1.0)
const IMPACT_LIFETIME := 1.1
const IMPACT_SCALE_BOOST := 1.35
const MISSILE_SCALE := 1.0
## PE2-only 飞弹（水元素弹无 mesh）世界尺度偏小，单独放大
const PE2_ONLY_MISSILE_SCALE := 2.75
const PE2_ONLY_IMPACT_SCALE := 2.2
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
var _impact_z_offset_wc3: float = 60.0
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
	if target != null and is_instance_valid(target):
		var tgt := Wc3Coords.godot_to_wc3(target.global_position)
		_impact_z_offset_wc3 = to_wc3.z - tgt.z
	else:
		_impact_z_offset_wc3 = maxf(to_wc3.z, 40.0)
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
	add_child(_missile_root)
	_missile_root.add_child(inst)
	if _cache != null:
		# bake 过的 .scn 已含 Additive + 0.01 根缩放；prepare 只补材质/防双重缩放
		_cache.prepare_fx_model(inst, art_path)
	else:
		_fit_missile_model_scale(inst)
		if FireballMissileModern.wants(art_path, inst):
			FireballMissileModern.apply(inst)
	var pe2_only := _is_pe2_only_missile(inst)
	var modern_fireball := bool(inst.get_meta(FireballMissileModern.META_APPLIED, false))
	_missile_root.scale = Vector3.ONE * (PE2_ONLY_MISSILE_SCALE if pe2_only else MISSILE_SCALE)
	# 有实体 mesh 的飞弹（火球）：模型轴多为 +Y，look_at 对齐 -Z
	# PE2-only（水元素弹）：粒子已是广告牌，再拧 -90° 会把曳迹拧扁
	# 现代火球：光核/粒子已是 billboard，勿再拧轴
	if not pe2_only and not modern_fireball:
		_missile_root.rotation.x = -PI * 0.5
	if not modern_fireball:
		Wc3Pe2Particles.attach_to(inst, art_path)
	# 飞行序列：Stand（火球）→ Birth（水元素弹等仅有 Birth/Death 的 PE2 弹）
	var flight_seq := _resolve_flight_sequence(inst)
	if not modern_fireball:
		Wc3Pe2Particles.apply_sequence(inst, flight_seq)
		# 脉冲发射器在 apply_sequence 时会先关闸等 Animation 轨；飞弹壳无完整轨时强制开
		_force_flight_particles(inst, flight_seq)
	var ap := AnimPlayback.find_animation_player(inst)
	if ap != null:
		var anim := AnimPlayback.resolve(inst, flight_seq, ap)
		if not anim.is_empty():
			# 强制 LOOP：Birth 在 MDX 标 NonLooping，但作飞行壳须持续发射
			AnimPlayback.play(inst, anim, 0.0, _cache, 1, ap)


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
	var tgt := Wc3Coords.godot_to_wc3(_target.global_position)
	_to = Wc3Coords.wc3_to_godot(
		Vector3(tgt.x, tgt.y, tgt.z + _impact_z_offset_wc3)
	)


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
	var place := _resolve_impact_parent()
	var parent: Node = place.get("parent") as Node
	var local_pos: Vector3 = place.get("local_pos", Vector3.ZERO) as Vector3
	var use_global: bool = bool(place.get("use_global", false))
	if parent == null:
		return
	if inst == null:
		_spawn_fallback_flash(parent, local_pos, use_global)
		return
	var fx := Node3D.new()
	fx.name = "CombatImpactFx"
	parent.add_child(fx)
	if use_global:
		fx.global_position = local_pos
	else:
		fx.position = local_pos
	if _cache != null:
		_cache.prepare_fx_model(inst, art_path)
	else:
		_fit_missile_model_scale(inst)
		if FireballMissileModern.wants(art_path, inst):
			FireballMissileModern.apply(inst)
	var pe2_only := _is_pe2_only_missile(inst)
	var modern_fireball := bool(inst.get_meta(FireballMissileModern.META_APPLIED, false))
	fx.scale = Vector3.ONE * (PE2_ONLY_IMPACT_SCALE if pe2_only else IMPACT_SCALE_BOOST)
	fx.add_child(inst)
	var impact_seq := _resolve_impact_sequence(inst)
	if modern_fireball:
		var ctrl := inst.find_child(FireballMissileModern.NODE_CONTROLLER, true, false)
		if ctrl != null and ctrl.has_method("set_impact_mode"):
			ctrl.call("set_impact_mode")
	else:
		Wc3Pe2Particles.attach_to(inst, art_path)
		# 火球等：爆开在 Death；Birth 极短且无 burst。优先 Death → Birth → Stand。
		Wc3Pe2Particles.apply_sequence(inst, impact_seq)
		# Death 脉冲粒子：强制开（空 active_sequences 推断后的 burst）
		_force_flight_particles(inst, impact_seq)
		_restart_particles(inst)
	var ap := AnimPlayback.find_animation_player(inst)
	if ap != null:
		var anim := AnimPlayback.resolve(inst, impact_seq, ap)
		if not anim.is_empty():
			AnimPlayback.play(inst, anim, 0.0, _cache, 0, ap)
	var life := IMPACT_LIFETIME * (1.25 if pe2_only else 1.0)
	var tree := parent.get_tree()
	if tree != null:
		tree.create_timer(life).timeout.connect(
			func() -> void:
				if is_instance_valid(fx):
					fx.queue_free()
		)


## 有目标：挂**单位实体根**（不跟进 SkinMeshes/插座，避免继承 MODEL_SCALE=0.01
## 把命中 FX 缩没）；位置取 chest/origin 世界坐标，随单位平移/旋转。
## 无目标：仍落地图层世界坐标。
func _resolve_impact_parent() -> Dictionary:
	if _target != null and is_instance_valid(_target):
		var world_pos := _impact_world_pos_on_target(_target)
		return {"parent": _target, "local_pos": world_pos, "use_global": true}
	var host := get_parent()
	return {"parent": host, "local_pos": _to, "use_global": true}


func _impact_world_pos_on_target(target: Node3D) -> Vector3:
	var place := AbilityAttachFxPresenter.resolve_attach(
		target, "chest", Vector3(0.0, 0.55, 0.0)
	)
	var sock: Node3D = place.get("parent", target) as Node3D
	var local_off: Vector3 = place.get("local_pos", Vector3(0.0, 0.55, 0.0)) as Vector3
	if sock != null and is_instance_valid(sock) and sock != target:
		# 插座在 scaled 模型树内：只用它的世界坐标，不把 FX 挂进去。
		return sock.global_position
	return target.to_global(local_off)


## 命中序列：有 Death 用 Death（壳隐 + burst PE2）；否则 Birth / Stand。
func _resolve_impact_sequence(inst: Node) -> String:
	if inst == null:
		return "Birth"
	var ap := AnimPlayback.find_animation_player(inst)
	if ap == null:
		return "Birth"
	for want in ["Death", "Birth", "Stand"]:
		if not AnimPlayback.resolve(inst, want, ap).is_empty():
			return want
	return "Birth"


## 飞行序列：优先 Stand；无则 Birth（WaterElementalMissile 仅 Birth+Death）。
func _resolve_flight_sequence(inst: Node) -> String:
	if inst == null:
		return "Stand"
	var ap := AnimPlayback.find_animation_player(inst)
	if ap == null:
		return "Stand"
	for want in ["Stand", "Birth"]:
		if not AnimPlayback.resolve(inst, want, ap).is_empty():
			return want
	var names := ap.get_animation_list()
	if not names.is_empty():
		var leaf := str(names[0])
		var slash := leaf.rfind("/")
		if slash >= 0:
			leaf = leaf.substr(slash + 1)
		return leaf
	return "Stand"


func _spawn_fallback_flash(host: Node, at: Vector3, use_global: bool = true) -> void:
	var fx := MeshInstance3D.new()
	fx.name = "CombatImpactFallback"
	host.add_child(fx)
	if use_global:
		fx.global_position = at
	else:
		fx.position = at
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
		tree.create_timer(0.35).timeout.connect(
			func() -> void:
				if is_instance_valid(fx):
					fx.queue_free()
		)


func _restart_particles(root: Node) -> void:
	if root == null:
		return
	if root is GPUParticles3D:
		var p := root as GPUParticles3D
		p.restart()
		p.emitting = true
	for c in root.get_children():
		_restart_particles(c)


## 飞行壳：对属于 flight_seq 的 PE2 强制 emitting（避免 pulse 关闸后看不见曳迹）。
func _force_flight_particles(root: Node, flight_seq: String) -> void:
	if root == null:
		return
	for n in root.find_children("*", "GPUParticles3D", true, false):
		var p := n as GPUParticles3D
		if p == null:
			continue
		if not Wc3Pe2Particles.emitting_for_sequence(p, flight_seq):
			continue
		p.emitting = true
		p.restart()
		# PE2-only 飞弹：略抬发射量，避免水花太稀
		if p.amount < 48:
			p.amount = mini(p.amount * 2, 96)
		p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))


## 无可视 Mesh（仅 Armature + PE2）的飞弹，如 WaterElementalMissile。
func _is_pe2_only_missile(root: Node) -> bool:
	if root == null:
		return false
	var has_mesh := false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		# Ribbon / soft-orb 广告牌不算「实体 mesh」——否则水元素会丢掉 PE2_ONLY 放大
		if str(mi.name) == "FxBillboard" or mi.has_meta("wc3_ribbon_active_sequences") \
				or mi.has_meta("wc3_ribbon_always_on"):
			continue
		has_mesh = true
		break
	if has_mesh:
		return false
	for n2 in root.find_children("*", "GPUParticles3D", true, false):
		if n2 is GPUParticles3D:
			return true
	return false


func _fit_missile_model_scale(inst: Node3D) -> void:
	if inst == null:
		return
	var aabb := AABB()
	var first := true
	for c in inst.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if vi == null:
			continue
		var la := vi.get_aabb()
		var xf := vi.global_transform
		for i in range(8):
			var local := la.position + la.size * Vector3(
				float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1)
			)
			var p := inst.to_local(xf * local)
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	if aabb.size.length() > 2.0:
		inst.scale = Vector3.ONE * Wc3Coords.WORLD_SCALE


func _face_dir(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	look_at(global_position + dir.normalized(), Vector3.UP)
