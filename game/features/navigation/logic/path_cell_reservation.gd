class_name PathCellReservation
extends RefCounted
## 运行时寻路格占用/预约（Logic）。
##
## 用途：多单位同时走窄道时，A* 避开「别人正在占/预约」的格，减轻堵门互卡。
## 不做完整 WC3 占格系统：只维护 instance_id → 若干格；站立不预约（对齐「站着不挤人」）。

var _cells: Dictionary = {} ## Vector2i -> owner id
var _owners: Dictionary = {} ## owner id -> successfully reserved cells

func clear() -> void:
	_cells.clear()
	_owners.clear()

func clear_owner(owner_id: int) -> void:
	for cell in _owners.get(owner_id, {}):
		if _cells.get(cell, 0) == owner_id:
			_cells.erase(cell)
	_owners.erase(owner_id)

func set_owner_cells(owner_id: int, cells: Array) -> void:
	var started := MatchHotpathMetrics.begin()
	_measured_set_owner_cells(owner_id, cells)
	MatchHotpathMetrics.finish(&"reservation", started)


func _measured_set_owner_cells(owner_id: int, cells: Array) -> void:
	if owner_id == 0:
		return
	var wanted := {}
	for cell in cells:
		if cell is Vector2i:
			wanted[cell] = true
	var owned: Dictionary = _owners.get(owner_id, {})
	for cell in owned.keys():
		if not wanted.has(cell):
			if _cells.get(cell, 0) == owner_id:
				_cells.erase(cell)
			owned.erase(cell)
	# Retry previously blocked cells even when the requested set is unchanged.
	for cell in wanted:
		if not _cells.has(cell) or _cells[cell] == owner_id:
			_cells[cell] = owner_id
			owned[cell] = true
	if owned.is_empty():
		_owners.erase(owner_id)
	else:
		_owners[owner_id] = owned

func is_blocked_for(cx: int, cy: int, self_id: int) -> bool:
	var owner: int = _cells.get(Vector2i(cx, cy), 0)
	return owner != 0 and owner != self_id
