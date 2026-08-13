class_name TrainQueue
extends Node

## 建筑训练队列（最小：1 队列长度；F2-6 不支持队列叠加）。
## 挂 Barracks / Altar / Town Hall 等能训兵/英雄的建筑子节点。
##
## 状态机 IDLE → TRAINING → IDLE
## start()：扣资源（外部 pre-validate） + 启动 timer
## timer 跑完 → training_completed.emit → Director 刷单位到建筑门口
## cancel()：退款 75%（WC3 行为；建筑训练可取消）
##
## 不扣 fused 人口（前置主城/农场已给够；F3-F4 接严格 fused 校验）

signal state_changed(state: int)
signal training_started(unit_id: String, time_sec: float)
signal training_completed(unit_id: String, site_wc3: Vector2, owner: int)
signal training_cancelled(unit_id: String, refund_g: int, refund_l: int)


const STATE_IDLE := 0
const STATE_TRAINING := 1

## 取消训练退款比例（WC3：训练可取消，退 75%）。
const CANCEL_REFUND_RATIO := 0.75


var _unit_id: String = ""
var _time_sec: float = 0.0
var _elapsed: float = 0.0
var _gold_spent: int = 0
var _lumber_spent: int = 0
var _site_wc3: Vector2 = Vector2.INF
var _owner: int = 0
var _state: int = STATE_IDLE


func _ready() -> void:
	set_process(false)


## 训练 unit_id（hfoo/hkni/hamg）。返回 true = 资源已扣 + timer 启动。
## 调用方需先 validate：资源 / 建筑能训该单位 / fused 人口（fused 校验留 F3-F4）。
func start(
	unit_id: String,
	time_sec: float,
	gold: int,
	lumber: int,
	site_wc3: Vector2,
	player_owner: int
) -> bool:
	if _state != STATE_IDLE:
		return false
	if unit_id.is_empty() or time_sec <= 0.0:
		return false
	_unit_id = unit_id
	_time_sec = time_sec
	_elapsed = 0.0
	_gold_spent = gold
	_lumber_spent = lumber
	_site_wc3 = site_wc3
	_owner = player_owner
	_state = STATE_TRAINING
	set_process(true)
	state_changed.emit(_state)
	training_started.emit(_unit_id, _time_sec)
	return true


## 取消：退款 75%。
func cancel() -> bool:
	if _state != STATE_TRAINING:
		return false
	_state = STATE_IDLE
	set_process(false)
	var refund_g: int = int(round(float(_gold_spent) * CANCEL_REFUND_RATIO))
	var refund_l: int = int(round(float(_lumber_spent) * CANCEL_REFUND_RATIO))
	var u: String = _unit_id
	_unit_id = ""
	state_changed.emit(_state)
	training_cancelled.emit(u, refund_g, refund_l)
	return true


func is_training() -> bool:
	return _state == STATE_TRAINING


func current_unit() -> String:
	return _unit_id


func progress_ratio() -> float:
	if _time_sec <= 0.0:
		return 1.0
	return clampf(_elapsed / _time_sec, 0.0, 1.0)


func _process(delta: float) -> void:
	if _state != STATE_TRAINING:
		return
	_elapsed += delta
	if _elapsed >= _time_sec:
		_state = STATE_IDLE
		set_process(false)
		var u: String = _unit_id
		var site: Vector2 = _site_wc3
		var o: int = _owner
		_unit_id = ""
		state_changed.emit(_state)
		training_completed.emit(u, site, o)
