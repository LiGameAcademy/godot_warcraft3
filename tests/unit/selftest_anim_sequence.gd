extends SceneTree
## Stance × Activity → Sequence 命名契约（AnimSequenceResolver）。
##
## godot --headless --path . -s res://tests/unit/selftest_anim_sequence.gd

var passed: int = 0
var total: int = 0


func _init() -> void:
	_expect(
		"peasant idle gold",
		AnimSequenceResolver.sequence_name(
			AnimSequenceResolver.Activity.IDLE, AnimSequenceResolver.Stance.GOLD
		),
		"Stand Gold"
	)
	_expect(
		"peasant walk lumber",
		AnimSequenceResolver.sequence_name(
			AnimSequenceResolver.Activity.MOVE, AnimSequenceResolver.Stance.LUMBER
		),
		"Walk Lumber"
	)
	_expect(
		"peasant work gold",
		AnimSequenceResolver.sequence_name(
			AnimSequenceResolver.Activity.WORK, AnimSequenceResolver.Stance.GOLD
		),
		"Stand Work Gold"
	)
	_expect(
		"attack lumber",
		AnimSequenceResolver.sequence_name(
			AnimSequenceResolver.Activity.ATTACK, AnimSequenceResolver.Stance.LUMBER
		),
		"Attack Lumber"
	)
	_expect(
		"town hall keep idle",
		AnimSequenceResolver.sequence_name(
			AnimSequenceResolver.Activity.IDLE,
			AnimSequenceResolver.stance_for_building_type("hkee")
		),
		"Stand Upgrade First"
	)
	_expect(
		"town hall castle birth",
		AnimSequenceResolver.sequence_name(
			AnimSequenceResolver.Activity.BIRTH,
			AnimSequenceResolver.stance_for_building_type("hcas")
		),
		"Birth Upgrade Second"
	)
	_expect(
		"underscored",
		AnimSequenceResolver.sequence_name_underscored(
			AnimSequenceResolver.Activity.WORK, AnimSequenceResolver.Stance.LUMBER
		),
		"Stand_Work_Lumber"
	)
	_expect(
		"avatar alternate stand",
		AnimSequenceResolver.sequence_name(
			AnimSequenceResolver.Activity.IDLE, AnimSequenceResolver.Stance.ALTERNATE
		),
		"Alternate Stand"
	)
	_expect(
		"avatar alternate walk",
		AnimSequenceResolver.sequence_name(
			AnimSequenceResolver.Activity.MOVE, AnimSequenceResolver.Stance.ALTERNATE
		),
		"Alternate Walk"
	)
	_expect_bool("ping stand gold", AnimSequenceResolver.needs_ping_pong("Stand_Gold"), true)
	_expect_bool("ping stand gold camel", AnimSequenceResolver.needs_ping_pong("StandGold"), true)
	_expect_bool("ping walk gold", AnimSequenceResolver.needs_ping_pong("Walk_Gold"), false)
	_expect(
		"compact decay flesh",
		AnimPlayback.compact_seq_name("Decay Flesh"),
		"decayflesh"
	)
	_expect(
		"compact stand variant",
		AnimPlayback.compact_seq_name("Stand - 2"),
		"stand-2"
	)
	_expect(
		"compact old underscore variant",
		AnimPlayback.compact_seq_name("Stand_-_2"),
		"stand-2"
	)
	_expect(
		"pe2 strips gold idle",
		AnimSequenceResolver.pe2_hint("Stand Gold", AnimSequenceResolver.Activity.IDLE),
		"Stand"
	)
	_expect(
		"building phase via BuildingVisual",
		BuildingVisual.sequence_name("hkee", BuildingVisual.Phase.WORK),
		"Stand Work Upgrade First"
	)

	if passed == total:
		print("selftest_anim_sequence: PASS %d/%d" % [passed, total])
		quit(0)
	else:
		push_error("selftest_anim_sequence: FAIL %d/%d" % [passed, total])
		quit(1)


func _expect(label: String, got: String, want: String) -> void:
	total += 1
	if got == want:
		passed += 1
		print("  OK %s" % label)
	else:
		push_error("FAIL %s: got '%s' want '%s'" % [label, got, want])


func _expect_bool(label: String, got: bool, want: bool) -> void:
	total += 1
	if got == want:
		passed += 1
		print("  OK %s" % label)
	else:
		push_error("FAIL %s: got %s want %s" % [label, got, want])
