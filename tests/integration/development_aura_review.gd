extends RefCounted
## 发布游戏内：普通学习自动生效、原生光圈、范围/死亡清理与再次进入。
var failures: int = 0

func run(game: GameMain, caster: Node3D, capture: String) -> Dictionary:
	var host: MapUnitLayer = game.map_root.get_unit_layer()
	var priest: Node3D = null
	for actor: Node in host.get_children():
		if CombatQuery.type_id_of(actor) == "hmpr" and CombatQuery.owner_of(actor) == CombatQuery.owner_of(caster):
			priest = actor as Node3D
			break
	_check(priest != null, "Aura review priest exists")
	if priest == null:
		return {"failures": failures}
	var saved_levels: Dictionary = HeroSkill.ability_levels(caster).duplicate()
	var saved_level: int = AbilityCatalog.hero_level_of(caster)
	var saved_life: float = UnitLife.get_life(caster)
	var saved_position: Vector3 = priest.global_position
	var hf: Wc3Heightfield = Wc3Heightfield.from_dict(game.map_root.get_heightfield_dict(), false)
	priest.global_position = _ground(hf, caster.global_position + Vector3(0, 0, 2))
	caster.set_meta(AbilityCatalog.META_ABILITY_LEVELS, {})
	caster.set_meta(AbilityCatalog.META_HERO_LEVEL, 1)
	await _settle(game)
	var ctrl: BrillianceAuraController = BrillianceAuraController.of(caster)
	_check(ctrl != null and ctrl.is_processing(), "Unlearned controller observes ordinary learning")
	if ctrl == null:
		return {"failures": failures}
	_check(BuffQuery.mana_regen_bonus(priest) == 0.0 and not ctrl._beneficiary_fx.has(priest.get_instance_id()), "Unlearned aura grants no buff or circle")
	_check(bool(HeroSkill.learn(caster, "AHab").get("ok", false)), "Learn through ordinary skill logic without runtime reconfigure")
	await _settle(game)
	_check(is_equal_approx(BuffQuery.mana_regen_bonus(priest), 0.75), "Learning grants actual priest regen bonus")
	var fx: Node3D = ctrl._beneficiary_fx.get(priest.get_instance_id()) as Node3D
	_check(CompiledModelPresentation.is_compiled(fx), "Beneficiary uses published native SCN")
	var animation: String = ""
	var policy: String = ""
	if fx != null:
		var player: AnimationPlayer = AnimPlayback.find_animation_player(fx)
		_check(player != null and player.is_playing(), "Beneficiary source Stand plays")
		if player != null:
			animation = player.current_animation
			_check(player.get_animation(animation).loop_mode == Animation.LOOP_LINEAR, "Beneficiary Stand loops")
		policy = str(fx.get_meta("aura_beneficiary_policy", ""))
		_check(policy == AuraBeneficiaryPresentation.POLICY, "Readable beneficiary policy applied")
		_check(fx.get_parent() == priest and fx.scale.is_equal_approx(Vector3.ONE), "Circle follows entity without double MODEL_SCALE")
	# 开发地图开局的敌人没有蓝；从真实牧师配置生成原生敌方模型补齐样本。
	var enemy_data: Dictionary = priest.get_meta("unit_data", {}).duplicate(true)
	enemy_data["owner"] = 1 - CombatQuery.owner_of(caster)
	enemy_data["creationNumber"] = 99091
	var enemy_point: Vector2 = Wc3Coords.godot_to_wc3_xy(caster.global_position) + Vector2(128, 128)
	enemy_data["position"] = {"x": enemy_point.x, "y": enemy_point.y, "z": 0.0}
	var enemy: Node3D = game.map_root.add_unit_instance(enemy_data, game.map_root.get_heightfield_dict())
	_check(enemy is Unit, "Enemy aura sample uses actual Unit lifecycle")
	if enemy != null:
		UnitMana.ensure(enemy)
	await _settle(game)
	var checked_footman: bool = false
	var checked_enemy: bool = false
	for actor: Node in host.get_children():
		if CombatQuery.type_id_of(actor) == "hfoo" and CombatQuery.owner_of(actor) == CombatQuery.owner_of(caster):
			checked_footman = true
			_check(not ctrl._beneficiary_fx.has(actor.get_instance_id()), "Actual no-mana footman receives no circle")
		elif CombatQuery.owner_of(actor) == 1 - CombatQuery.owner_of(caster) and UnitMana.has_mana(actor as Node3D):
			checked_enemy = true
			_check(not ctrl._beneficiary_fx.has(actor.get_instance_id()), "Actual enemy receives no circle")
	_check(checked_footman and checked_enemy, "Actual footman and enemy samples present")
	if enemy != null:
		enemy.queue_free()
	await _settle(game)
	game.unit_selector.select_node(priest)
	await _save(game, capture.get_basename() + "-aura-beneficiary.png")
	var elapsed: float = 0.0
	while elapsed < 2.4:
		await game.get_tree().process_frame
		elapsed += game.get_process_delta_time()
	_check(ctrl._beneficiary_fx.get(priest.get_instance_id()) == fx, "Multiple Stand cycles retain same instance")
	priest.global_position = _ground(hf, caster.global_position + Vector3(20, 0, 0))
	await _settle(game)
	_check(BuffQuery.mana_regen_bonus(priest) == 0.0 and not is_instance_valid(fx), "Leaving radius clears buff and circle")
	priest.global_position = _ground(hf, caster.global_position + Vector3(0, 0, 2))
	await _settle(game)
	_check(ctrl._beneficiary_fx.has(priest.get_instance_id()) and BuffQuery.mana_regen_bonus(priest) > 0.0, "Reentering recreates circle and buff")
	caster.set_meta("life", 0.0)
	await _settle(game)
	_check(ctrl._beneficiary_fx.is_empty() and BuffQuery.mana_regen_bonus(priest) == 0.0, "Dead source clears beneficiary circles and buffs")
	caster.set_meta("life", saved_life)
	await _settle(game)
	_check(ctrl._beneficiary_fx.has(priest.get_instance_id()), "Revived source restores circle")
	caster.set_meta(AbilityCatalog.META_ABILITY_LEVELS, saved_levels)
	caster.set_meta(AbilityCatalog.META_HERO_LEVEL, saved_level)
	priest.global_position = saved_position
	await _settle(game)
	return {"failures": failures, "ordinary_learning": true, "native": true, "animation": animation, "policy": policy, "range_cleanup": true, "dead_source_cleanup": true, "reentry": true, "visual": "requires_original_game_comparison"}

func _settle(game: GameMain) -> void:
	for frame: int in range(4):
		await game.get_tree().process_frame

func _save(game: GameMain, path: String) -> void:
	await RenderingServer.frame_post_draw
	_check(game.get_viewport().get_texture().get_image().save_png(path) == OK, "Aura screenshot")

func _ground(hf: Wc3Heightfield, point: Vector3) -> Vector3:
	var xy: Vector2 = Wc3Coords.godot_to_wc3_xy(point)
	return Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, hf.interpolated_height(xy.x, xy.y))

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
