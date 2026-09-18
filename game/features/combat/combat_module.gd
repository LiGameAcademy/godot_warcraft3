class_name CombatModule
extends Node

## 对局内战斗协调：伤害管线、投射物、死亡/尸体、AttackController 装配。
## 由总管注入地图与横切依赖；本模块不依赖 GameDirector 类型。

const CombatProjectileShellScene = preload("res://game/scenes/combat_projectile_shell.tscn")
const SceneDelay = preload("res://scripts/shared/infra/scene_delay.gd")
const Experience = preload("res://game/scripts/logic/hero/hero_experience.gd")

var damage_pipeline: DamagePipeline = null
var death_service: DeathService = null
var projectile_service: ProjectileService = null

var _map_root: MapLoader
var _health_bar_manager: HealthBarManager
var _ensure_navigator: Callable
var _ensure_unit_visual: Callable
var _unit_host: Callable
var _release_food: Callable
var _terminate_production: Callable
var _prepare_hero_death: Callable
var _deselect_unit: Callable
var _get_primary: Callable
var _get_selected: Callable
var _apply_selection_info: Callable
var _refresh_command_card: Callable


func configure(deps: Dictionary) -> void:
	_map_root = deps.get("map_root") as MapLoader
	_health_bar_manager = deps.get("health_bar_manager") as HealthBarManager
	_ensure_navigator = deps.get("ensure_navigator", Callable()) as Callable
	_ensure_unit_visual = deps.get("ensure_unit_visual", Callable()) as Callable
	_unit_host = deps.get("unit_host", Callable()) as Callable
	_release_food = deps.get("release_food", Callable()) as Callable
	_terminate_production = deps.get("terminate_production", Callable()) as Callable
	_prepare_hero_death = deps.get("prepare_hero_death", Callable()) as Callable
	_deselect_unit = deps.get("deselect_unit", Callable()) as Callable
	_get_primary = deps.get("get_primary", Callable()) as Callable
	_get_selected = deps.get("get_selected", Callable()) as Callable
	_apply_selection_info = deps.get("apply_selection_info", Callable()) as Callable
	_refresh_command_card = deps.get("refresh_command_card", Callable()) as Callable
	_ensure_services()


func shutdown() -> void:
	_disconnect_service_signals()
	damage_pipeline = null
	death_service = null
	projectile_service = null
	_map_root = null
	_health_bar_manager = null
	_ensure_navigator = Callable()
	_ensure_unit_visual = Callable()
	_unit_host = Callable()
	_release_food = Callable()
	_terminate_production = Callable()
	_prepare_hero_death = Callable()
	_deselect_unit = Callable()
	_get_primary = Callable()
	_get_selected = Callable()
	_apply_selection_info = Callable()
	_refresh_command_card = Callable()


func _exit_tree() -> void:
	shutdown()


func tick(delta: float) -> void:
	if projectile_service != null:
		projectile_service.tick(delta)


