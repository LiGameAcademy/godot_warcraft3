extends RefCounted
## Local controls repeat inside the longer skeletal bake used for global clocks.
static func compatible(player: AnimationPlayer, sequence: Dictionary) -> bool:
	if player.root_node != NodePath("..") or not player.has_animation(str(sequence.name)):
		return false
	var period: float = (float(sequence.interval[1]) - float(sequence.interval[0])) / 1000.0
	var length: float = player.get_animation(str(sequence.name)).length
	return period > 0.0 and (length >= period - 0.01 if bool(sequence.get("looping", false)) else absf(length - period) <= 0.01)

static func snapshot(scene: Node) -> Dictionary:
	var tracks: Dictionary = {}
	var players: Array[Node] = scene.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1:
		return tracks
	for node: Node in players:
		var player: AnimationPlayer = node as AnimationPlayer
		for name: String in player.get_animation_list():
			tracks[name] = player.get_animation(name).get_track_count()
	return tracks

static func repeat_controls(scene: Node, sequences: Array, before: Dictionary) -> int:
	var repeated: int = 0
	var players: Array[Node] = scene.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1:
		return 0
	for node: Node in players:
		var player: AnimationPlayer = node as AnimationPlayer
		for sequence: Dictionary in sequences:
			if not compatible(player, sequence) or not bool(sequence.get("looping", false)):
				continue
			var period: float = (float(sequence.interval[1]) - float(sequence.interval[0])) / 1000.0
			var animation: Animation = player.get_animation(str(sequence.name))
			animation.set_meta("source_period_sec", period)
			if animation.length <= period + 0.01:
				continue
			for track: int in range(int(before.get(str(sequence.name), 0)), animation.get_track_count()):
				if _repeat_track(animation, track, period):
					repeated += 1
	return repeated

static func _repeat_track(animation: Animation, track: int, period: float) -> bool:
	var count: int = animation.track_get_key_count(track)
	if count <= 1:
		return false
	# Only tracks appended by the compiler are eligible; never rewrite baked bones.
	if animation.track_get_key_time(track, count - 1) > period + 0.01:
		return false
	var keys: Array[Dictionary] = []
	for index: int in range(count):
		keys.append({"time": animation.track_get_key_time(track, index), "value": animation.track_get_key_value(track, index)})
	var tail_time: float = fmod(animation.length, period)
	var tail: Variant
	match animation.track_get_type(track):
		Animation.TYPE_VALUE:
			tail = animation.value_track_interpolate(track, tail_time)
		Animation.TYPE_POSITION_3D:
			tail = animation.position_track_interpolate(track, tail_time)
		Animation.TYPE_ROTATION_3D:
			tail = animation.rotation_track_interpolate(track, tail_time)
		Animation.TYPE_SCALE_3D:
			tail = animation.scale_track_interpolate(track, tail_time)
		_:
			return false
	for cycle: int in range(1, int(ceil(animation.length / period))):
		for key: Dictionary in keys:
			var time: float = float(key.time) + cycle * period
			if time <= animation.length:
				animation.track_insert_key(track, time, key.value)
	animation.track_insert_key(track, animation.length, tail)
	return true
