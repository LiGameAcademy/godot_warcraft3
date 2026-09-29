extends RefCounted
## glTF carries animation curves, but not MDX sequence playback flags.
static func compile(scene: Node, ir: Dictionary) -> Dictionary:
	var result: Dictionary = {"sequences": 0, "diagnostics": []}
	var players: Array[Node] = scene.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1:
		return result
	var player: AnimationPlayer = players[0]
	for sequence: Dictionary in ir.get("animations", {}).get("payload", {}).get("sequences", []):
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
