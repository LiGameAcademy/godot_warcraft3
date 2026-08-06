class_name PathCellReservation
extends RefCounted
## 运行时寻路格占用/预约（Logic）。
##
## 用途：多单位同时走窄道时，A* 避开「别人正在占/预约」的格，减轻堵门互卡。
## 不做完整 WC3 占格系统：只维护 instance_id → 若干格；站立不预约（对齐「站着不挤人」）。

var _cells: Dictionary = {} ## "cx,cy" → owner_instance_id


func clear() -> void:
	_cells.clear()


func clear_owner(owner_id: int) -> void:
	if owner_id == 0:
		return
	var drop: Array[String] = []
	for k in _cells.keys():
		if int(_cells[k]) == owner_id:
			drop.append(str(k))
	for k in drop:
		_cells.erase(k)


## 写入该单位当前占用的格（先清自己旧预约）。cells: Array[Vector2i]
func set_owner_cells(owner_id: int, cells: Array) -> void:
	clear_owner(owner_id)
	if owner_id == 0:
		return
	for c in cells:
		if not (c is Vector2i):
			continue
		var v: Vector2i = c
		var k := _key(v.x, v.y)
		# 已被别人占：不抢；自己可覆盖
		if _cells.has(k) and int(_cells[k]) != owner_id:
			continue
		_cells[k] = owner_id


func is_blocked_for(cx: int, cy: int, self_id: int) -> bool:
	var k := _key(cx, cy)
	if not _cells.has(k):
		return false
	return int(_cells[k]) != self_id


func _key(cx: int, cy: int) -> String:
	return "%d,%d" % [cx, cy]
