class_name BehaviorRegistry
extends RefCounted

## behavior_id → 工厂 Callable（D5）。启动阶段注册；对局冻结后不得改语义。

var _factories: Dictionary = {} # String → Callable
var _frozen: bool = false


func freeze() -> void:
	_frozen = true


func is_frozen() -> bool:
	return _frozen


func register_factory(behavior_id: String, factory: Callable) -> bool:
	if _frozen:
		push_warning("BehaviorRegistry: frozen, ignore %s" % behavior_id)
		return false
	if behavior_id.is_empty() or not factory.is_valid():
		return false
	_factories[behavior_id] = factory
	return true


func has_behavior(behavior_id: String) -> bool:
	return _factories.has(behavior_id)


func create(behavior_id: String, ctx: Dictionary = {}) -> Variant:
	if not _factories.has(behavior_id):
		return null
	var factory: Callable = _factories[behavior_id]
	return factory.call(ctx)


func registered_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _factories.keys():
		out.append(str(k))
	return out
