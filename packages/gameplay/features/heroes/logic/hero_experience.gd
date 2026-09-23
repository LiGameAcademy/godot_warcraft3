extends RefCounted

const Rules = preload("res://addons/rts_gameplay/catalog/melee_game_constants.gd")
const AWARDED := "hero_death_xp_processed"

static func reward_for_level(level: int, hero: bool) -> float:
	var prefix := "GrantHeroXP" if hero else "GrantNormalXP"
	var table := Rules.numbers(prefix)
	if table.is_empty():
		return 0.0
	var lv := clampi(level, 1, int(Rules.number("MaxHeroLevel" if hero else "MaxUnitLevel", 10 if hero else 20)))
	if lv <= table.size():
		return table[lv - 1]
	var result := table[-1]
	for i in range(table.size() + 1, lv + 1):
		result = Rules.number(prefix + "FormulaA", 1) * result + Rules.number(prefix + "FormulaB", 0) * i + Rules.number(prefix + "FormulaC", 0)
	return result

## 当前对战敌我按owner区分，与CombatQuery一致；联盟共享待会话联盟接入。
## 返回实际入账结果，便于HUD/升级表现与验收复用。
static func award_death(victim: Node3D, killer: Node3D, host: Node) -> Array[Dictionary]:
	var awards: Array[Dictionary] = []
	if not is_instance_valid(victim) or not is_instance_valid(killer) or host == null:
		return awards
	if UnitLife.get_life(victim) > 0 or bool(victim.get_meta(AWARDED, false)):
		return awards
	victim.set_meta(AWARDED, true)
	var owner := CombatQuery.owner_of(killer)
	if CombatQuery.is_neutral_owner(owner) or not CombatQuery.is_hostile(killer, victim):
		return awards
	if BuildingCatalog.is_building(CombatQuery.type_id_of(killer)) and Rules.number("BuildingKillsGiveExp", 0) == 0:
		return awards
	if BuildingCatalog.is_building(CombatQuery.type_id_of(victim)) and not CombatQuery.has_weapon(victim):
		return awards
	var balance := CombatQuery.balance_of(victim)
	if balance == null:
		return awards
	var is_hero := TechPresence.is_hero_id(CombatQuery.type_id_of(victim))
	var reward := reward_for_level(AbilityCatalog.hero_level_of(victim) if is_hero else balance.level, is_hero)
	if victim.has_meta("summon_caster_id"):
		reward *= Rules.number("SummonedKillFactor", 0.5)
	var eligible: Array[Node3D] = []
	var nearby: Array[Node3D] = []
	for child in host.get_children():
		if not child is Node3D or CombatQuery.owner_of(child) != owner or not TechPresence.is_hero_id(CombatQuery.type_id_of(child)):
			continue
		if not CombatQuery.is_alive_in_world(child):
			continue
		if AbilityCatalog.hero_level_of(child) >= HeroProgression.MAX_HERO_LEVEL and Rules.number("MaxLevelHeroesDrainExp", 1) == 0:
			continue
		eligible.append(child)
		if CombatQuery.distance_wc3(child, victim) <= Rules.number("HeroExpRange", 1200):
			nearby.append(child)
	var recipients := nearby if not nearby.is_empty() else eligible
	if nearby.is_empty() and Rules.number("GlobalExperience", 1) == 0:
		return awards
	if recipients.is_empty():
		return awards
	var factors := Rules.numbers("HeroFactorXP")
	for recipient in recipients:
		var share := reward / recipients.size()
		if CombatQuery.is_neutral_owner(CombatQuery.owner_of(victim)):
			if factors.is_empty():
				continue
			share *= factors[mini(AbilityCatalog.hero_level_of(recipient) - 1, factors.size() - 1)] / 100.0
		var gained := HeroProgression.add_experience(recipient, floori(share + 0.000000001))
		if gained.gained > 0:
			awards.append({"hero": recipient, "gained": gained.gained, "levels_gained": gained.levels_gained})
	return awards
