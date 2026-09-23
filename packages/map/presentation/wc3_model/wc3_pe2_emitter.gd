@tool
extends GPUParticles3D
## World-space particles inherit emission position/velocity through Godot's
## EMISSION_TRANSFORM, but gravity and display size need explicit unit conversion.
@export_storage var model_gravity := Vector3.ZERO
@export_storage var model_particle_scale := 1.0
@export_storage var burst_mode := false
var _last_unit_scale := -1.0


func _enter_tree() -> void:
	set_notify_transform(true)
	sync_simulation_space()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		sync_simulation_space()


func sync_simulation_space() -> void:
	var material := process_material as ParticleProcessMaterial
	if material == null:
		return
	var unit_scale := 1.0
	if not local_coords:
		unit_scale = global_transform.basis.get_scale().abs().y if is_inside_tree() else 0.01
	if is_equal_approx(unit_scale, _last_unit_scale):
		return
	_last_unit_scale = unit_scale
	material.gravity = model_gravity * unit_scale
	material.scale_min = model_particle_scale * unit_scale
	material.scale_max = model_particle_scale * unit_scale


## Method keys emit discrete bursts without restarting already living particles.
func emit_burst(count: int) -> void:
	if not burst_mode or not is_visible_in_tree():
		return
	for i in range(clampi(count, 0, amount)):
		emit_particle(Transform3D.IDENTITY, Vector3.ZERO, Color.WHITE, Color(), 0)
