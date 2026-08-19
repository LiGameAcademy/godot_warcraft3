extends SceneTree
## C-2 selftest: 烘焙 .scn 时 attachments 拼装 + PE2 打进场景。
## godot --headless --path . -s res://tests/unit/selftest_attachment_bake.gd

var passed: int = 0
var total: int = 9


func _init() -> void:
	_test_footman_scn_has_bone_attachments()
	_test_footman_bone_attachments_count()
	_test_footman_attachment_marker()
	_test_footman_particle_attachments()
	_test_townhall_sockets_and_light()
	_test_footman_animkeys_bake()
	_test_townhall_pe2_bake()
	_test_townhall_birth_dust_and_portrait_cam()
	_test_archmage_weapon_tip_world()

	if passed == total:
		print("selftest_attachment_bake: PASS")
		quit(0)
	else:
		push_error("selftest_attachment_bake: FAIL %d/%d" % [passed, total])
		quit(1)


# Test 1: Skeleton3D 只留骨头；Geoset 蒙皮在 SkinMeshes；Attachments 只有 Attach_*
func _test_footman_scn_has_bone_attachments() -> void:
	var scn = load("res://assets/asset-converted/Units/Human/Footman/Footman.scn")
	if scn == null:
		push_error("test_1 FAIL: Footman scn load null (没烤？)")
		return
	var inst = scn.instantiate()
	if inst == null:
		push_error("test_1 FAIL: instantiate null")
		return
	var skeleton = null
	for c in inst.find_children("*", "Skeleton3D", true, false):
		if c is Skeleton3D:
			skeleton = c
			break
	if skeleton == null:
		push_error("test_1 FAIL: no Skeleton3D")
		inst.queue_free()
		return
	for c in skeleton.get_children():
		if c is BoneAttachment3D or c is MeshInstance3D:
			push_error("test_1 FAIL: Skeleton3D still has %s '%s'" % [c.get_class(), c.name])
			inst.queue_free()
			return
	var skin_host = inst.find_child("SkinMeshes", true, false)
	if skin_host == null:
		push_error("test_1 FAIL: no SkinMeshes bucket")
		inst.queue_free()
		return
	var geoset_n := 0
	for c in skin_host.get_children():
		if c is MeshInstance3D and str(c.name).begins_with("Geoset_"):
			geoset_n += 1
	if geoset_n < 3:
		push_error("test_1 FAIL: SkinMeshes Geoset_* count=%d (want >=3, glTF 对齐)" % geoset_n)
		inst.queue_free()
		return
	var ba_host = inst.find_child("Attachments", true, false)
	if ba_host == null:
		push_error("test_1 FAIL: no Attachments bucket")
		inst.queue_free()
		return
	var ba_n := 0
	for c in ba_host.get_children():
		if not (c is BoneAttachment3D):
			continue
		ba_n += 1
		var nm := str(c.name)
		if not nm.begins_with("Attach_"):
			push_error("test_1 FAIL: Attachments has non-Attach '%s'" % nm)
			inst.queue_free()
			return
	if ba_n < 1:
		push_error("test_1 FAIL: Attachments empty")
	else:
		print("  Footman skins=%d BA(Attach_*)=%d OK" % [geoset_n, ba_n])
		passed += 1
	inst.queue_free()


# Test 2: Helpers 已进 Skin 后，Foot Left Ref 应绑到 Bone_Foot_L
func _test_footman_bone_attachments_count() -> void:
	var scn = load("res://assets/asset-converted/Units/Human/Footman/Footman.scn")
	if scn == null:
		push_error("test_2 FAIL: scn load null")
		return
	var inst = scn.instantiate()
	if inst == null:
		return
	var foot_l := false
	var ba_count := 0
	for c in inst.find_children("*", "BoneAttachment3D", true, false):
		var ba := c as BoneAttachment3D
		if ba == null:
			continue
		ba_count += 1
		if ba.bone_name == "Bone_Foot_L":
			foot_l = true
	if not foot_l:
		push_error("test_2 FAIL: no BoneAttachment3D with bone_name=Bone_Foot_L (got %d BA)" % ba_count)
	elif ba_count < 6 or ba_count > 12:
		push_error("test_2 FAIL: BoneAttachment3D total=%d (want ~7 Attach_*, not VertexGroup 拆组)" % ba_count)
	else:
		print("  Footman Bone_Foot_L attachment OK (BoneAttachment3D total=%d)" % ba_count)
		passed += 1
	inst.queue_free()


