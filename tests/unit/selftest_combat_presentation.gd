extends Node
## 攻击伤害帧/收招、引导循环、挂点与建筑消散的行为回归。
class ProbePipeline extends DamagePipeline:
	var strikes: int = 0
	var fatal: bool = false
	func apply(_request: Dictionary) -> Dictionary:
		strikes += 1
		return {"killed": fatal}

var _failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var attacker: Unit = _actor("hfoo", 0)
	var target: Unit = _actor("hfoo", 1)
	target.position.x = 0.3
	var player: AnimationPlayer = AnimPlayback.find_animation_player(attacker.model_node())
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var pipeline: ProbePipeline = ProbePipeline.new()
	var attack: AttackController = AttackController.new()
	attacker.add_child(attack)
	attack.configure(Callable(), Callable(), pipeline)
	attack.set_process(false)
	attack._target = target
	attack._mode = AttackController.Mode.ATTACK
	attack._begin_windup()
	player.advance(0.4)
	attack._resolve_strike()
	_check(pipeline.strikes == 1, "Damage resolves once at damage point")
	_check(player.assigned_animation == &"Attack" and player.is_playing(), "Damage point does not cut recovery")
	player.advance(1.1)
	_check(player.assigned_animation == &"Stand", "Finished attack returns to idle")
	attack._begin_windup()
	_check(player.current_animation == "Attack" and player.current_animation_position == 0.0, "Next strike restarts Attack")
	attack.cancel()
	pipeline.fatal = true
	attack._target = target
	attack._mode = AttackController.Mode.ATTACK
	attack._begin_windup()
	player.advance(0.4)
	attack._resolve_strike()
	_check(attack.get_state() == AttackController.State.IDLE and player.current_animation == "Attack", "Killing blow ends order while preserving recovery")
	player.advance(1.1)
	_check(player.assigned_animation == &"Stand", "Killing blow finishes normally")
	pipeline.fatal = false
	AbilityCastPresenter.begin(attacker, "AHbz", true, Vector2.INF)
	_check(player.current_animation == "StandChannel", "Blizzard selects dedicated channel sequence")
	player.advance(3.3)
	_check(player.is_playing() and player.assigned_animation == &"StandChannel", "Channel remains active across multiple loops")
	AbilityCastPresenter.end(attacker)
	_check(player.assigned_animation == &"Stand", "Channel end releases animation")
	AbilityCastPresenter.begin(attacker, "AHwe", false, Vector2.INF)
	_check(player.current_animation == "Spell" and player.get_animation("Spell").loop_mode == Animation.LOOP_NONE, "Summon stays single play")
	player.advance(3.0)
	_check(player.assigned_animation == &"Stand", "Gesture completion survives old attack callbacks")
	var socket: Marker3D = attacker.model_node().get_node("WeaponOrigin/Tip") as Marker3D
	for yaw: float in [0.0, PI * 0.5, PI]:
		attacker.rotation.y = yaw
		attacker.position = Vector3(4, 2, -5)
		attacker.model_node().scale = Vector3.ONE * 1.25
		var actual: Vector3 = CombatProjectileOrigin.weapon_start_wc3(attacker, Vector3.ZERO)
		_check(actual.is_equal_approx(Wc3Coords.godot_to_wc3(socket.global_position)), "Weapon Tip respects position/rotation/scale")
	_check(CombatProjectileOrigin.weapon_start_wc3(target, Vector3(1, 2, 3)) != Vector3(1, 2, 3), "Existing socket overrides fallback")
	var bare: Node3D = Node3D.new()
	add_child(bare)
	_check(CombatProjectileOrigin.weapon_start_wc3(bare, Vector3(1, 2, 3)) == Vector3(1, 2, 3), "Missing socket keeps logic fallback")
	bare.free()
	var building: Unit = _actor("hbar", 0)
	var model: Node3D = building.model_node()
	var decal: Decal = Decal.new()
	decal.set_meta("is_runtime_uber_splat", true)
	decal.set_meta("uber_splat_decay_seconds", 0.05)
	building.add_child(decal)
	var settings: BuildingDeathSettings = BuildingDeathSettings.new()
	settings.corpse_seconds = 0.3
	var bp: AnimationPlayer = AnimPlayback.find_animation_player(model)
	bp.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	BuildingDeathPresentation.prepare(building, settings)
	building.play_death()
	_check(bp.current_animation == "Death" and bp.speed_scale == 1.0, "Building Death retains source speed")
	bp.advance(0.11)
	_check(bp.current_animation == "Decay", "Death transitions into corpse")
	_check(is_equal_approx(bp.speed_scale, 0.2 / 0.3), "Decay retimed to configured lifetime")
	var settings_before: float = settings.corpse_seconds
	await get_tree().create_timer(0.15).timeout
	await get_tree().process_frame
	_check(not is_instance_valid(decal), "Ground decal fades and is freed during corpse")
	_check(is_instance_valid(building), "Removing ground decal preserves corpse")
	bp.advance(0.31)
	await get_tree().process_frame
	_check(not is_instance_valid(building), "Corpse and child FX removed at end")
	_check(settings.corpse_seconds == settings_before, "Read-only settings remain unchanged")
	attacker.free()
	target.free()
	print("PASS: combat recovery, channel, sockets and building corpse" if _failures == 0 else "FAIL: combat presentation %d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

func _actor(type_id: String, owner: int) -> Unit:
	var actor: Unit = Unit.new()
	actor.set_meta("unit_data", {"typeId": type_id, "owner": owner})
	actor.set_meta("life", 420.0)
	var model: Node3D = Node3D.new()
	model.name = "Model"
	actor.add_child(model)
	var origin: Node3D = Node3D.new()
	origin.name = "WeaponOrigin"
	origin.position = Vector3(0.1, 0.5, 0.2)
	model.add_child(origin)
	var tip: Marker3D = Marker3D.new()
	tip.name = "Tip"
	tip.position.y = 0.5
	tip.set_meta("import_socket", "Weapon Ref")
	origin.add_child(tip)
	var player: AnimationPlayer = AnimationPlayer.new()
	model.add_child(player)
	var library: AnimationLibrary = AnimationLibrary.new()
	for name: String in ["Stand", "Attack", "Spell", "StandChannel", "Death", "Decay"]:
		var clip: Animation = Animation.new()
		clip.length = {"Attack": 1.4, "Spell": 2.7, "Death": 0.1, "Decay": 0.2}.get(name, 1.0)
		clip.set_meta("source_looping", name in ["Stand", "StandChannel"])
		library.add_animation(name, clip)
	player.add_animation_library("", library)
	add_child(actor)
	actor.bind_animation_player(player)
	return actor

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
