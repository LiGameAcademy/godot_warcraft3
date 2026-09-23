class_name OrderQueue
extends RefCounted

## 单单位命令队列。F0：仅当前命令；后续可 push 排队（Shift+命令）。

var current: UnitOrder = null
var _pending: Array[UnitOrder] = []


func clear() -> void:
	current = null
	_pending.clear()


func set_current(order: UnitOrder) -> void:
	current = order
	_pending.clear()


func push(order: UnitOrder) -> void:
	if order == null:
		return
	if current == null:
		current = order
	else:
		_pending.append(order)


func pop_next() -> UnitOrder:
	if _pending.is_empty():
		current = null
		return null
	current = _pending.pop_front()
	return current


func is_idle() -> bool:
	return current == null or current.kind == UnitOrder.Kind.NONE


func is_move() -> bool:
	return current != null and current.kind == UnitOrder.Kind.MOVE