# Test 3: 绑骨挂点本身就是插座，不再挂 *_marker 空子节点
func _test_footman_attachment_marker() -> void:
	var scn = load("res://assets/asset-converted/Units/Human/Footman/Footman.scn")
	if scn == null:
		push_error("test_3 FAIL: scn load null")
		return
	var inst = scn.instantiate()
	if inst == null:
		return
	var ba_n := 0
	var dummy := 0
	for c in inst.find_children("*", "BoneAttachment3D", true, false):
		var ba := c as BoneAttachment3D
		if ba == null:
			continue
		ba_n += 1
		for sc in ba.get_children():
			var nm := str(sc.name)
			if nm.ends_with("_marker") or nm.ends_with("_particles"):
				dummy += 1
	if ba_n < 1:
		push_error("test_3 FAIL: no BoneAttachment3D")
	elif dummy > 0:
		push_error("test_3 FAIL: leftover dummy children=%d" % dummy)
	else:
		print("  Footman BoneAttachment3D sockets have no dummy children OK")
		passed += 1
	inst.queue_free()


# Test 4: Footman collision sidecar 烤进 MdxCollision（2 个球）
func _test_footman_particle_attachments() -> void:
	var scn = load("res://assets/asset-converted/Units/Human/Footman/Footman.scn")
	if scn == null:
		push_error("test_4 FAIL: scn load null")
		return
	var inst = scn.instantiate()
	if inst == null:
		return
	var host = inst.find_child("MdxCollision", true, false)
	if host == null:
		push_error("test_4 FAIL: no MdxCollision node")
		inst.queue_free()
		return
	var spheres := 0
	for c in host.get_children():
		if c is Area3D:
			spheres += 1
	if spheres < 2:
		push_error("test_4 FAIL: expected >= 2 collision Area3D got %d" % spheres)
	else:
		print("  Footman MdxCollision Area3D: %d" % spheres)
		passed += 1
	inst.queue_free()


