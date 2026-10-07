extends RefCounted
## Exercise the real cast controller, published scenes and gameplay presentation.
const FxScene: GDScript = preload("res://packages/gameplay/presentation/ability_fx_scene.gd")
const AuraReview: GDScript = preload("res://tmp/development_aura_review.gd")
var failures: int = 0
var _frames: Array[float] = []
var _phases: Array[Dictionary] = []
var _instances: Array[Dictionary] = []
var _summon_transitions: Array[Dictionary] = []

func run(game: GameMain, capture: String) -> int:
	var caster: Node3D = null
	var host: MapUnitLayer = game.map_root.get_unit_layer()
	for actor: Node in host.get_children():
		var data: Dictionary = actor.get_meta("unit_data", {})
		if data.get("typeId", "") == "Hamg" and int(data.get("owner", -1)) == 0:
			caster = actor as Node3D
			break
	_check(caster != null, "Review Archmage exists")
	if caster == null:
		return failures
	var abilities: AbilitiesModule = game.game_director.get_node("AbilitiesModule") as AbilitiesModule
	var controller: AbilityCastController = AbilityCastController.ensure_on(caster)
	caster.set_meta("ability_levels", {"AHwe": 1, "AHbz": 1, "AHmt": 1})
	for level: int in range(1, 4):
		caster.set_meta("ability_levels", {"AHwe": level, "AHbz": 1, "AHmt": 1})
		UnitMana.regenerate(caster, 1000)
		AbilityCooldowns.start(caster, "AHwe", 0.0)
		_check(bool(controller.begin_cast("AHwe", Vector2.INF, abilities.cast_context()).get("ok", false)), "Real summon cast level %d" % level)
		await _wait(game, 0.6)
		var id: String = ["hwat", "hwt2", "hwt3"][level-1]
		var summon: Node3D = null
		for actor: Node in host.get_children():
			if actor.get_meta("unit_data", {}).get("typeId", "") == id:
				summon = actor as Node3D
		_check(summon != null, "Summon created: " + id)
		if summon != null:
			var model: Node3D = summon.get_node_or_null("Model") as Node3D
			_check(CompiledModelPresentation.is_compiled(model), "Summon uses compiled model, not placeholder: " + id)
			_check(AnimPlayback.find_animation_player(model) != null, "Summon has native animation: " + id)
			game.unit_selector.select_node(summon)
			await _wait_portrait(game, id)
			await _wait_summon_idle(game, caster, model, id)
		await _save(game, capture.get_basename() + "-water-%d.png" % level)
	var goal: Vector2 = Wc3Coords.godot_to_wc3_xy(caster.global_position) + Vector2(-180.0, -200.0)
	game.unit_selector.select_node(caster)
	await _benchmark_instances(game)
	var loads: int = FxScene.scene_loads
	var blizzard_loads: Dictionary = _blizzard_loads()
	for cast: int in range(2):
		var first_frame: int = _frames.size()
		UnitMana.regenerate(caster, 1000)
		AbilityCooldowns.start(caster, "AHbz", 0.0)
		_check(bool(controller.begin_cast("AHbz", goal, abilities.cast_context()).get("ok", false)), "Real Blizzard channel")
		await _wait(game, 1.2)
		var channel_player: AnimationPlayer = AnimPlayback.find_animation_player(caster.get_node("Model"))
		_check(AnimPlayback.compact_seq_name(channel_player.current_animation) == "standchannel", "Blizzard uses dedicated Stand Channel")
		_check(channel_player.is_playing() and channel_player.get_animation(channel_player.current_animation).loop_mode == Animation.LOOP_LINEAR, "Channel animation loops while casting")
		var shards: Array[AbilityGroundFx] = _ground_effects(game)
		var per_wave: int = clampi(int(round(AbilityCatalog.data("AHbz").data_c_at(1))), 2, 6)
		_check(shards.size() >= per_wave, "Blizzard creates configured source shards")
		for shard: AbilityGroundFx in shards:
			var model: Node3D = shard.get("_inst") as Node3D
			_check(CompiledModelPresentation.is_compiled(model), "Ground FX bypass legacy sanitizers")
			_check(model.find_children("*", "GPUParticles3D", true, false).size() == 5, "All Blizzard emitters, including impact bursts, survive")
		var hits: Array[Node] = game.map_root.find_children("*", "SpellHitFx", true, false)
		_check(not hits.is_empty(), "Blizzard creates actual hit effects")
		for hit: Node in hits:
			_check(CompiledModelPresentation.is_compiled(hit.get("_inst") as Node3D), "Hit FX bypass legacy mesh rebuilding")
		if cast == 0:
			await _save(game, capture.get_basename() + "-blizzard.png")
		await _wait(game, 0.7)
		_check(channel_player.is_playing() and AnimPlayback.compact_seq_name(channel_player.current_animation) == "standchannel", "Casting survives a second source animation cycle")
		if cast == 0:
			await _save(game, capture.get_basename() + "-blizzard-impact.png")
		await _wait(game, 2.9)
		_check(not controller.is_channeling(), "Blizzard channel finishes normally")
		_check(AnimPlayback.compact_seq_name(channel_player.assigned_animation) != "standchannel", "Finished Blizzard releases casting animation")
		_phases.append({"name": "blizzard_%d" % (cast+1), "timings": _timings(_frames.slice(first_frame))})
	_check(_blizzard_loads() == blizzard_loads, "Repeated waves/casts do not reload Blizzard or FrostDamage scenes")
	UnitMana.regenerate(caster, 1000)
	AbilityCooldowns.start(caster, "AHmt", 0.0)
	var destination: Vector2 = Wc3Coords.godot_to_wc3_xy(caster.global_position) + Vector2(-320.0, -160.0)
	var before: Vector3 = caster.global_position
	_check(bool(controller.begin_cast("AHmt", destination, abilities.cast_context()).get("ok", false)), "Real Mass Teleport cast")
	await _wait(game, 1.0)
	var attached: Node3D = caster.get_node_or_null("MassTeleportCasterFx") as Node3D
	_check(CompiledModelPresentation.is_compiled(attached), "Teleport caster visual exists during channel")
	_check(attached != null and attached.get_meta("teleport_material_policy", "") == TeleportEffectPresentation.POLICY, "Teleport caster uses logged gameplay brightness enhancement")
	var marker: Node = game.map_root.get_node_or_null("MassTeleportDestMarker")
	var decal: Decal = marker.get_node_or_null("Decal") as Decal if marker != null else null
	_check(decal != null and decal.lower_fade == 0.0 and decal.upper_fade == 0.0, "Teleport preview retains visibility across projection depth")
	await _save(game, capture.get_basename() + "-teleport-cast.png")
	await _wait(game, 2.6)
	_check(caster.global_position.distance_to(before) > 0.5, "Teleport moves caster")
	_check(caster.get_node_or_null("MassTeleportCasterFx") == null, "Channel caster FX cleaned")
	var arrivals: Array[AbilityGroundFx] = _ground_effects(game)
	_check(not arrivals.is_empty(), "Teleport departure/arrival source scenes exist")
	for arrival: AbilityGroundFx in arrivals:
		var root: Node3D = arrival.get("_inst") as Node3D
		_check(root != null and root.get_meta("teleport_material_policy", "") == TeleportEffectPresentation.POLICY, "Teleport departure/arrival brightness policy applied")
	await _save(game, capture.get_basename() + "-teleport-arrival.png")
	await _wait(game, 6.0)
	_check(_ground_effects(game).is_empty(), "Ground effects finish Death and clean up")
	UnitMana.regenerate(caster, 1000)
	AbilityCooldowns.start(caster, "AHmt", 0.0)
	_check(bool(controller.begin_cast("AHmt", destination, abilities.cast_context()).get("ok", false)), "Cancelable teleport begins")
	controller.cancel_cast()
	await _wait(game, 0.1)
	_check(caster.get_node_or_null("MassTeleportCasterFx") == null, "Canceled teleport clears caster FX")
	_check(game.map_root.get_node_or_null("MassTeleportDestMarker") == null, "Canceled teleport clears destination preview")
	var aura: Dictionary = await AuraReview.new().run(game, caster, capture)
	failures += int(aura.get("failures", 1))
	var stats: Dictionary = _timings(_frames)
	stats["aura"] = aura
	stats.merge({"scene_loads_before_casts": loads, "scene_loads_after_casts": FxScene.scene_loads, "phases": _phases, "instance_setup": _instances, "summon_transitions": _summon_transitions, "blizzard_loads_before": blizzard_loads, "blizzard_loads_after": _blizzard_loads(), "failures": failures, "visual": "requires_original_game_comparison"})
	var file: FileAccess = FileAccess.open(capture.get_basename() + "-spells.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(stats, "  "))
	print("SPELL_REVIEW " + JSON.stringify(stats))
	return failures

func _wait(game: GameMain, seconds: float) -> void:
	# Gameplay timers use frame delta; wall-clock waits race channels after long frames.
	var elapsed: float = 0.0
	var deadline: int = Time.get_ticks_usec() + 120000000
	var previous: int = Time.get_ticks_usec()
	while elapsed < seconds and Time.get_ticks_usec() < deadline:
		await game.get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		_frames.append(float(now-previous)/1000.0)
		previous = now
		elapsed += game.get_process_delta_time()
	_check(elapsed >= seconds, "Gameplay wait timed out: %.2f seconds" % seconds)

func _save(game: GameMain, path: String) -> void:
	await RenderingServer.frame_post_draw
	_check(game.get_viewport().get_texture().get_image().save_png(path) == OK, "Spell screenshot " + path)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _timings(frames: Array[float]) -> Dictionary:
	var sorted: Array[float] = frames.duplicate()
	sorted.sort()
	return {"frames": sorted.size(), "median_ms": sorted[int(sorted.size()/2)], "p95_ms": sorted[int(sorted.size()*0.95)], "max_ms": sorted.back()}

func _ground_effects(game: GameMain) -> Array[AbilityGroundFx]:
	var effects: Array[AbilityGroundFx] = []
	for child: Node in game.map_root.get_children():
		if child is AbilityGroundFx:
			effects.append(child as AbilityGroundFx)
	return effects

func _benchmark_instances(game: GameMain) -> void:
	var art: String = AbilityFxCatalog.ground_effect_art("AHbz")
	for index: int in range(3):
		var start: int = Time.get_ticks_usec()
		var root: Node3D = FxScene.instantiate(art, game.map_root.get_model_cache())
		var instantiated: int = Time.get_ticks_usec()
		game.map_root.add_child(root)
		FxScene.play(root, "Birth")
		var ready: int = Time.get_ticks_usec()
		_instances.append({"instance_ms": float(instantiated-start)/1000.0, "setup_ms": float(ready-instantiated)/1000.0})
		await game.get_tree().process_frame
		root.queue_free()
		await game.get_tree().process_frame

func _blizzard_loads() -> Dictionary:
	return {"ground": FxScene.load_count(AbilityFxCatalog.ground_effect_art("AHbz")), "hit": FxScene.load_count(AbilityFxCatalog.hit_effect_art("AHbz"))}

func _wait_portrait(game: GameMain, id: String) -> void:
	await game.get_tree().process_frame
	for control: Node in game.game_hud.find_children("*", "Control", true, false):
		if control is UnitPortraitView:
			var view: UnitPortraitView = control as UnitPortraitView
			var deadline: int = Time.get_ticks_msec() + 15000
			while view._settled_gen != view._load_gen and Time.get_ticks_msec() < deadline:
				await game.get_tree().process_frame
			await game.get_tree().create_timer(0.5).timeout
			_check(CompiledModelPresentation.is_compiled(view._model_root), "Summon portrait uses compiled source: " + id)
			return
	_check(false, "Summon portrait UI exists: " + id)

func _wait_summon_idle(game: GameMain, caster: Node3D, model: Node3D, id: String) -> void:
	var ap: AnimationPlayer = AnimPlayback.find_animation_player(model)
	var caster_ap: AnimationPlayer = AnimPlayback.find_animation_player(caster)
	if ap == null or caster_ap == null:
		_check(false, "Summon and caster animation players exist")
		return
	var birth: String = AnimPlayback.resolve(model, "Birth", ap)
	var spell: String = AnimPlayback.resolve(caster, "Spell", caster_ap)
	if birth.is_empty() or spell.is_empty():
		_check(false, "Birth and Spell clips resolve")
		return
	var birth_clip: Animation = ap.get_animation(birth)
	var spell_clip: Animation = caster_ap.get_animation(spell)
	_check(birth_clip.loop_mode == Animation.LOOP_NONE, "Summon Birth remains single play: " + id)
	_check(spell_clip.loop_mode == Animation.LOOP_NONE, "Summon gesture remains single play")
	var deadline: int = Time.get_ticks_msec() + 8000
	while (ap.current_animation == birth or bool(caster.get("_spell_casting"))) and Time.get_ticks_msec() < deadline:
		await _wait(game, 0.1)
	_check(AnimPlayback.compact_seq_name(ap.current_animation).begins_with("stand"), "Birth finishes into Stand: " + id)
	_check(not bool(caster.get("_spell_casting")), "Caster exits spell gesture: " + id)
	_check(not AnimPlayback.compact_seq_name(caster_ap.current_animation).begins_with("spell"), "Caster leaves Spell: " + id)
	# Observe another Birth-length interval to catch repeated/restarted birth phases.
	await _wait(game, birth_clip.length + 0.2)
	_check(ap.current_animation != birth, "Summon does not restart Birth: " + id)
	_check(not bool(caster.get("_spell_casting")), "Caster remains released after summon: " + id)
	_summon_transitions.append({"unit": id, "birth_seconds": birth_clip.length, "spell_seconds": spell_clip.length,
		"summon_animation": ap.current_animation, "caster_animation": caster_ap.current_animation,
		"caster_spell_casting": bool(caster.get("_spell_casting"))})
