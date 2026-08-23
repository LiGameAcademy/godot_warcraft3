class_name AbilityAutoCastRunner
extends RefCounted

## 自动施法 tick（Logic）：对开启 autocast 的技能找目标并 try_cast。

const TICK_INTERVAL := 0.35


static func tick_unit(unit: Node3D, ctx: Dictionary, delta: float) -> void:
	if unit == null or not is_instance_valid(unit) or delta <= 0.0:
		return
	if _is_busy(unit):
		return
	var acc_key := "_autocast_acc"
	var acc := float(unit.get_meta(acc_key, 0.0)) + delta
	if acc < TICK_INTERVAL:
		unit.set_meta(acc_key, acc)
		return
	unit.set_meta(acc_key, 0.0)
	for abil_id in AbilityAutoCast.enabled_ability_ids(unit):
		if not AbilityAutoCast.is_enabled(unit, abil_id):
			continue
		_try_one(unit, str(abil_id), ctx)


static func _is_busy(unit: Node3D) -> bool:
	var acc := AbilityCastController.of(unit)
	if acc != null and acc.is_channeling():
		return true
	return false


static func _try_one(caster: Node3D, abil_id: String, ctx: Dictionary) -> void:
	if not AbilityCatalog.is_supported(abil_id):
		return
	var lv := AbilityCatalog.level_for(caster, abil_id)
	if lv <= 0:
		return
	if not AbilityCooldowns.is_ready(caster, abil_id):
		return
	var ab := AbilityCatalog.data(abil_id)
	if ab != null and UnitMana.has_mana(caster):
		if not UnitMana.can_spend(caster, ab.cost_at(lv)):
			return
	var target := _pick_target(caster, abil_id, ctx)
	if target == null:
		return
	var goal := Wc3Coords.godot_to_wc3_xy(
		target.global_position if target != null else caster.global_position
	)
	var check: Dictionary
	match AbilityCatalog.target_kind(abil_id):
		AbilityCatalog.TARGET_ALLY:
			check = AbilityCastRules.can_cast_unit(caster, abil_id, target, lv)
		AbilityCatalog.TARGET_UNIT:
			check = AbilityCastRules.can_cast_unit(caster, abil_id, target, lv)
		_:
			return
	if not bool(check.get("ok", false)):
		return
	AbilityExecutor.try_cast(caster, abil_id, goal, target, ctx)


static func _pick_target(caster: Node3D, abil_id: String, ctx: Dictionary) -> Node3D:
	match AbilityCatalog.order_for(abil_id):
		"heal":
			return _pick_heal_target(caster, abil_id, ctx)
		"innerfire":
			return _pick_inner_fire_target(caster, abil_id, ctx)
		"slow":
			return _pick_slow_target(caster, abil_id, ctx)
		_:
			return null


static func _pick_heal_target(caster: Node3D, abil_id: String, ctx: Dictionary) -> Node3D:
	var host_cb: Callable = ctx.get("unit_host", Callable())
	if not host_cb.is_valid():
		return null
	var host: Node = host_cb.call() as Node
	if host == null:
		return null
	var lv := AbilityCatalog.level_for(caster, abil_id)
	var ab := AbilityCatalog.data(abil_id)
	if ab == null:
		return null
	var rng := ab.cast_range_at(lv)
	var center := Wc3Coords.godot_to_wc3_xy(caster.global_position)
	var allies := CombatQuery.units_friendly_in_radius(host, caster, center, rng)
	var best: Node3D = null
	var best_ratio := 1.0
	for n in allies:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var ally := n as Node3D
		if not CombatQuery.is_valid_ability_unit_target(caster, ally, abil_id):
			continue
		UnitLife.ensure(ally)
		var mx := maxf(UnitLife.get_max_life(ally), 1.0)
		var life := UnitLife.get_life(ally)
		if life >= mx - 0.5:
			continue
		var ratio := life / mx
		if ratio < best_ratio:
			best_ratio = ratio
			best = ally
	return best


static func _pick_inner_fire_target(caster: Node3D, abil_id: String, ctx: Dictionary) -> Node3D:
	var host_cb: Callable = ctx.get("unit_host", Callable())
	if not host_cb.is_valid():
		return null
	var host: Node = host_cb.call() as Node
	if host == null:
		return null
	var lv := AbilityCatalog.level_for(caster, abil_id)
	var ab := AbilityCatalog.data(abil_id)
	if ab == null:
		return null
	var rng := ab.cast_range_at(lv)
	var center := Wc3Coords.godot_to_wc3_xy(caster.global_position)
	var allies := CombatQuery.units_friendly_in_radius(host, caster, center, rng)
	for n in allies:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var ally := n as Node3D
		if not CombatQuery.is_valid_ability_unit_target(caster, ally, abil_id):
			continue
		var ctrl := InnerFireController.of(ally)
		if ctrl != null and ctrl.is_active():
			continue
		return ally
	return null


static func _pick_slow_target(caster: Node3D, abil_id: String, ctx: Dictionary) -> Node3D:
	var host_cb: Callable = ctx.get("unit_host", Callable())
	if not host_cb.is_valid():
		return null
	var host: Node = host_cb.call() as Node
	if host == null:
		return null
	var lv := AbilityCatalog.level_for(caster, abil_id)
	var ab := AbilityCatalog.data(abil_id)
	if ab == null:
		return null
	var rng := ab.cast_range_at(lv)
	var center := Wc3Coords.godot_to_wc3_xy(caster.global_position)
	var foes := CombatQuery.units_hostile_in_radius(host, caster, center, rng)
	for n in foes:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var foe := n as Node3D
		if not CombatQuery.is_valid_ability_unit_target(caster, foe, abil_id):
			continue
		if UnitStatusEffects.is_slowed(foe):
			continue
		return foe
	return null
