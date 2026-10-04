extends RefCounted
## glTF carries animation curves, but not MDX sequence playback flags.
static func compile(scene: Node, ir: Dictionary) -> Dictionary:
	var result: Dictionary = {"sequences": 0, "diagnostics": []}
	var players: Array[Node] = scene.find_children("*", "AnimationPlayer", true, false)
	var sequences: Array = ir.get("animations", {}).get("payload", {}).get("sequences", [])
	if players.is_empty() and not sequences.is_empty():
		# Particle-only glTF has no channels. Keep clips for emitter controls.
		var created: AnimationPlayer = AnimationPlayer.new()
		created.name = "AnimationPlayer"
		scene.add_child(created)
		created.owner = scene
		var library: AnimationLibrary = AnimationLibrary.new()
		for sequence: Dictionary in sequences:
			var animation: Animation = Animation.new()
			animation.length = maxf(0.001, (float(sequence.interval[1]) - float(sequence.interval[0])) / 1000.0)
			library.add_animation(str(sequence.name), animation)
		created.add_animation_library("", library)
		players.append(created)
	if players.size() != 1:
		return result
	var player: AnimationPlayer = players[0]
	for sequence: Dictionary in sequences:
		var name: String = str(sequence.get("name", ""))
		if not player.has_animation(name) or not sequence.get("looping") is bool:
			result.diagnostics.append({"code": "sequence_metadata_missing", "severity": "warning", "animation": name})
			continue
		var animation: Animation = player.get_animation(name)
		animation.loop_mode = Animation.LOOP_LINEAR if bool(sequence.looping) else Animation.LOOP_NONE
		animation.set_meta("source_sequence_name", str(sequence.get("mdx_name", name)))
		animation.set_meta("source_interval_ms", sequence.get("interval", []))
		animation.set_meta("source_looping", bool(sequence.looping))
		result.sequences += 1
	return result
