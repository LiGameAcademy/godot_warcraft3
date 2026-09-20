extends SceneTree

## 金矿塌陷烟：空 active_sequences 不得推断成 Stand 常开。
## godot --headless --path . -s res://tests/unit/selftest_pe2_goldmine_smoke.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_infer_death_not_stand()
	_test_ensure_no_all_fallback_when_vis_inert()
	_test_goldmine_payload_stand_off()
	if failed == 0:
		print("selftest_pe2_goldmine_smoke: PASS")
		quit(0)
	else:
		push_error("selftest_pe2_goldmine_smoke: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _goldmine_sequences() -> Array:
	return [
		{"name": "Stand", "interval": [333, 3333]},
		{"name": "Stand Work", "interval": [6633, 7400]},
		{"name": "Birth", "interval": [9967, 69967]},
		{"name": "Death", "interval": [74967, 76200]},
		{"name": "Decay", "interval": [76633, 136633]},
	]


func _explosion_smoke_em() -> Dictionary:
	return {
		"name": "BlizParticleExplosionSmoke",
		"active_sequences": [],
		"emission_rate": 165.97,
		"visibility_keys": [
			{"frame": 9967, "value": 0},
			{"frame": 74967, "value": 0},
			{"frame": 76633, "value": 0},
		],
		"emission_rate_keys": [
			{"frame": 0, "value": 0},
			{"frame": 74967, "value": 0},
			{"frame": 75067, "value": 0},
			{"frame": 75100, "value": 60},
			{"frame": 75133, "value": 165.97},
			{"frame": 75200, "value": 63.0},
			{"frame": 75433, "value": 61.0},
			{"frame": 75467, "value": 0},
			{"frame": 75500, "value": 0},
		],
	}


func _test_infer_death_not_stand() -> void:
	var inferred: Array = Wc3Pe2Particles._infer_active_sequences(
		_explosion_smoke_em(), _goldmine_sequences()
	)
	var names: PackedStringArray = PackedStringArray()
	for n in inferred:
		names.append(str(n))
	if names.has("Stand") or names.has("Stand Work") or names.has("Birth"):
		_fail("塌陷烟不应推断出 Stand/Work/Birth，实际 %s" % str(names))
		return
	if not names.has("Death"):
		_fail("塌陷烟应推断出 Death，实际 %s" % str(names))
		return
	print("  infer_death_not_stand OK %s" % str(names))


func _test_ensure_no_all_fallback_when_vis_inert() -> void:
	# rate 全 0 → 推断空；vis inert → 不得兜底全程
	var em := {
		"active_sequences": [],
		"emission_rate": 0.0,
		"visibility_keys": [{"frame": 100, "value": 0}],
		"emission_rate_keys": [{"frame": 100, "value": 0}],
	}
	Wc3Pe2Particles._ensure_active_sequences(em, _goldmine_sequences())
	var active: Array = em.get("active_sequences", [])
	if not active.is_empty():
		_fail("vis inert 且无 rate 脉冲时不得兜底全程，实际 %s" % str(active))
		return
	print("  ensure_no_all_fallback OK")


func _test_goldmine_payload_stand_off() -> void:
	var path := "res://assets/asset-converted/Buildings/Other/GoldMine/Goldmine.gltf"
	if not Wc3Pe2Particles.has_emitters(path):
		_fail("GoldMine 应有 pe2")
		return
	var cache := MapModelCache.new()
	var root := cache.instance_glb(path, true)
	if root == null:
		_fail("instance_glb GoldMine 失败")
		return
	get_root().add_child(root)
	cache.autoplay_stand(root)
	BuildingVisual.apply_idle(cache, root, "ngol")
	Wc3Pe2Particles.attach_to(root, path)
	Wc3Pe2Particles.apply_sequence(root, "Stand")
	for n in root.find_children("*", "GPUParticles3D", true, false):
		var p := n as GPUParticles3D
		var nm := str(p.name)
		if nm == "BlizParticleExplosion02" or nm == "BlizParticleExplosionSmoke":
			if p.emitting:
				_fail("%s 在 Stand 不得 emitting" % nm)
	print("  goldmine_payload_stand_off OK")
	root.queue_free()