# Test 5: TownHall Omni 进 Pe2Root；Sprite* 在根下 SpriteRefs；骨骼挂点在 Attachments
func _test_townhall_sockets_and_light() -> void:
	var scn = load("res://assets/asset-converted/Buildings/Human/TownHall/TownHall.scn")
	if scn == null:
		push_error("test_5 FAIL: TownHall scn load null")
		return
	var inst = scn.instantiate()
	if inst == null:
		push_error("test_5 FAIL: instantiate null")
		return
	var leftover_blast := false
	for n in inst.find_children("BlastFlare", "Node3D", true, false):
		var node := n as Node
		var p: Node = node.get_parent() if node != null else null
		if p != null and str(p.name) != "Pe2Root":
			leftover_blast = true
			break
	if leftover_blast:
		push_error("test_5 FAIL: leftover BlastFlare attachment stub")
		inst.queue_free()
		return
	var host = inst.find_child("SpriteRefs", true, false)
	if host == null:
		push_error("test_5 FAIL: no SpriteRefs bucket")
		inst.queue_free()
		return
	var sprite_n := 0
	for c in host.get_children():
		if c is Marker3D and str(c.name).begins_with("Sprite"):
			if c.get_child_count() != 0:
				push_error("test_5 FAIL: Sprite socket '%s' still has children" % c.name)
				inst.queue_free()
				return
			sprite_n += 1
	if sprite_n < 5:
		push_error("test_5 FAIL: Sprite Marker3D count=%d" % sprite_n)
		inst.queue_free()
		return
	if host.find_child("Origin Ref", false, false) != null:
		push_error("test_5 FAIL: Origin Ref should not be under SpriteRefs")
		inst.queue_free()
		return
	var origin = inst.find_child("Origin Ref", true, false)
	if origin == null or not (origin is Marker3D):
		push_error("test_5 FAIL: Origin Ref missing or not Marker3D")
		inst.queue_free()
		return
	if origin.get_parent() != inst:
		push_error("test_5 FAIL: Origin Ref parent=%s want scene root" % origin.get_parent())
		inst.queue_free()
		return
	if origin.position.y < 0.02:
		push_error("test_5 FAIL: Origin Ref y=%s (double-scaled under 0.01?)" % origin.position.y)
		inst.queue_free()
		return
	if inst.get_script() == null or not inst.has_method("overhead_anchor"):
		push_error("test_5 FAIL: scn root missing Wc3ModelScene API")
		inst.queue_free()
		return
	var oh: Variant = inst.call("overhead_anchor")
	if not (oh is Node3D):
		push_error("test_5 FAIL: overhead_anchor() returned %s" % str(oh))
		inst.queue_free()
		return
	var oh_n := oh as Node3D
	if oh_n.get_parent() != inst:
		push_error("test_5 FAIL: OverHead parent=%s want scene root" % oh_n.get_parent())
		inst.queue_free()
		return
	if oh_n.position.y < 1.0:
		push_error("test_5 FAIL: OverHead y=%s (should be ~3.5m, not ×0.01)" % oh_n.position.y)
		inst.queue_free()
		return
	var pe2 = inst.find_child("Pe2Root", true, false)
	if pe2 == null:
		push_error("test_5 FAIL: no Pe2Root")
		inst.queue_free()
		return
	if host.get_parent() != inst:
		push_error("test_5 FAIL: SpriteRefs parent=%s want scene root" % host.get_parent())
		inst.queue_free()
		return
	var cam = inst.find_child("Camera01", true, false)
	if cam == null or not (cam is Camera3D):
		push_error("test_5 FAIL: Camera01 missing")
		inst.queue_free()
		return
	if cam.get_parent() != inst:
		push_error("test_5 FAIL: Camera01 parent=%s want scene root (not 0.01)" % cam.get_parent())
		inst.queue_free()
		return
	var omni: OmniLight3D = inst.find_child("Omni01", false, false) as OmniLight3D
	if omni == null:
		push_error("test_5 FAIL: Omni01 missing on scene root")
		inst.queue_free()
		return
	if omni.get_parent() != inst:
		push_error("test_5 FAIL: Omni01 parent=%s want scene root (not Pe2Root/0.01)" % omni.get_parent())
		inst.queue_free()
		return
	if omni.find_child("Flash", false, false) == null:
		push_error("test_5 FAIL: Omni01 missing Flash mesh")
		inst.queue_free()
		return
	if omni.omni_range < 1.0:
		push_error("test_5 FAIL: Omni01 range=%s want ~2m" % omni.omni_range)
		inst.queue_free()
		return
	var ap: AnimationPlayer = null
	for c3 in inst.find_children("*", "AnimationPlayer", true, false):
		if c3 is AnimationPlayer:
			ap = c3
			break
	if ap != null:
		for an in ap.get_animation_list():
			var anim := ap.get_animation(an)
			if anim == null:
				continue
			for ti in range(anim.get_track_count()):
				var pth := str(anim.track_get_path(ti))
				if pth.contains("Pe2Root") and pth.ends_with("Omni01:visible"):
					push_error("test_5 FAIL: Omni vis still under Pe2Root %s in %s" % [pth, an])
					inst.queue_free()
					return
				if pth == "TownHall/Omni01:visible":
					push_error("test_5 FAIL: stale Omni vis track %s in %s" % [pth, an])
					inst.queue_free()
					return
	print("  TownHall sockets on root, Omni01+Flash on proto OK")
	passed += 1
	inst.queue_free()


