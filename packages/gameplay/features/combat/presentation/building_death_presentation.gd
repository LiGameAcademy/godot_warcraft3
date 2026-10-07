class_name BuildingDeathPresentation
extends RefCounted
## Death 原速播放；Decay 按游戏数据重定时，完整保留尸体的显隐/烟尘轨。
static func prepare(body: Node3D, settings: BuildingDeathSettings) -> void:
	var unit: Unit = Unit.of(body)
	var model: Node3D = unit.model_node() if unit != null else body.get_node_or_null("Model") as Node3D
	var player: AnimationPlayer = AnimPlayback.find_animation_player(model)
	if player == null or player.has_meta("building_decay_prepared"):
		return
	player.set_meta("building_decay_prepared", true)
	var started: Callable = func(clip: StringName) -> void:
		if not AnimPlayback.compact_seq_name(str(clip)).begins_with("decay"):
			return
		var animation: Animation = player.get_animation(clip)
		player.speed_scale = animation.length / maxf(settings.corpse_seconds, 0.01)
		_fade_ground(body)
	player.animation_started.connect(started)
	# 无 Decay 的建筑仍必须清掉运行时贴花；正常链在 Decay 开始时执行。
	body.tree_exiting.connect(func() -> void:
		if is_instance_valid(player) and player.animation_started.is_connected(started):
			player.animation_started.disconnect(started)
	, CONNECT_ONE_SHOT)

static func _fade_ground(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	for node: Node in body.find_children("*", "Decal", true, false):
		var decal: Decal = node as Decal
		if not bool(decal.get_meta("is_runtime_uber_splat", false)) or decal.has_meta("death_fading"):
			continue
		decal.set_meta("death_fading", true)
		var seconds: float = maxf(float(decal.get_meta("uber_splat_decay_seconds", 2.0)), 0.01)
		var tween: Tween = body.create_tween()
		tween.tween_property(decal, "modulate:a", 0.0, seconds)
		tween.tween_callback(decal.queue_free)
