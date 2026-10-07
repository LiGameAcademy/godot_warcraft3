extends RefCounted
## 发布游戏内验证真实模型：普攻收招/杖尖、建筑 Death→Decay→清理。
var failures: int = 0
var evidence: Dictionary = {}

func run(game: GameMain, capture: String) -> int:
	var host: MapUnitLayer = game.map_root.get_unit_layer()
	var caster: Unit = null
	var seed: Dictionary = {}
	for child: Node in host.get_children():
		var data: Dictionary = child.get_meta("unit_data", {})
		if data.get("typeId") == "Hamg" and int(data.get("owner", -1)) == 0:
			caster = child as Unit
			seed = data.duplicate(true)
	_check(caster != null, "Native Archmage found for combat review")
	if caster == null:
		return failures
	var module: CombatModule = game.game_director.get_node("CombatModule") as CombatModule
	await _attack(game, module, caster, capture)
	await _building(game, module, seed, capture)
	var file: FileAccess = FileAccess.open(capture.get_basename() + "-combat.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "  "))
	print("COMBAT_REVIEW " + JSON.stringify(evidence))
	return failures

func _attack(game: GameMain, module: CombatModule, caster: Unit, capture: String) -> void:
	var attack: AttackController = module.ensure_attack_controller(caster)
	attack.cancel()
	var player: AnimationPlayer = AnimPlayback.find_animation_player(caster.model_node())
	var previous: int = player.callback_mode_process
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	attack.set_process(false)
	var target: Node3D = Node3D.new()
	target.set_meta("unit_data", {"typeId": "hfoo", "owner": 1})
	target.set_meta("life", 420.0)
	game.map_root.get_unit_layer().add_child(target)
	target.global_position = caster.global_position + Vector3(3, 0, 0)
	var launches: Array[Dictionary] = []
	var record: Callable = func(info: Dictionary) -> void:
		if info.get("attacker") == caster:
			launches.append(info.duplicate(true))
	module.projectile_service.projectile_launched.connect(record)
	attack._target = target
	attack._mode = AttackController.Mode.ATTACK
	attack._begin_windup()
	var clip: String = player.current_animation
	var length: float = player.current_animation_length
	var damage_point: float = CombatQuery.damage_point_sec(caster)
	player.advance(damage_point)
	attack._tick_windup(damage_point + 0.01)
	_check(launches.size() == 1, "Exactly one fireball launched at damage point")
	_check(player.is_playing() and player.current_animation == clip, "Native Attack retains recovery after launch")
	var socket: Node3D = CombatProjectileOrigin._weapon_socket(caster.model_node())
	_check(socket != null and socket.has_meta("import_socket"), "Native Weapon Ref resolves to pivot Marker, not bone origin")
	if not launches.is_empty() and socket != null:
		var info: Dictionary = launches[0]
		var shell: Node3D = game.map_root.get_unit_layer().get_node_or_null("CombatProjectileShell_%s" % str(info.id)) as Node3D
		_check(shell != null and shell.global_position.distance_to(socket.global_position) < 0.001, "Fireball begins at animated staff tip")
		_check(info.from_wc3 == info.pos_wc3, "Presentation did not mutate logical launch position")
		var samples: Array[Dictionary] = []
		for yaw: float in [0.0, PI * 0.5, PI]:
			caster.rotation.y = yaw
			var start: Vector3 = CombatProjectileOrigin.weapon_start_wc3(caster, Vector3.ZERO)
			_check(start.distance_to(Wc3Coords.godot_to_wc3(socket.global_position)) < 0.01, "Native staff pivot follows facing")
			samples.append({"yaw": yaw, "start_wc3": str(start)})
		evidence.attack = {"clip": clip, "length": length, "damage_point": damage_point,
			"logical_from": str(info.from_wc3), "staff_tip_after_facing_samples": str(socket.global_position), "facing_samples": samples}
	player.advance(length - damage_point + 0.05)
	_check(player.assigned_animation != StringName(clip), "Native attack finishes into idle")
	attack._begin_windup()
	_check(player.current_animation == clip and player.current_animation_position == 0.0, "Native next strike restarts")
	attack.cancel()
	player.callback_mode_process = previous
	attack.set_process(true)
	module.projectile_service.projectile_launched.disconnect(record)
	WorldMembership.exit(target)
	# Dummy target stays allocated until the fixture exits, so queued impact callbacks are valid.
	await _save(game, capture.get_basename() + "-attack.png")

func _building(game: GameMain, module: CombatModule, seed: Dictionary, capture: String) -> void:
	seed.typeId = "hhou"
	seed.creationNumber = 97999
	seed.position.x = float(seed.position.x) + 256.0
	seed.position.y = float(seed.position.y) + 256.0
	var farm: Unit = game.map_root.add_unit_instance(seed, game.map_root.get_heightfield_dict()) as Unit
	_check(farm != null, "Native farm spawned")
	if farm == null:
		return
	var model: Node3D = farm.model_node()
	var player: AnimationPlayer = AnimPlayback.find_animation_player(model)
	var decals: Array[Node] = farm.find_children("*", "Decal", true, false)
	_check(not decals.is_empty(), "Building has runtime ground decal before death")
	var fade_seconds: float = 0.0
	for node: Node in decals:
		fade_seconds = maxf(fade_seconds, float(node.get_meta("uber_splat_decay_seconds", 0.0)))
	var settings: BuildingDeathSettings = BuildingDeathSettings.from_source()
	module.kill(farm)
	_check(AnimPlayback.compact_seq_name(player.current_animation).begins_with("death"), "Building uses native destruction animation")
	var death_seconds: float = player.current_animation_length
	await _wait(game, 0.6)
	await _save(game, capture.get_basename() + "-building-death.png")
	await _wait(game, death_seconds + 2.5)
	_check(is_instance_valid(farm), "Building retains corpse after Death")
	if not is_instance_valid(farm):
		return
	_check(AnimPlayback.compact_seq_name(player.current_animation).begins_with("decay"), "Death transitions into native Decay")
	_check(is_equal_approx(player.current_animation_length / player.speed_scale, settings.corpse_seconds), "Source StructureDecayTime controls real corpse duration")
	for node: Node in farm.find_children("*", "Decal", true, false):
		_check(bool(node.get_meta("death_fading", false)) and (node as Decal).modulate.a < 1.0, "Runtime ground is fading during corpse")
	evidence.building = {"death_seconds": death_seconds, "decay_clip_seconds": player.current_animation_length,
		"corpse_seconds": settings.corpse_seconds, "speed_scale": player.speed_scale, "ground_fade_seconds": fade_seconds}
	await _save(game, capture.get_basename() + "-building-corpse.png")
	await _wait(game, fade_seconds + 0.5)
	_check(is_instance_valid(farm) and farm.find_children("*", "Decal", true, false).is_empty(), "Source ground fade finishes before corpse removal")
	evidence.building.ground_cleaned = is_instance_valid(farm) and farm.find_children("*", "Decal", true, false).is_empty()
	await _save(game, capture.get_basename() + "-building-ground-cleared.png")
	await _wait(game, maxf(settings.corpse_seconds - fade_seconds, 0.0) + 0.5)
	_check(not is_instance_valid(farm), "Native corpse and all emitter children expire")
	evidence.building.cleaned = not is_instance_valid(farm)
	evidence.failures = failures
	await _save(game, capture.get_basename() + "-building-cleared.png")

func _wait(game: GameMain, seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		await game.get_tree().process_frame
		elapsed += game.get_process_delta_time()

func _save(game: GameMain, path: String) -> void:
	await RenderingServer.frame_post_draw
	_check(game.get_viewport().get_texture().get_image().save_png(path) == OK, "Combat capture: " + path)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