func kill(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if death_service != null:
		death_service.kill(unit)
	else:
		unit.queue_free()


func ensure_attack_controller(unit: Node3D) -> AttackController:
	if unit == null or not is_instance_valid(unit):
		return null
	if _ensure_unit_visual.is_valid():
		_ensure_unit_visual.call(unit)
	UnitLife.ensure(unit)
	var existing := unit.get_node_or_null("AttackController") as AttackController
	if existing != null:
		existing.configure(_ensure_navigator, _unit_host, damage_pipeline, projectile_service)
		return existing
	var ac := AttackController.new()
	ac.name = "AttackController"
	ac.configure(_ensure_navigator, _unit_host, damage_pipeline, projectile_service)
	unit.add_child(ac)
	return ac


## 物品等系统订阅单位死亡（经验已在模块内处理）。
func connect_unit_died(cb: Callable) -> void:
	if death_service == null or not cb.is_valid():
		return
	if not death_service.unit_died.is_connected(cb):
		death_service.unit_died.connect(cb)


func _ensure_services() -> void:
	if death_service == null:
		death_service = DeathService.new()
	death_service.on_before_exit = Callable(self, "on_unit_dying")
	if not death_service.unit_died.is_connected(_award_death_experience):
		death_service.unit_died.connect(_award_death_experience)

	if damage_pipeline == null:
		damage_pipeline = DamagePipeline.new()
	damage_pipeline.death = death_service
	if not damage_pipeline.damage_applied.is_connected(_on_damage_applied_present):
		damage_pipeline.damage_applied.connect(_on_damage_applied_present)

	if projectile_service == null:
		projectile_service = ProjectileService.new()
	projectile_service.pipeline = damage_pipeline
	if not projectile_service.projectile_launched.is_connected(_on_projectile_launched):
		projectile_service.projectile_launched.connect(_on_projectile_launched)
	if not projectile_service.projectile_resolved.is_connected(_on_projectile_resolved):
		projectile_service.projectile_resolved.connect(_on_projectile_resolved)


func _disconnect_service_signals() -> void:
	if death_service != null:
		if death_service.unit_died.is_connected(_award_death_experience):
			death_service.unit_died.disconnect(_award_death_experience)
		death_service.on_before_exit = Callable()
	if damage_pipeline != null and damage_pipeline.damage_applied.is_connected(_on_damage_applied_present):
		damage_pipeline.damage_applied.disconnect(_on_damage_applied_present)
	if projectile_service != null:
		if projectile_service.projectile_launched.is_connected(_on_projectile_launched):
			projectile_service.projectile_launched.disconnect(_on_projectile_launched)
		if projectile_service.projectile_resolved.is_connected(_on_projectile_resolved):
			projectile_service.projectile_resolved.disconnect(_on_projectile_resolved)


func _award_death_experience(victim: Node3D, killer: Node3D) -> void:
	if _map_root == null:
		return
	var awards := Experience.award_death(victim, killer, _map_root.get_unit_layer())
	var primary: Node3D = null
	if _get_primary.is_valid():
		primary = _get_primary.call() as Node3D
	for award in awards:
		if award.hero == primary:
			if _apply_selection_info.is_valid():
				var selected: Array = _get_selected.call() if _get_selected.is_valid() else []
				_apply_selection_info.call(primary, selected)
			if int(award.levels_gained) > 0 and _refresh_command_card.is_valid():
				_refresh_command_card.call()
			break


func _on_projectile_launched(info: Dictionary) -> void:
	var from_wc3: Vector3 = info.get("from_wc3", Vector3.ZERO)
	var to_wc3: Vector3 = info.get("to_wc3", Vector3.ZERO)
	var duration := float(info.get("duration", 0.2))
	var attacker: Node3D = info.get("attacker") as Node3D
	var target: Node3D = info.get("target") as Node3D
	var show_tracer := true
	var impact_art := ""
	var missile_art := ""
	var arc := 0.0
	var speed_wc3 := 900.0
	if bool(info.get("is_spell", false)):
		show_tracer = true
		var spell_missile := str(info.get("missile_art", "")).strip_edges()
		if not spell_missile.is_empty():
			missile_art = spell_missile
		var spell_impact := str(info.get("impact_art", "")).strip_edges()
		if not spell_impact.is_empty():
			impact_art = spell_impact
	elif attacker != null and is_instance_valid(attacker):
		show_tracer = CombatQuery.wants_tracer_visual(attacker)
		impact_art = CombatQuery.weapon_impact_art(attacker)
		missile_art = CombatQuery.weapon_missile_art(attacker)
		arc = CombatQuery.missile_arc(attacker)
		speed_wc3 = CombatQuery.missile_speed_wc3(attacker)
	if info.has("speed_wc3"):
		speed_wc3 = float(info.get("speed_wc3", speed_wc3))
	var cache := _model_cache()
	var shell: Node3D = CombatProjectileShellScene.instantiate() as Node3D
	if shell == null:
		return
	shell.name = "CombatProjectileShell_%s" % str(info.get("id", 0))
	var fx_parent: Node = _map_root
	if _map_root != null and _map_root.has_method("get_unit_layer"):
		var layer := _map_root.get_unit_layer()
		if layer != null:
			fx_parent = layer
	elif _map_root == null:
		fx_parent = self
	fx_parent.add_child(shell)
	if shell.has_method("play"):
		shell.call(
			"play",
			from_wc3,
			to_wc3,
			duration,
			show_tracer,
			impact_art,
			cache,
			target,
			missile_art,
			arc,
			speed_wc3
		)


func _on_projectile_resolved(result: Dictionary) -> void:
	if bool(result.get("visual_only", false)):
		return
	if bool(result.get("is_spell", false)):
		var target: Node3D = result.get("target") as Node3D
		var abil_id := str(result.get("spell_abil_id", "")).strip_edges()
		var hit_art := AbilityCastCatalog.hit_effect_art(abil_id)
		if not hit_art.is_empty() and target != null and is_instance_valid(target):
			SpellHitFx.spawn_on(target, hit_art, _model_cache())
		if _health_bar_manager != null:
			_health_bar_manager.resync()
		return
	var attacker: Node3D = result.get("attacker") as Node3D
	if attacker == null or not is_instance_valid(attacker):
		return
	var ac := attacker.get_node_or_null("AttackController") as AttackController
	if ac != null:
		ac.notify_strike_result(result)


func _on_damage_applied_present(result: Dictionary) -> void:
	DamageFloatText.spawn(result.get("target") as Node3D, result)
	var victim: Node3D = result.get("target") as Node3D
	var ai := UnitAI.of(victim)
	if ai != null:
		ai.notify_damaged(result)


func on_unit_dying(unit: Node3D) -> void:
	if unit == null:
		return
	InnerFireController.cleanup_on_death(unit)
	var bh := BuffHost.of(unit)
	if bh != null:
		bh.clear_all()
	if _prepare_hero_death.is_valid():
		_prepare_hero_death.call(unit)
	HeroDeathRegistry.register_death(unit)
	var inv := Inventory.of(unit)
	if inv != null:
		inv.clear()
	if _release_food.is_valid():
		_release_food.call(unit)
	if _terminate_production.is_valid():
		_terminate_production.call(unit)
	if _deselect_unit.is_valid():
		_deselect_unit.call(unit)
	var vis: Variant = null
	if _ensure_unit_visual.is_valid():
		vis = _ensure_unit_visual.call(unit)
	if vis != null:
		if not vis.corpse_expired.is_connected(on_corpse_expired):
			vis.corpse_expired.connect(on_corpse_expired)
		vis.play_death()
	else:
		var tree := get_tree()
		if tree != null:
			SceneDelay.create_timer(self, Unit.CORPSE_LINGER_SEC).timeout.connect(
				on_corpse_expired.bind(unit)
			)
		else:
			on_corpse_expired(unit)
	var hc := unit.get_node_or_null("HarvestController") as HarvestController
	if hc != null:
		hc.abort()
	var ac := unit.get_node_or_null("AttackController") as AttackController
	if ac != null:
		ac.cancel()
	var uai := UnitAI.of(unit)
	if uai != null:
		uai.yield_to_player()
	var mc := MilitiaController.of(unit)
	if mc != null:
		mc.set_process(false)
	var sl := unit.get_node_or_null("SummonLifetime") as SummonLifetime
	if sl != null:
		sl.set_process(false)
	var pc := unit.get_node_or_null("PatrolController") as PatrolController
	if pc != null:
		pc.cancel()
	var nav := unit.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null:
		nav.stop()
	var cast := AbilityCastController.of(unit)
	if cast != null:
		cast.cancel_cast()


func on_corpse_expired(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var d: Dictionary = unit.get_meta("unit_data", {})
	var cn := int(d.get("creationNumber", -1))
	if _map_root != null and cn >= 0 and _map_root.remove_unit_instance(cn):
		return
	unit.queue_free()


func _model_cache() -> MapModelCache:
	if _map_root != null and _map_root.has_method("get_model_cache"):
		return _map_root.get_model_cache() as MapModelCache
	return null
