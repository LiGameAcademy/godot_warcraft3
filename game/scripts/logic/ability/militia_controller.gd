class_name MilitiaController
extends Node

## 人族农民 ↔ 民兵（Amil）。Logic：计时变身；Present 换模型由会话注入。
## 原作：主动变民兵 / 主动收回须先走到己方主城；计时到期被动收回原地变身。

const NODE_NAME := "MilitiaController"
const ABIL_ID := "Amil"
const FORM_PEASANT := "hpea"
const FORM_MILITIA := "hmil"
const DEFAULT_DURATION_SEC := 45.0
## 到达主城判定（WC3 水平距离）
const TOWN_HALL_ARRIVE_WC3 := 420.0

signal form_changed(to_type_id: String)

enum PendingForm { NONE, TO_MILITIA, TO_PEASANT }

## Callable(unit: Node3D, new_type_id: String) -> bool
var _apply_form: Callable = Callable()
## Callable() -> Node3D 己方 htow/hkee/hcas
var _find_town_hall: Callable = Callable()
## Callable(unit: Node3D, hall: Node3D) -> void 下发移动
var _order_move_to_hall: Callable = Callable()
var _duration_sec: float = DEFAULT_DURATION_SEC
var _revert_left: float = 0.0
var _pending: int = PendingForm.NONE


func configure(
	apply_form: Callable,
	find_town_hall: Callable = Callable(),
	order_move_to_hall: Callable = Callable(),
	duration_sec: float = -1.0
) -> void:
	_apply_form = apply_form
	if find_town_hall.is_valid():
		_find_town_hall = find_town_hall
	if order_move_to_hall.is_valid():
		_order_move_to_hall = order_move_to_hall
	if duration_sec > 0.0:
		_duration_sec = duration_sec
	else:
		_duration_sec = _duration_from_def()


static func of(unit: Node) -> MilitiaController:
	if unit == null or not is_instance_valid(unit):
		return null
	return unit.get_node_or_null(NODE_NAME) as MilitiaController


static func unit_has_abil(unit: Node) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var tid := CombatQuery.type_id_of(unit)
	if tid == FORM_PEASANT or tid == FORM_MILITIA:
		return true
	if tid.is_empty():
		return false
	return CommandButtonCatalog.get_shared().get_abil_list(tid).find(ABIL_ID) >= 0


func is_militia() -> bool:
	return CombatQuery.type_id_of(_body()) == FORM_MILITIA


func revert_left_sec() -> float:
	return maxf(_revert_left, 0.0)


func duration_sec() -> float:
	return maxf(_duration_sec, 0.0)


## 农民→民兵；已是民兵→收回农民。成功 true（含已下发「走向主城」）。
func toggle_call_to_arms() -> bool:
	if is_militia():
		return _begin_revert_manual()
	return _begin_arm()


func _begin_arm() -> bool:
	var body := _body()
	if body == null or not _apply_form.is_valid():
		return false
	if CombatQuery.type_id_of(body) != FORM_PEASANT:
		return false
	return _begin_walk_to_hall(PendingForm.TO_MILITIA)


func _begin_revert_manual() -> bool:
	var body := _body()
	if body == null or not _apply_form.is_valid():
		return false
	if CombatQuery.type_id_of(body) != FORM_MILITIA:
		return false
	return _begin_walk_to_hall(PendingForm.TO_PEASANT)


func _begin_walk_to_hall(kind: int) -> bool:
	var body := _body()
	if body == null:
		return false
	var hall := _resolve_town_hall()
	if hall == null:
		return false
	if _is_at_town_hall(body, hall):
		return _complete_pending(kind)
	_pending = kind
	if _order_move_to_hall.is_valid():
		_order_move_to_hall.call(body, hall)
	set_process(true)
	return true


func _complete_pending(kind: int = _pending) -> bool:
	_pending = PendingForm.NONE
	match kind:
		PendingForm.TO_MILITIA:
			return _arm_now()
		PendingForm.TO_PEASANT:
			return _revert_now(false)
		_:
			return false


func _arm_now() -> bool:
	var body := _body()
	if body == null or not _apply_form.is_valid():
		return false
	if CombatQuery.type_id_of(body) != FORM_PEASANT:
		return false
	if not bool(_apply_form.call(body, FORM_MILITIA)):
		return false
	_revert_left = _duration_sec
	set_process(true)
	form_changed.emit(FORM_MILITIA)
	return true


## passive=false：计时到期，原地收回，不需主城。
func _revert_now(_passive: bool = false) -> bool:
	var body := _body()
	if body == null or not _apply_form.is_valid():
		return false
	if CombatQuery.type_id_of(body) != FORM_MILITIA:
		return false
	if not bool(_apply_form.call(body, FORM_PEASANT)):
		return false
	_revert_left = 0.0
	_pending = PendingForm.NONE
	set_process(false)
	form_changed.emit(FORM_PEASANT)
	return true


func _process(delta: float) -> void:
	var body := _body()
	if body == null:
		set_process(false)
		return
	if _pending != PendingForm.NONE:
		var hall := _resolve_town_hall()
		if hall != null and _is_at_town_hall(body, hall):
			_complete_pending()
		return
	if _revert_left <= 0.0:
		set_process(false)
		return
	_revert_left -= delta
	if _revert_left <= 0.0:
		_revert_left = 0.0
		_revert_now(true)


func _ready() -> void:
	set_process(false)


func _body() -> Node3D:
	return get_parent() as Node3D


func _resolve_town_hall() -> Node3D:
	if not _find_town_hall.is_valid():
		return null
	var hall: Variant = _find_town_hall.call()
	if hall is Node3D and is_instance_valid(hall):
		return hall as Node3D
	return null


static func _is_at_town_hall(unit: Node3D, hall: Node3D) -> bool:
	if unit == null or hall == null:
		return false
	if not is_instance_valid(unit) or not is_instance_valid(hall):
		return false
	var pu := Wc3Coords.godot_to_wc3_xy(unit.global_position)
	var ph := Wc3Coords.godot_to_wc3_xy(hall.global_position)
	return pu.distance_to(ph) <= TOWN_HALL_ARRIVE_WC3


func _duration_from_def() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return DEFAULT_DURATION_SEC
	var store: Node = tree.root.get_node_or_null("Wc3DefStore")
	if store == null or not store.has_method("ensure_table"):
		return DEFAULT_DURATION_SEC
	store.ensure_table(AbilityDataDef.TABLE_NAME)
	var ab := store.get_row(AbilityDataDef.TABLE_NAME, ABIL_ID) as AbilityDataDef
	if ab != null and ab.dur1 > 0.0:
		return ab.dur1
	return DEFAULT_DURATION_SEC
