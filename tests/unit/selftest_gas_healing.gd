extends Node

var checks := 0
var failed := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed += 1
		push_error("GAS HEALING: " + message)

func unit(id: String, owner_id: int = 0) -> Node3D:
	var node := Node3D.new()
	node.set_meta("unit_data", {"typeId": id, "owner": owner_id})
	node.set_meta("life", 100.0)
	node.set_meta("max_life", 1000.0)
	node.set_meta("mana", 100)
	node.set_meta("max_mana", 100)
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	library.add_animation("SpellAttack", Animation.new())
	player.add_animation_library("", library)
	node.add_child(player)
	add_child(node)
	return node

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var priest := unit("hmpr")
	var hero := unit("Hamg")
	var inv := Inventory.ensure_on(hero)
	inv.insert(ItemInstance.create("phea"))
	inv.insert(ItemInstance.create("phea"))
	var effect := Wc3HealEffect.new()
	check(effect is GameplayEffect, "game healing uses plugin effect protocol")
	var heal := AbilityCatalog.data("Ahea")
	var before := UnitLife.get_life(hero)
	var cast := HealAbility.try_cast(priest, "Ahea", hero, {})
	check(cast.get("ok", false), "actual HealAbility accepted")
	check(UnitLife.get_life(hero) == before + heal.data_a_at(1), "spell heals exactly once with SLK amount")
	check(UnitMana.get_mana(priest) == 100 - heal.cost_at(1), "spell pays mana exactly once")
	check(inv.item_at(0).charges == 1 and inv.item_at(1).charges == 1, "spell does not consume held items")
	check(inv.cooldown_remaining(0) == 0.0, "spell does not start potion cooldown")
	var mana_before := UnitMana.get_mana(hero)
	before = UnitLife.get_life(hero)
	check(inv.try_use(0).ok, "potion succeeds alongside spell cooldown")
	check(UnitLife.get_life(hero) == before + ItemCatalog.effect("phea").data_a_at(1), "potion heals exactly once through shared backend")
	check(UnitMana.get_mana(hero) == mana_before, "potion does not pay spell mana")
	check(inv.item_at(0) == null and inv.item_at(1).charges == 1, "only source potion consumed")
	check(not inv.try_use(1).ok, "shared potion cooldown remains authoritative")
	var full := unit("Hamg")
	UnitLife.set_life(full, 1000.0)
	var full_inv := Inventory.ensure_on(full)
	full_inv.insert(ItemInstance.create("phea"))
	check(Wc3AbilityEffects.heal(full, priest, 20.0).outcome == GameplayEffectResult.Outcome.NO_EFFECT, "full health returns no_effect")
	check(not full_inv.try_use(0).ok and full_inv.item_at(0).charges == 1 and full_inv.cooldown_remaining(0) == 0.0, "full health rejects without item charge or cooldown")
	var other_priest := unit("hmpr")
	check(not HealAbility.try_cast(other_priest, "Ahea", full, {}).get("ok", false), "full health spell rejected")
	check(UnitMana.get_mana(other_priest) == 100 and AbilityCooldowns.is_ready(other_priest, "Ahea"), "failed spell costs nothing")
	UnitLife.set_life(full, 995.0)
	check(full_inv.try_use(0).ok and UnitLife.get_life(full) == 1000.0, "same backend caps at maximum")
	UnitLife.set_life(full, 0.0)
	check(Wc3AbilityEffects.heal(full, priest, 20.0).outcome == GameplayEffectResult.Outcome.REJECTED, "healing never revives dead target")
	check(Wc3AbilityEffects.heal(null, priest, 20.0).outcome == GameplayEffectResult.Outcome.REJECTED, "missing target rejected")
	var enemy := unit("hfoo", 1)
	check(not HealAbility.try_cast(other_priest, "Ahea", enemy, {}).get("ok", false), "existing faction validation preserved")
	check(hero.get_node_or_null("GameplayVitalAttributeComponent") == null, "no second HP/MP storage attached")
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("selftest_gas_healing: %s (%d checks)" % ["PASS" if failed == 0 else "FAIL", checks])
	get_tree().quit(0 if failed == 0 else 1)
