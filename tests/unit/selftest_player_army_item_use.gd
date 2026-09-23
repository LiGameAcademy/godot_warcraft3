extends Node

## PlayerArmyAI 用药：HP/MP 阈值触发 try_use；满血不耗；装备不主动用。
const ArmyScript = preload("res://addons/rts_gameplay/features/ai/logic/player_army_ai.gd")
var failures := 0
var checks := 0
var enemies: Array[Node3D] = []


class RecordingRouter extends CommandRouter:
	func issue_attack_move(units: Array, _goal: Vector2, _source: int = UnitOrder.Source.UNKNOWN) -> Dictionary:
		return {"moved": units.size()}

	func issue_move_to_wc3(units: Array, _goal: Vector2, _source: int = UnitOrder.Source.UNKNOWN) -> Dictionary:
		return {"moved": units.size()}

	func issue_pickup(_selected: Array, _ground: GroundItem, _source: int) -> int:
		return 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ARMY ITEM USE: " + label)


func hero(host: Node, owner_id: int = 1) -> Node3D:
	var node := Node3D.new()
	node.set_meta("unit_data", {"typeId": "Hamg", "owner": owner_id})
	node.set_meta("life", 100.0)
	node.set_meta("max_life", 1000.0)
	host.add_child(node)
	Inventory.ensure_on(node)
	UnitMana.ensure(node)
	return node


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var host := Node3D.new()
	add_child(host)
	var session := GameSession.new()
	session.ensure_stock(1)
	var commands := RecordingRouter.new()
	commands.configure(null, null, Callable(), Callable(), Callable(), session, Callable(), Callable(), Callable(), 1)
	var army := ArmyScript.new()
	army.router = commands
	army.unit_host = host
	army.observe_enemies = func() -> Array[Node3D]: return enemies
	add_child(army)

	var base := Node3D.new()
	base.set_meta("unit_data", {"typeId": "htow", "owner": 1})
	base.set_meta("life", 100.0)
	host.add_child(base)

	var mage := hero(host)
	var inv := Inventory.of(mage)
	inv.insert(ItemInstance.create("phea"), 0)
	inv.insert(ItemInstance.create("pman"), 1)
	inv.insert(ItemInstance.create("rde1"), 2)

	UnitLife.set_life(mage, 100.0)
	army.decide()
	check(inv.item_at(0) == null, "低生命时消耗治疗药水")
	check(UnitLife.get_life(mage) > 100.0, "治疗后生命上升")

	UnitLife.set_life(mage, UnitLife.get_max_life(mage))
	inv.insert(ItemInstance.create("phea"), 0)
	army.decide()
	check(inv.item_at(0) != null, "满血不消耗治疗药水")

	# 强制低蓝：ensure 之后直接改 meta
	var max_mp := maxi(UnitMana.get_max_mana(mage), 1)
	mage.set_meta("mana", int(max_mp * 0.1))
	var mana_before := UnitMana.get_mana(mage)
	army.decide()
	check(inv.item_at(1) == null and UnitMana.get_mana(mage) > mana_before, "低魔法时消耗回蓝药水")

	check(inv.item_at(2) != null, "指环仍在槽位（装备不主动消耗）")

	print("selftest_player_army_item_use: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
