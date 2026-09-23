class_name EntityRegistry
extends RefCounted

## EntityId → 节点门面（D5 第一版）。对局内有效；存档 API 另议。
## 不持有 SceneTree 全局；由 Match 装配并在结束时 clear。

var _by_id: Dictionary = {} # int → Node
var _id_by_instance: Dictionary = {} # instance_id → int


func clear() -> void:
	_by_id.clear()
	_id_by_instance.clear()


func register_unit(entity: EntityId, node: Node) -> void:
	if entity == null or not entity.is_valid() or node == null:
		return
	_by_id[entity.value] = node
	_id_by_instance[node.get_instance_id()] = entity.value


func unregister(entity: EntityId) -> void:
	if entity == null or not entity.is_valid():
		return
	var node: Node = _by_id.get(entity.value) as Node
	_by_id.erase(entity.value)
	if node != null:
		_id_by_instance.erase(node.get_instance_id())


func get_node(entity: EntityId) -> Node:
	if entity == null or not entity.is_valid():
		return null
	var n: Node = _by_id.get(entity.value) as Node
	if n != null and not is_instance_valid(n):
		_by_id.erase(entity.value)
		return null
	return n


func id_of(node: Node) -> EntityId:
	if node == null or not is_instance_valid(node):
		return EntityId.invalid()
	var v: int = int(_id_by_instance.get(node.get_instance_id(), 0))
	return EntityId.from_creation_number(v)


func count() -> int:
	return _by_id.size()
