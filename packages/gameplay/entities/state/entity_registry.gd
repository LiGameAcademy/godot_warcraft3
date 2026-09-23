class_name EntityRegistry
extends RefCounted

var _by_id: Dictionary = {}
var _id_by_instance: Dictionary = {}
var _host: WeakRef
var _next_id := 2000000000

func clear() -> void:
	bind_host(null)
	for value in _by_id.keys():
		unregister(EntityId.new(value))

func register_unit(entity: EntityId, node: Node) -> void:
	if entity == null or not entity.is_valid() or not is_instance_valid(node):
		return
	var instance := node.get_instance_id()
	if _id_by_instance.get(instance, 0) == entity.value and get_node(entity) == node:
		return
	unregister(entity)
	var old: int = _id_by_instance.get(instance, 0)
	if old > 0:
		unregister(EntityId.new(old))
	var callback := _on_exit.bind(entity.value, instance)
	_by_id[entity.value] = {"ref": weakref(node), "instance": instance, "callback": callback}
	_id_by_instance[instance] = entity.value
	node.tree_exiting.connect(callback)

func unregister(entity: EntityId) -> void:
	if entity == null or not _by_id.has(entity.value):
		return
	var record: Dictionary = _by_id[entity.value]
	var node: Node = record.ref.get_ref()
	if is_instance_valid(node) and node.tree_exiting.is_connected(record.callback):
		node.tree_exiting.disconnect(record.callback)
	_id_by_instance.erase(record.instance)
	_by_id.erase(entity.value)

func _on_exit(value: int, instance: int) -> void:
	if _by_id.has(value) and _by_id[value].instance == instance:
		unregister(EntityId.new(value))

func get_node(entity: EntityId) -> Node:
	if entity == null or not _by_id.has(entity.value):
		return null
	var node: Node = _by_id[entity.value].ref.get_ref()
	if not is_instance_valid(node):
		unregister(entity)
		return null
	return node

func id_of(node: Node) -> EntityId:
	if not is_instance_valid(node):
		return EntityId.invalid()
	return EntityId.new(_id_by_instance.get(node.get_instance_id(), 0))

func count() -> int:
	for value in _by_id.keys():
		get_node(EntityId.new(value))
	return _by_id.size()

func bind_host(host: Node) -> void:
	var old: Node = _host.get_ref() if _host != null else null
	if old == host:
		return
	if is_instance_valid(old) and old.child_entered_tree.is_connected(_track):
		old.child_entered_tree.disconnect(_track)
	_host = weakref(host) if is_instance_valid(host) else null
	if is_instance_valid(host):
		host.child_entered_tree.connect(_track)
		for child in host.get_children():
			_track(child)

func _track(node: Node) -> void:
	if not node is Node3D or not node.has_meta("unit_data") or id_of(node).is_valid():
		return
	var value := int(node.get_meta("unit_data", {}).get("creationNumber", 0))
	if value <= 0 or get_node(EntityId.new(value)) != null:
		while _by_id.has(_next_id):
			_next_id += 1
		value = _next_id
		_next_id += 1
	register_unit(EntityId.new(value), node)
