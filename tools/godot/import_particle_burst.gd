extends GPUParticles3D
## Animation events trigger the source Squirt count; retained scenes need no source JSON.
func emit_burst(count: int) -> void:
	if count <= 0 or not is_visible_in_tree():
		return
	amount_ratio = clampf(float(count) / amount, 0.0, 1.0)
	emitting = true
	restart()