# Test 6: animkeys → loop_mode / rarity / move_speed / Death Event Method Track
func _test_footman_animkeys_bake() -> void:
	var scn = load("res://assets/asset-converted/Units/Human/Footman/Footman.scn")
	if scn == null:
		push_error("test_6 FAIL: scn load null")
		return
	var inst = scn.instantiate()
	if inst == null:
		return
	var ap: AnimationPlayer = null
	for c in inst.find_children("*", "AnimationPlayer", true, false):
		if c is AnimationPlayer:
			ap = c
			break
	if ap == null:
		push_error("test_6 FAIL: no AnimationPlayer")
		inst.queue_free()
		return
	var death := _ap_anim(ap, "Death")
	var walk := _ap_anim(ap, "Walk")
	var stand2 := _ap_anim(ap, "Stand-2")
	if death == null or walk == null or stand2 == null:
		push_error("test_6 FAIL: missing Death/Walk/Stand-2")
		inst.queue_free()
		return
	if death.loop_mode != Animation.LOOP_NONE:
		push_error("test_6 FAIL: Death loop_mode=%d want LOOP_NONE" % death.loop_mode)
		inst.queue_free()
		return
	if walk.loop_mode != Animation.LOOP_LINEAR:
		push_error("test_6 FAIL: Walk loop_mode=%d want LOOP_LINEAR" % walk.loop_mode)
		inst.queue_free()
		return
	if int(walk.get_meta("wc3_move_speed", -1)) != 215:
		push_error("test_6 FAIL: Walk wc3_move_speed=%s" % str(walk.get_meta("wc3_move_speed", null)))
		inst.queue_free()
		return
	if int(stand2.get_meta("wc3_rarity", -1)) != 4:
		push_error("test_6 FAIL: Stand-2 wc3_rarity=%s" % str(stand2.get_meta("wc3_rarity", null)))
		inst.queue_free()
		return
	var ev_host = inst.find_child("MdxEvents", true, false)
	if ev_host == null:
		push_error("test_6 FAIL: no MdxEvents")
		inst.queue_free()
		return
	var has_snd := false
	for i in range(death.get_track_count()):
		if death.track_get_type(i) != Animation.TYPE_METHOD:
			continue
		for k in range(death.track_get_key_count(i)):
			var kv: Variant = death.track_get_key_value(i, k)
			var args: Array = []
			if typeof(kv) == TYPE_DICTIONARY:
				var av: Variant = (kv as Dictionary).get("args", [])
				if typeof(av) == TYPE_ARRAY:
					args = av
			if args.size() > 0 and str(args[0]) == "SNDXDFOO":
				has_snd = true
				break
	if not has_snd:
		push_error("test_6 FAIL: Death missing SNDXDFOO method key")
	else:
		print("  Footman animkeys loop/meta/SNDXDFOO OK")
		passed += 1
	inst.queue_free()


