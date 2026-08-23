class_name MilitiaController
extends Node

## 人族农民 ↔ 民兵（Amil）。Logic：计时变身；Present 换模型由会话注入。
## P0：点 Call to Arms 立刻变身（不跑主城），到期或再点收回。

const NODE_NAME := "MilitiaController"
const ABIL_ID := "Amil"
const FORM_PEASANT := "hpea"
const FORM_MILITIA := "hmil"
const DEFAULT_DURATION_SEC := 45.0

signal form_changed(to_type_id: String)

## Callable(unit: Node3D, new_type_id: String) -> bool
var _apply_form: Callable = Callable()
var _duration_sec: float = DEFAULT_DURATION_SEC
var _revert_left: float = 0.0


func configure(apply_form: Callable, duration_sec: float = -1.0) -> void:
	_apply_form = apply_form
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


## 农民→民兵；已是民兵→收回农民。成功 true。
func toggle_call_to_arms() -> bool:
	if is_militia():
		return _revert_now()
	return _arm_now()


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


func _revert_now() -> bool:
	var body := _body()
	if body == null or not _apply_form.is_valid():
		return false
	if CombatQuery.type_id_of(body) != FORM_MILITIA:
		return false
	if not bool(_apply_form.call(body, FORM_PEASANT)):
		return false
	_revert_left = 0.0
	set_process(false)
	form_changed.emit(FORM_PEASANT)
	return true


func _process(delta: float) -> void:
	if _revert_left <= 0.0:
		set_process(false)
		return
	_revert_left -= delta
	if _revert_left <= 0.0:
		_revert_left = 0.0
		_revert_now()


func _ready() -> void:
	set_process(false)


func _body() -> Node3D:
	return get_parent() as Node3D


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
