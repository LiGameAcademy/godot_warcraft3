class_name OpponentAiModule
extends Node

## 对手电脑：经营 AI + 可选军队 AI 的对局挂接。
## 节点挂在 host_parent（通常为总管）下，保持 OpponentEconomy / OpponentArmy 路径兼容。
## 不持有 GameDirector 类型。

const PlayerEconomyAIScript = preload("res://game/scripts/logic/ai/player_economy_ai.gd")
const PlayerArmyAIScript = preload("res://game/scripts/logic/ai/player_army_ai.gd")

var _host_parent: Node
var _map_root: MapLoader
var _session: GameSession
var _path_query: PathQuery
var _crowd_query: UnitCrowdQuery
var _pathing: Wc3PathingMap
var _tree_registry: TreeRegistry
var _item_service: Variant

var _ensure_navigator: Callable
var _ensure_harvest: Callable
var _ensure_build: Callable
var _ensure_attack: Callable
var _find_build_site: Callable
var _find_build_site_by_node: Callable
var _wire_train_queue: Callable
var _stock_for_owner: Callable


func configure(deps: Dictionary) -> void:
	_host_parent = deps.get("host_parent") as Node
	_map_root = deps.get("map_root") as MapLoader
	_session = deps.get("session") as GameSession
	_path_query = deps.get("path_query") as PathQuery
	_crowd_query = deps.get("crowd_query") as UnitCrowdQuery
	_pathing = deps.get("pathing") as Wc3PathingMap
	_tree_registry = deps.get("tree_registry") as TreeRegistry
	_item_service = deps.get("item_service")
	_ensure_navigator = deps.get("ensure_navigator", Callable()) as Callable
	_ensure_harvest = deps.get("ensure_harvest", Callable()) as Callable
	_ensure_build = deps.get("ensure_build", Callable()) as Callable
	_ensure_attack = deps.get("ensure_attack", Callable()) as Callable
	_find_build_site = deps.get("find_build_site", Callable()) as Callable
	_find_build_site_by_node = deps.get("find_build_site_by_node", Callable()) as Callable
	_wire_train_queue = deps.get("wire_train_queue", Callable()) as Callable
	_stock_for_owner = deps.get("stock_for_owner", Callable()) as Callable


func shutdown() -> void:
	_host_parent = null
	_map_root = null
	_session = null
	_path_query = null
	_crowd_query = null
	_pathing = null
	_tree_registry = null
	_item_service = null
	_ensure_navigator = Callable()
	_ensure_harvest = Callable()
	_ensure_build = Callable()
	_ensure_attack = Callable()
	_find_build_site = Callable()
	_find_build_site_by_node = Callable()
	_wire_train_queue = Callable()
	_stock_for_owner = Callable()


func _exit_tree() -> void:
	shutdown()


## 挂接对手经营（及可选军队）。已存在 OpponentEconomy 时跳过。
func setup(local_player: int, enable_army: bool = false) -> Node:
	if _host_parent == null or _session == null or _map_root == null:
		return null
	var owner := 1 if local_player == 0 else 0
	if not _session.stocks.has(owner):
		return null
	if _host_parent.has_node("OpponentEconomy"):
		return _host_parent.get_node("OpponentEconomy")

	var unit_layer: Node = _map_root.get_unit_layer()
	var commands := CommandRouter.new()
	commands.configure(
		_path_query,
		_crowd_query,
		_ensure_navigator,
		_ensure_harvest,
		_ensure_build,
		_session,
		_find_build_site,
		_find_build_site_by_node,
		_ensure_attack,
		owner
	)
	if _wire_train_queue.is_valid():
		commands.production_queue_ready.connect(_wire_train_queue)

	var economy := PlayerEconomyAIScript.new()
	economy.name = "OpponentEconomy"
	economy.configure(commands, unit_layer, _tree_registry, owner)
	if _stock_for_owner.is_valid():
		economy.stock = _stock_for_owner.call(owner)
	economy.pathing = _pathing
	economy.path_query = _path_query
	_host_parent.add_child(economy)

	if enable_army:
		var army := PlayerArmyAIScript.new()
		army.name = "OpponentArmy"
		army.router = commands
		army.unit_host = unit_layer
		army.observe_enemies = Callable(self, "observe_enemies").bind(owner)
		army.item_service = _item_service
		_host_parent.add_child(army)

	return economy


## 当前开发对局全图可见；后续战争迷雾只替换此观察接口。
func observe_enemies(owner: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _map_root == null:
		return out
	var layer: Node = _map_root.get_unit_layer()
	if layer == null:
		return out
	for unit in layer.get_children():
		if unit is Node3D and CombatQuery.is_alive_in_world(unit):
			var other := CombatQuery.owner_of(unit)
			if other != owner and not CombatQuery.is_neutral_owner(other):
				out.append(unit)
	return out