# Test 7: bake:scn 把 PE2 打进 TownHall.scn（Pe2Root + Stand Work :emitting）
func _test_townhall_pe2_bake() -> void:
	var scn = load("res://assets/asset-converted/Buildings/Human/TownHall/TownHall.scn")
	if scn == null:
		push_error("test_7 FAIL: TownHall scn load null (没烤？)")
		return
	var inst = scn.instantiate()
	if inst == null:
		push_error("test_7 FAIL: instantiate null")
		return
	var pe2 = inst.find_child("Pe2Root", true, false)
	if pe2 == null:
		push_error("test_7 FAIL: no Pe2Root")
		inst.queue_free()
		return
	var parent := pe2.get_parent() as Node3D
	if parent == null or absf(parent.scale.x - 0.01) > 1e-3:
		push_error("test_7 FAIL: Pe2Root parent scale=%s want 0.01" % str(parent.scale if parent else "?"))
		inst.queue_free()
		return
	var gp_n := 0
	for c in pe2.get_children():
		if c is GPUParticles3D:
			gp_n += 1
	if gp_n < 1:
		push_error("test_7 FAIL: Pe2Root GPUParticles3D count=%d" % gp_n)
		inst.queue_free()
		return
	var ap: AnimationPlayer = null
	for c2 in inst.find_children("*", "AnimationPlayer", true, false):
		if c2 is AnimationPlayer:
			ap = c2
			break
	if ap == null:
		push_error("test_7 FAIL: no AnimationPlayer")
		inst.queue_free()
		return
	var work := _ap_anim(ap, "Stand Work")
	if work == null:
		push_error("test_7 FAIL: missing Stand Work")
		inst.queue_free()
		return
	var emit_tracks := 0
	for i in range(work.get_track_count()):
		if work.track_get_type(i) != Animation.TYPE_VALUE:
			continue
		var pth := str(work.track_get_path(i))
		if pth.contains("Pe2Root") and pth.ends_with(":emitting"):
			emit_tracks += 1
	if emit_tracks < 1:
		push_error("test_7 FAIL: Stand Work has no Pe2Root :emitting tracks")
		inst.queue_free()
		return
	var work_smoke_on := false
	for i2 in range(work.get_track_count()):
		if work.track_get_type(i2) != Animation.TYPE_VALUE:
			continue
		var pth2 := str(work.track_get_path(i2))
		if not pth2.contains("StandWorkBliz") or not pth2.ends_with(":emitting"):
			continue
		if work.track_get_key_count(i2) < 1:
			continue
		if bool(work.track_get_key_value(i2, 0)):
			work_smoke_on = true
			break
	if not work_smoke_on:
		push_error("test_7 FAIL: Stand Work BlizParticle emitting stays off")
		inst.queue_free()
		return
	var smoke: GPUParticles3D = inst.find_child("StandWorkBlizParticle01", true, false) as GPUParticles3D
	if smoke == null:
		push_error("test_7 FAIL: StandWorkBlizParticle01 missing")
		inst.queue_free()
		return
	if smoke.amount > 32:
		push_error("test_7 FAIL: Work smoke amount=%d want ~30 (rate*life, no 1.35 boost)" % smoke.amount)
		inst.queue_free()
		return
	if smoke.preprocess > 0.05:
		push_error("test_7 FAIL: Work smoke preprocess=%s want 0" % str(smoke.preprocess))
		inst.queue_free()
		return
	var quad := smoke.draw_pass_1 as QuadMesh
	var mat := quad.material as StandardMaterial3D if quad != null else null
	if mat == null or mat.blend_mode != BaseMaterial3D.BLEND_MODE_ADD:
		push_error("test_7 FAIL: Work smoke not additive")
		inst.queue_free()
		return
	if mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		push_error("test_7 FAIL: Work smoke additive dropped alpha fade")
		inst.queue_free()
		return
	var death := _ap_anim(ap, "Death")
	if death == null:
		push_error("test_7 FAIL: missing Death")
		inst.queue_free()
		return
	var names: Dictionary = {}
	var snd_t := -1.0
	var ubr_t := -1.0
	var method_tracks := 0
	for i in range(death.get_track_count()):
		if death.track_get_type(i) != Animation.TYPE_METHOD:
			continue
		method_tracks += 1
		for k in range(death.track_get_key_count(i)):
			var kv: Variant = death.track_get_key_value(i, k)
			if typeof(kv) != TYPE_DICTIONARY:
				continue
			var av: Variant = (kv as Dictionary).get("args", [])
			if typeof(av) != TYPE_ARRAY or (av as Array).is_empty():
				continue
			var ename := str((av as Array)[0])
			names[ename] = true
			var kt := death.track_get_key_time(i, k)
			if ename == "SNDxDHLB":
				snd_t = kt
			elif ename == "UBRxDHLB":
				ubr_t = kt
	if not names.has("SNDxDHLB") or not names.has("UBRxDHLB"):
		push_error("test_7 FAIL: Death events=%s want SNDxDHLB+UBRxDHLB" % str(names.keys()))
		inst.queue_free()
		return
	if method_tracks < 2:
		push_error("test_7 FAIL: Death method tracks=%d want >=2 (same-frame dual fire)" % method_tracks)
		inst.queue_free()
		return
	if snd_t < 0.0 or ubr_t < 0.0 or absf(snd_t - ubr_t) > 1e-5:
		push_error("test_7 FAIL: Death SND/UBR times staggered snd=%s ubr=%s" % [str(snd_t), str(ubr_t)])
		inst.queue_free()
		return
	var omni_on := false
	var omni_off := false
	for i in range(death.get_track_count()):
		if death.track_get_type(i) != Animation.TYPE_VALUE:
			continue
		if not str(death.track_get_path(i)).ends_with("Omni01:visible"):
			continue
		for k in range(death.track_get_key_count(i)):
			if bool(death.track_get_key_value(i, k)):
				omni_on = true
			else:
				omni_off = true
	if not omni_on or not omni_off:
		push_error("test_7 FAIL: Death Omni01 vis missing on/off pulses on=%s off=%s" % [omni_on, omni_off])
		inst.queue_free()
		return
	print(
		"  TownHall Pe2Root gp=%d work_emit_tracks=%d Death fire@%s Omni flash OK"
		% [gp_n, emit_tracks, str(snd_t)]
	)
	passed += 1
	inst.queue_free()


