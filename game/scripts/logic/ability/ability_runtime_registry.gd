class_name AbilityRuntimeRegistry
extends RefCounted

## 单位技能运行时（Logic）：Mana / Autocast / 英雄被动挂载 / tick。
## 另：集中遍历单位时顺带 `UnitRegen.tick_unit`（自然回血回蓝）。

var _unit_host: Callable = Callable()
var _ctx_factory: AbilityCastContextFactory = null
var _map_root: Node = null


func configure(deps: Dictionary) -> void:
	_unit_host = deps.get("unit_host", Callable()) as Callable
	_ctx_factory = deps.get("ctx_factory") as AbilityCastContextFactory
	_map_root = deps.get("map_root") as Node


func ensure_unit(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	UnitMana.ensure(unit)
	AbilityAutoCast.ensure_defaults(unit)
	var tid := str(unit.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	if TechPresence.is_hero_id(tid):
		ensure_hero_passives(unit)


func ensure_hero_passives(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var tid := str(unit.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	if not TechPresence.is_hero_id(tid):
		return
	if not unit.has_meta(AbilityCatalog.META_HERO_LEVEL):
		unit.set_meta(AbilityCatalog.META_HERO_LEVEL, 1)
	HeroProgression.ensure(unit)
	HeroSkill.ensure_levels_meta(unit)
	UnitMana.ensure(unit)
	UnitMana.sync_hero_max(unit)
	_ensure_passive_controllers(unit)


func _ensure_passive_controllers(unit: Node3D) -> void:
	# Catalog 被动表驱动：aura / proc；Avatar 为自 buff 控制器预挂。
	for abil_id in AbilityBehaviorCatalog.PASSIVE_ENTRIES.keys():
		var kind := AbilityBehaviorCatalog.passive_kind(str(abil_id))
		match kind:
			"aura":
				_ensure_brilliance(unit)
			"proc":
				_ensure_bash(unit)
	_ensure_avatar(unit)


func _ensure_bash(unit: Node3D) -> void:
	if BashController.unit_can_have(unit):
		BashController.ensure_on(unit)


func _ensure_avatar(unit: Node3D) -> void:
	if AvatarController.unit_can_have(unit):
		AvatarController.ensure_on(unit)


func _ensure_brilliance(unit: Node3D) -> void:
	var existing := BrillianceAuraController.of(unit)
	if not BrillianceAuraController.unit_can_have(unit):
		if existing != null:
			existing.queue_free()
		return
	var c := BrillianceAuraController.ensure_on(unit)
	var cache: MapModelCache = null
	if _map_root != null and _map_root.has_method("get_model_cache"):
		cache = _map_root.call("get_model_cache") as MapModelCache
	c.configure(_unit_host, cache)


func tick_all_units(delta: float) -> void:
	if delta <= 0.0:
		return
	if not _unit_host.is_valid():
		return
	var host: Node = _unit_host.call() as Node
	if host == null:
		return
	var ctx: Dictionary = {}
	if _ctx_factory != null:
		ctx = _ctx_factory.build()
	for c in host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var u := c as Node3D
		UnitRegen.tick_unit(u, delta)
		AbilityAutoCastRunner.tick_unit(u, ctx, delta)
		UnitStatusEffects.tick(u, delta)
		AbilityCooldowns.tick_all(u, delta)
