extends SceneTree
## Global Sequence：循环 Stand 必须长到旗/钟能飘完一圈，且 Flag 旋转非绑定位姿。
## godot --headless --path . -s res://tests/unit/selftest_global_seq_flags.gd

var passed: int = 0
var total: int = 3


func _init() -> void:
	_test_stand_covers_global_seq()
	_test_flag_rotation_varies()
	_test_bell_swings_on_work_upgrade()
	if passed == total:
		print("selftest_global_seq_flags: PASS")
		quit(0)
	else:
		push_error("selftest_global_seq_flags: FAIL %d/%d" % [passed, total])
		quit(1)


func _test_stand_covers_global_seq() -> void:
	var pack := _townhall_stand()
	if pack.is_empty():
		return
	var stand: Animation = pack.stand
	var inst: Node = pack.inst
	# 旗 GlobalSeq 最短 1.3s；分针 6.7s。至少要长过「只播 333ms 抖一下」。
	if stand.length < 1.2:
		push_error("test_1 FAIL: Stand length=%s want >= 1.2s (Global Sequence)" % stand.length)
		inst.queue_free()
		return
	print("  TownHall Stand length=%.3fs (Global Sequence bake)" % stand.length)
	passed += 1
	inst.queue_free()


func _test_flag_rotation_varies() -> void:
	var pack := _townhall_stand()
	if pack.is_empty():
		return
	var stand: Animation = pack.stand
	var inst: Node = pack.inst
	var found := false
	var varying := false
	for i in range(stand.get_track_count()):
		if stand.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var pth := str(stand.track_get_path(i))
		if pth.findn("Flag") < 0:
			continue
		found = true
		var n := stand.track_get_key_count(i)
		if n < 4:
			continue
		var q0: Quaternion = stand.rotation_track_interpolate(i, 0.0)
		var q1: Quaternion = stand.rotation_track_interpolate(i, minf(stand.length * 0.4, stand.length))
		if q0.angle_to(q1) > 0.03:
			varying = true
			break
	if not found:
		push_error("test_2 FAIL: Stand has no Flag rotation track")
		inst.queue_free()
		return
	if not varying:
		push_error("test_2 FAIL: Flag rotation stays at bind pose")
		inst.queue_free()
		return
	print("  TownHall Stand Flag rotation varies")
	passed += 1
	inst.queue_free()


# 铃铛无 GlobalSeq；误把 null 当成 GS0 会冻在 bind。施工升级段应摆动。
func _test_bell_swings_on_work_upgrade() -> void:
	var scn = load("res://assets/asset-converted/Buildings/Human/TownHall/TownHall.scn")
	if scn == null:
		push_error("test_3 FAIL: TownHall.scn load null")
		return
	var inst = scn.instantiate()
	if inst == null:
		push_error("test_3 FAIL: instantiate null")
		return
	var ap: AnimationPlayer = null
	for c in inst.find_children("*", "AnimationPlayer", true, false):
		if c is AnimationPlayer:
			ap = c
			break
	if ap == null:
		push_error("test_3 FAIL: no AnimationPlayer")
		inst.queue_free()
		return
	var work := _ap_anim(ap, "Stand Work Upgrade First")
	if work == null:
		push_error("test_3 FAIL: missing Stand Work Upgrade First")
		inst.queue_free()
		return
	var found := false
	var varying := false
	for i in range(work.get_track_count()):
		if work.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var pth := str(work.track_get_path(i))
		if pth.findn("Bell") < 0 or pth.findn("Bell01") >= 0:
			continue
		found = true
		if work.track_get_key_count(i) < 2:
			continue
		var q0: Quaternion = work.rotation_track_interpolate(i, 0.0)
		var q1: Quaternion = work.rotation_track_interpolate(i, minf(1.02, work.length * 0.5))
		if q0.angle_to(q1) > 0.08:
			varying = true
			break
	if not found:
		push_error("test_3 FAIL: Stand Work Upgrade First has no Upgrade1 Bell rotation")
		inst.queue_free()
		return
	if not varying:
		push_error("test_3 FAIL: Upgrade1 Bell rotation stays at bind")
		inst.queue_free()
		return
	print("  TownHall Stand Work Upgrade First Bell swings")
	passed += 1
	inst.queue_free()


func _townhall_stand() -> Dictionary:
	var scn = load("res://assets/asset-converted/Buildings/Human/TownHall/TownHall.scn")
	if scn == null:
		push_error("FAIL: TownHall.scn load null")
		return {}
	var inst = scn.instantiate()
	if inst == null:
		push_error("FAIL: TownHall instantiate null")
		return {}
	var ap: AnimationPlayer = null
	for c in inst.find_children("*", "AnimationPlayer", true, false):
		if c is AnimationPlayer:
			ap = c
			break
	if ap == null:
		push_error("FAIL: no AnimationPlayer")
		inst.queue_free()
		return {}
	var stand := _ap_anim(ap, "Stand")
	if stand == null:
		push_error("FAIL: missing Stand")
		inst.queue_free()
		return {}
	return { "stand": stand, "inst": inst }


func _ap_anim(ap: AnimationPlayer, leaf: String) -> Animation:
	if ap.has_animation(leaf):
		return ap.get_animation(leaf)
	var want := AnimPlayback.compact_seq_name(leaf)
	for n in ap.get_animation_list():
		if AnimPlayback.compact_seq_name(str(n)) == want:
			return ap.get_animation(str(n))
	return null
