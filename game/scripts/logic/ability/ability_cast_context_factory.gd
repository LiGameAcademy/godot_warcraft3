class_name AbilityCastContextFactory
extends RefCounted

## 施法 ctx 工厂（Orchestration）：字段变更集中此处。

var _map_root: Node = null
var _heightfield: Variant = null
var _damage_pipeline: DamagePipeline = null
var _projectile_service: ProjectileService = null
var _path_query: PathQuery = null
var _crowd_query: UnitCrowdQuery = null
var _alloc_creation_number: Callable = Callable()
var _ensure_unit_ai: Callable = Callable()
var _unit_host: Callable = Callable()
var _channel_interrupt_check: Callable = Callable()
var _teleport_unit_wc3: Callable = Callable()
var _kill_unit: Callable = Callable()
var _clear_caster_orders: Callable = Callable()


func configure(deps: Dictionary) -> void:
	_map_root = deps.get("map_root") as Node
	_heightfield = deps.get("heightfield")
	_damage_pipeline = deps.get("damage_pipeline") as DamagePipeline
	_projectile_service = deps.get("projectile_service") as ProjectileService
	_path_query = deps.get("path_query") as PathQuery
	_crowd_query = deps.get("crowd_query") as UnitCrowdQuery
	_alloc_creation_number = deps.get("alloc_creation_number", Callable()) as Callable
	_ensure_unit_ai = deps.get("ensure_unit_ai", Callable()) as Callable
	_unit_host = deps.get("unit_host", Callable()) as Callable
	_channel_interrupt_check = deps.get("channel_interrupt_check", Callable()) as Callable
	_teleport_unit_wc3 = deps.get("teleport_unit_wc3", Callable()) as Callable
	_kill_unit = deps.get("kill_unit", Callable()) as Callable
	_clear_caster_orders = deps.get("clear_caster_orders", Callable()) as Callable


func build() -> Dictionary:
	var cache: MapModelCache = null
	if _map_root != null and _map_root.has_method("get_model_cache"):
		cache = _map_root.call("get_model_cache") as MapModelCache
	var cn := 0
	if _alloc_creation_number.is_valid():
		cn = int(_alloc_creation_number.call())
	return {
		"map_root": _map_root,
		"heightfield": _heightfield,
		"creation_number": cn,
		"ensure_unit_ai": _ensure_unit_ai,
		"damage_pipeline": _damage_pipeline,
		"projectile_service": _projectile_service,
		"unit_host": _unit_host,
		"model_cache": cache,
		"channel_interrupt_check": _channel_interrupt_check,
		"teleport_unit_wc3": _teleport_unit_wc3,
		"path_query": _path_query,
		"crowd_query": _crowd_query,
		"kill_unit": _kill_unit,
		"clear_caster_orders": _clear_caster_orders,
	}
