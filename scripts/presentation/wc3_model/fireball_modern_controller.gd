class_name FireballModernController
extends Node
## 监听 AnimationPlayer：Stand/Birth → 飞行态；Death → 命中爆。
## 由 FireballMissileModern 挂到 ModernFX 下。

var _flight := true


func _ready() -> void:
	var host := _fx_root()
	if host == null:
		return
	var model := host.get_parent()
	var ap := AnimPlayback.find_animation_player(model)
	if ap != null:
		if not ap.animation_started.is_connected(_on_animation_started):
			ap.animation_started.connect(_on_animation_started)
		var cur := String(ap.current_animation)
		if not cur.is_empty():
			_on_animation_started(cur)
		else:
			set_flight_mode()
	else:
		set_flight_mode()


func _fx_root() -> Node3D:
	return get_parent() as Node3D


func _on_animation_started(anim_name: StringName) -> void:
	var n := String(anim_name).to_lower()
	if n.contains("death"):
		set_impact_mode()
	else:
		set_flight_mode()


func set_flight_mode() -> void:
	_flight = true
	var fx := _fx_root()
	if fx == null:
		return
	_set_mi_visible(fx, "Core", true)
	_set_mi_visible(fx, "Halo", true)
	_set_light(fx, true, 1.8)
	_set_particles(fx, "Smoke", true, false)
	_set_particles(fx, "FlameTrail", true, false)
	_set_particles(fx, "Burst", false, false)


func set_impact_mode() -> void:
	_flight = false
	var fx := _fx_root()
	if fx == null:
		return
	_set_mi_visible(fx, "Core", false)
	_set_mi_visible(fx, "Halo", false)
	_set_light(fx, true, 3.2)
	_set_particles(fx, "Smoke", false, false)
	_set_particles(fx, "FlameTrail", false, false)
	_set_particles(fx, "Burst", true, true)
	# 命中闪光短衰减
	var t := get_tree().create_timer(0.25)
	t.timeout.connect(func () -> void:
		if is_instance_valid(self):
			_set_light(fx, false, 0.0)
	)


func _set_mi_visible(fx: Node, name: String, on: bool) -> void:
	var n := fx.get_node_or_null(name)
	if n is MeshInstance3D:
		(n as MeshInstance3D).visible = on


func _set_light(fx: Node, on: bool, energy: float) -> void:
	var n := fx.get_node_or_null("Omni")
	if n is OmniLight3D:
		var L := n as OmniLight3D
		L.visible = on
		L.light_energy = energy


func _set_particles(fx: Node, name: String, emitting: bool, restart: bool) -> void:
	var n := fx.get_node_or_null(name)
	if not (n is GPUParticles3D):
		return
	var p := n as GPUParticles3D
	p.visible = emitting or name == "Burst"
	if restart:
		p.restart()
		p.emitting = true
	else:
		p.emitting = emitting