# Test 8: Birth 扬尘 333ms 才 emitting；Portrait 把 Camera01 拉到近景（不是 bind 全身远景）
func _test_townhall_birth_dust_and_portrait_cam() -> void:
	var scn = load("res://assets/asset-converted/Buildings/Human/TownHall/TownHall.scn")
	if scn == null:
		push_error("test_8 FAIL: TownHall scn load null")
		return
	var inst = scn.instantiate()
	if inst == null:
		push_error("test_8 FAIL: instantiate null")
		return
	var dust: GPUParticles3D = null
	for n in inst.find_children("*", "GPUParticles3D", true, false):
		if n is GPUParticles3D and str(n.name).contains("Dust"):
			dust = n as GPUParticles3D
			break
	if dust == null:
		push_error("test_8 FAIL: Birth DustParticles missing")
		inst.queue_free()
		return
	var ap: AnimationPlayer = null
	for c in inst.find_children("*", "AnimationPlayer", true, false):
		if c is AnimationPlayer:
			ap = c
			break
	if ap == null:
		push_error("test_8 FAIL: no AnimationPlayer")
		inst.queue_free()
		return
	var birth := _ap_anim(ap, "Birth")
	if birth == null:
		push_error("test_8 FAIL: missing Birth")
		inst.queue_free()
		return
	var dust_leaf := str(dust.name)
	var t0_on := true
	var t333_on := false
	var found_emit := false
	for i in range(birth.get_track_count()):
		if birth.track_get_type(i) != Animation.TYPE_VALUE:
			continue
		var pth := str(birth.track_get_path(i))
		if not pth.contains(dust_leaf) or not pth.ends_with(":emitting"):
			continue
		found_emit = true
		for k in range(birth.track_get_key_count(i)):
			var t := birth.track_get_key_time(i, k)
			var on := bool(birth.track_get_key_value(i, k))
			if t <= 0.02:
				t0_on = on
			if absf(t - 0.333) <= 0.05:
				t333_on = on
		break
	if not found_emit:
		push_error("test_8 FAIL: Birth missing %s:emitting track" % dust_leaf)
		inst.queue_free()
		return
	if t0_on or not t333_on:
		push_error("test_8 FAIL: Birth dust emitting t0=%s t333=%s want off→on" % [t0_on, t333_on])
		inst.queue_free()
		return
	var cam: Camera3D = inst.find_child("Camera01", true, false) as Camera3D
	if cam == null:
		push_error("test_8 FAIL: Camera01 missing")
		inst.queue_free()
		return
	var bind := Vector3(4.90408, 1.41382, 3.63237)
	if cam.position.distance_to(bind) < 1.5:
		push_error("test_8 FAIL: Camera01 rest still bind wide shot pos=%s" % cam.position)
		inst.queue_free()
		return
	var portrait := _ap_anim(ap, "Portrait -1")
	if portrait == null:
		push_error("test_8 FAIL: missing Portrait -1")
		inst.queue_free()
		return
	var has_pos := false
	for i2 in range(portrait.get_track_count()):
		if portrait.track_get_type(i2) != Animation.TYPE_POSITION_3D:
			continue
		if not str(portrait.track_get_path(i2)).contains("Camera01"):
			continue
		has_pos = true
		if portrait.track_get_key_count(i2) < 1:
			push_error("test_8 FAIL: Portrait Camera01 pos track empty")
			inst.queue_free()
			return
		var p0: Vector3 = portrait.track_get_key_value(i2, 0)
		if p0.distance_to(cam.position) > 0.35:
			push_error("test_8 FAIL: Portrait t0=%s rest=%s" % [p0, cam.position])
			inst.queue_free()
			return
		break
	if not has_pos:
		push_error("test_8 FAIL: Portrait missing Camera01 POSITION_3D")
		inst.queue_free()
		return
	print("  TownHall Birth dust delay + Portrait Camera01 crop OK rest=%s" % cam.position)
	passed += 1
	inst.queue_free()


