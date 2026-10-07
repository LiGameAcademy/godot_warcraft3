extends Node
## Native/legacy loop metadata, completion signals and shared-resource isolation.
var _failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var template: Node3D = Node3D.new()
	var player: AnimationPlayer = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	template.add_child(player)
	player.owner = template
	var library: AnimationLibrary = AnimationLibrary.new()
	_add_clip(library, "Birth", "source_looping", false)
	_add_clip(library, "Spell", "source_looping", false)
	_add_clip(library, "Stand", "source_looping", true)
	_add_clip(library, "Attack", "source_looping", true)
	_add_clip(library, "LegacyBirth", "wc3_seq_looping", false)
	_add_clip(library, "LegacyStand", "wc3_seq_looping", true)
	_add_clip(library, "Untagged", "", false)
	player.add_animation_library("native", library)
	var packed: PackedScene = PackedScene.new()
	_check(packed.pack(template) == OK, "Fixture packs")
	var a: Node3D = packed.instantiate() as Node3D
	var b: Node3D = packed.instantiate() as Node3D
	add_child(a)
	add_child(b)
	var ap: AnimationPlayer = AnimPlayback.find_animation_player(a)
	var bp: AnimationPlayer = AnimPlayback.find_animation_player(b)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var finished: Array[StringName] = []
	ap.animation_finished.connect(func(clip: StringName) -> void: finished.append(clip))
	for name: String in ["Birth", "Spell", "LegacyBirth"]:
		var clip: String = "native/" + name
		AnimPlayback.play(a, clip)
		_check(ap.get_animation(clip).loop_mode == Animation.LOOP_NONE, name + " preserves NonLooping")
		ap.advance(0.25)
		_check(finished.has(StringName(clip)), name + " emits animation_finished")
	for name: String in ["Stand", "LegacyStand", "Untagged"]:
		var clip: String = "native/" + name
		AnimPlayback.play(a, clip)
		ap.advance(0.25)
		_check(ap.is_playing() and not finished.has(StringName(clip)), name + " keeps looping")
	# Contradicting old metadata must not override the native source flag.
	library.get_animation("Birth").set_meta("wc3_seq_looping", true)
	AnimPlayback.play(a, "native/Birth")
	_check(ap.get_animation("native/Birth").loop_mode == Animation.LOOP_NONE, "Native metadata takes precedence")
	var source: Animation = library.get_animation("Spell")
	AnimPlayback.play(a, "native/Spell", 0.0, null, 1)
	_check(ap.get_animation("native/Spell").loop_mode == Animation.LOOP_LINEAR, "Explicit loop override applies to A")
	_check(bp.get_animation("native/Spell").loop_mode == Animation.LOOP_NONE, "B remains unchanged")
	_check(source.loop_mode == Animation.LOOP_NONE, "Template remains unchanged")
	AnimPlayback.play(a, "native/Spell")
	_check(ap.get_animation("native/Spell").loop_mode == Animation.LOOP_NONE, "Source policy restored after override")
	AnimPlayback.play(a, "native/Stand", 0.0, null, 0)
	_check(ap.get_animation("native/Stand").loop_mode == Animation.LOOP_NONE, "Explicit single play override")
	_check(bp.get_animation("native/Stand").loop_mode == Animation.LOOP_LINEAR, "B Stand keeps looping")
	AnimPlayback.play_logical(a, "Attack", 0.0, null, AnimSequenceResolver.Activity.ATTACK)
	_check(ap.get_animation("native/Attack").loop_mode == Animation.LOOP_NONE, "Combat Attack still forces single play")
	_check(bp.get_animation("native/Attack").loop_mode == Animation.LOOP_LINEAR, "Attack override leaves B unchanged")
	ap.advance(0.25)
	_check(finished.has(&"native/Attack"), "Attack still emits completion")
	var c: Node3D = packed.instantiate() as Node3D
	_check(AnimPlayback.find_animation_player(c).get_animation("native/Spell").loop_mode == Animation.LOOP_NONE, "New instance keeps source policy")
	c.free()
	a.free()
	b.free()
	template.free()
	print("PASS: native/legacy loop policy, finish signals and A/B/template isolation" if _failures == 0 else "FAIL: animation loop regressions=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _add_clip(library: AnimationLibrary, name: String, tag: String, looping: bool) -> void:
	var animation: Animation = Animation.new()
	animation.length = 0.1
	animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	if not tag.is_empty():
		animation.set_meta(tag, looping)
	library.add_animation(name, animation)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
