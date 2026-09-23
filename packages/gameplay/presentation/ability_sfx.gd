class_name AbilitySfx
extends RefCounted

## 技能音效（Present）：按逻辑名找 wav/mp3；缺文件则静默跳过。
## 暴风雪：Func 键 BlizzardWave / BlizzardLoop — 转换包未必含 Sound，故允许多候选路径。

const _CANDIDATES := {
	"BlizzardWave": [
		"Sound/Abilities/BlizzardWave.wav",
		"Sound/Spells/BlizzardWave.wav",
		"Sound/Units/Human/HeroArchMage/BlizzardWave.wav",
		"Sound/Ambient/BlizzardWave.wav",
	],
	"BlizzardLoop": [
		"Sound/Abilities/BlizzardLoop.wav",
		"Sound/Spells/BlizzardLoop.wav",
		"Sound/Units/Human/HeroArchMage/BlizzardLoop.wav",
		"Sound/Ambient/BlizzardLoop.wav",
	],
	"MassTeleportTarget": [
		"Abilities/Spells/Human/MassTeleport/MassTeleportTarget.wav",
		"Sound/Abilities/MassTeleportTarget.wav",
		"Sound/Spells/MassTeleportTarget.wav",
	],
}

static var _stream_cache: Dictionary = {} ## key → AudioStream


static func play_oneshot(parent: Node, key: String, at_global: Vector3 = Vector3.ZERO) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var stream := _resolve_stream(key)
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.name = "AbilitySfx_%s" % key
	p.stream = stream
	p.bus = "Master"
	p.max_distance = 80.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	parent.add_child(p)
	if at_global != Vector3.ZERO:
		p.global_position = at_global
	p.finished.connect(p.queue_free)
	p.play()


static func start_loop(parent: Node, key: String, node_name: String = "AbilitySfxLoop") -> AudioStreamPlayer3D:
	if parent == null or not is_instance_valid(parent):
		return null
	var existing := parent.get_node_or_null(node_name) as AudioStreamPlayer3D
	if existing != null:
		return existing
	var stream := _resolve_stream(key)
	if stream == null:
		return null
	_try_enable_loop(stream)
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.stream = stream
	p.bus = "Master"
	p.max_distance = 90.0
	parent.add_child(p)
	p.play()
	return p


static func stop_named(parent: Node, node_name: String = "AbilitySfxLoop") -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var n := parent.get_node_or_null(node_name)
	if n != null and is_instance_valid(n):
		n.queue_free()


static func _try_enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var w := stream as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true


static func _resolve_stream(key: String) -> AudioStream:
	var k := key.strip_edges()
	if k.is_empty():
		return null
	if _stream_cache.has(k):
		return _stream_cache[k] as AudioStream
	var paths: Array = _CANDIDATES.get(k, [k]) as Array
	for raw in paths:
		var rel := str(raw).strip_edges().replace("\\", "/")
		if rel.is_empty():
			continue
		var res := RuntimeAssets.converted_path(rel)
		var try_paths: PackedStringArray = [res, res.get_basename() + ".mp3", res.get_basename() + ".ogg"]
		for cand in try_paths:
			if not RuntimeAssets.file_exists(cand) and not ResourceLoader.exists(cand):
				continue
			var stream: AudioStream = load(cand) as AudioStream
			if stream != null:
				_stream_cache[k] = stream
				return stream
	_stream_cache[k] = null
	return null