## 杖尖 Tip 局部 = Weapon Pivot 厘米（与蒙皮 v_model 同空间）。
func _test_archmage_weapon_tip_world() -> void:
	var scn = load("res://assets/asset-converted/Units/Human/HeroArchMage/HeroArchMage.scn")
	if scn == null:
		push_error("test_9 FAIL: HeroArchMage.scn load null")
		return
	var inst = scn.instantiate()
	if inst == null:
		push_error("test_9 FAIL: instantiate null")
		return
	MapModelCache.apply_bone_rest_sidecar(inst, "Units/Human/HeroArchMage/HeroArchMage.gltf")
	var ba: BoneAttachment3D = null
	for c in inst.find_children("*", "BoneAttachment3D", true, false):
		var n := c as BoneAttachment3D
		if n == null:
			continue
		var key := str(n.name).replace(" ", "").to_lower()
		if key.contains("weapon"):
			ba = n
			break
	if ba == null:
		push_error("test_9 FAIL: no Weapon BoneAttachment3D")
		inst.queue_free()
		return
	var tip := ba.get_node_or_null("Tip") as Node3D
	if tip == null:
		push_error("test_9 FAIL: Weapon Tip missing")
		inst.queue_free()
		return
	var want_local := Vector3(65.32, 133.28, 47.37)
	if tip.position.distance_to(want_local) > 2.0:
		push_error("test_9 FAIL: Weapon Tip local=%s want≈%s (model cm)" % [tip.position, want_local])
		inst.queue_free()
		return
	print("  ArchMage Weapon Tip local=%s (pivot cm≈%s)" % [tip.position, want_local])
	var glow := tip.get_node_or_null("TeamGlowBillboard") as Node3D
	if glow == null:
		push_error("test_9 FAIL: TeamGlowBillboard not under Tip")
		inst.queue_free()
		return
	if glow.position.length() > 0.05:
		push_error("test_9 FAIL: TeamGlowBillboard local=%s want 0" % glow.position)
		inst.queue_free()
		return
	var pe := tip.get_node_or_null("BlizParticle01") as Node3D
	if pe == null:
		push_error("test_9 FAIL: BlizParticle01 not under Tip")
		inst.queue_free()
		return
	if pe.position.length() > 0.05:
		push_error("test_9 FAIL: BlizParticle01 local=%s want 0" % pe.position)
		inst.queue_free()
		return
	print("  ArchMage Tip children glow+BlizParticle01 identity OK")
	passed += 1
	inst.queue_free()


func _ap_anim(ap: AnimationPlayer, leaf: String) -> Animation:
	if ap == null:
		return null
	if ap.has_animation(leaf):
		return ap.get_animation(leaf)
	var want := AnimPlayback.compact_seq_name(leaf)
	for n in ap.get_animation_list():
		if AnimPlayback.compact_seq_name(str(n)) == want:
			return ap.get_animation(str(n))
	return null
