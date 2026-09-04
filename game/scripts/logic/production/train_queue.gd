class_name TrainQueue
extends Node

## 建筑训练/研究队列（对齐 WC3：每建筑最多 7 槽，训兵与研究共用）。
## 挂 Barracks / Altar / Town Hall 等可训建筑子节点。
##
## 槽 0 为正在训练；1..N-1 为等待。点训兵按钮 enqueue；满 7 拒单。
## 取消：训练单位一律退 100%（原作；建造取消才是 ~75%）。完工自动开下一槽。

signal state_changed(state: int)
signal queue_changed
signal training_started(unit_id: String, time_sec: float)
signal training_completed(unit_id: String, site_wc3: Vector2, owner: int)
signal training_cancelled(unit_id: String, refund_g: int, refund_l: int, food: int)
## 当前槽进度（约 10Hz）；HUD 订阅，勿让 Director 每帧轮询。
signal progress_changed(progress: float, remaining_sec: float)

## 最近一次完工条目（含 is_revive / revive_level）；Director 读后即清。
var _last_completed: Dictionary = {}
## 最近一次取消条目（复活失败时写回 DeathRegistry）。
var _last_cancelled: Dictionary = {}


const STATE_IDLE := 0
const STATE_TRAINING := 1

## 原作建筑生产队列上限。
const MAX_QUEUE := 7
## 取消训练退款比例（WC3：Canceled Units = 100%）。
const CANCEL_REFUND_RATIO := 1.0


## 每项：unit_id, time_sec, gold, lumber, food, site_wc3, owner, elapsed
var _entries: Array[Dictionary] = []
var _state: int = STATE_IDLE
var _progress_emit_accum: float = 0.0
const PROGRESS_EMIT_INTERVAL := 0.1


func _ready() -> void:
	set_process(false)


## 是否已满（不可再下单）。
func is_full() -> bool:
	return _entries.size() >= MAX_QUEUE


func queue_count() -> int:
	return _entries.size()


func is_training() -> bool:
	return not _entries.is_empty()


func current_unit() -> String:
	if _entries.is_empty():
		return ""
	return str(_entries[0].get("unit_id", ""))


func progress_ratio() -> float:
	if _entries.is_empty():
		return 0.0
	var t := float(_entries[0].get("time_sec", 0.0))
	if t <= 0.0:
		return 1.0
	return clampf(float(_entries[0].get("elapsed", 0.0)) / t, 0.0, 1.0)


## HUD / 命令卡：[{ unit_id, progress, active, remaining_sec, gold, lumber, food }, ...]
func snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(_entries.size()):
		var e: Dictionary = _entries[i]
		var t := float(e.get("time_sec", 0.0))
		var elapsed := float(e.get("elapsed", 0.0))
		var prog := 0.0
		if i == 0 and t > 0.0:
			prog = clampf(elapsed / t, 0.0, 1.0)
		var remain := 0.0
		if i == 0 and t > 0.0:
			remain = maxf(t - elapsed, 0.0)
		elif t > 0.0:
			remain = t
		out.append({
			"unit_id": str(e.get("unit_id", "")),
			"progress": prog,
			"active": i == 0,
			"remaining_sec": remain,
			"gold": int(e.get("gold", 0)),
			"lumber": int(e.get("lumber", 0)),
			"food": int(e.get("food", 0)),
			"revive_level": int(e.get("revive_level", 0)),
			"is_revive": bool(e.get("is_revive", false)),
		})
	return out


## 入队。已满 / 参数非法 → false（调用方负责退资源）。
func enqueue(
	unit_id: String,
	time_sec: float,
	gold: int,
	lumber: int,
	food: int,
	site_wc3: Vector2,
	player_owner: int,
	extra: Dictionary = {}
) -> bool:
	if is_full():
		return false
	if unit_id.is_empty() or time_sec <= 0.0:
		return false
	var entry := {
		"unit_id": unit_id,
		"time_sec": time_sec,
		"gold": gold,
		"lumber": lumber,
		"food": food,
		"site_wc3": site_wc3,
		"owner": player_owner,
		"elapsed": 0.0,
	}
	for k in extra.keys():
		entry[k] = extra[k]
	var was_empty := _entries.is_empty()
	_entries.append(entry)
	if was_empty:
		_begin_active()
	else:
		queue_changed.emit()
	return true


## 兼容旧 API：空闲时入队并立刻开工。已有队列时失败（请用 enqueue）。
func start(
	unit_id: String,
	time_sec: float,
	gold: int,
	lumber: int,
	site_wc3: Vector2,
	player_owner: int
) -> bool:
	if not _entries.is_empty():
		return false
	return enqueue(unit_id, time_sec, gold, lumber, 0, site_wc3, player_owner)


## 取消进行中的一槽（index 0）。
func cancel() -> bool:
	return cancel_at(0)


## 取消指定槽。训练单位一律全额退款（原作 Canceled Units = 100%）。
func cancel_at(index: int) -> bool:
	if index < 0 or index >= _entries.size():
		return false
	var e: Dictionary = _entries[index]
	var uid := str(e.get("unit_id", ""))
	var gold := int(e.get("gold", 0))
	var lumber := int(e.get("lumber", 0))
	var food := int(e.get("food", 0))
	var refund_g: int = int(round(float(gold) * CANCEL_REFUND_RATIO))
	var refund_l: int = int(round(float(lumber) * CANCEL_REFUND_RATIO))
	_last_cancelled = e.duplicate(true)
	_entries.remove_at(index)
	if _entries.is_empty():
		_state = STATE_IDLE
		set_process(false)
		state_changed.emit(_state)
	elif index == 0:
		# 取消当前 → 下一槽立刻开工
		_begin_active()
	queue_changed.emit()
	training_cancelled.emit(uid, refund_g, refund_l, food)
	return true


func take_last_cancelled() -> Dictionary:
	var out := _last_cancelled
	_last_cancelled = {}
	return out


func take_last_completed() -> Dictionary:
	var out := _last_completed
	_last_completed = {}
	return out


func _begin_active() -> void:
	if _entries.is_empty():
		_state = STATE_IDLE
		set_process(false)
		state_changed.emit(_state)
		queue_changed.emit()
		return
	_entries[0]["elapsed"] = 0.0
	_progress_emit_accum = 0.0
	_state = STATE_TRAINING
	set_process(true)
	state_changed.emit(_state)
	queue_changed.emit()
	training_started.emit(str(_entries[0].get("unit_id", "")), float(_entries[0].get("time_sec", 0.0)))
	_emit_progress()


func _emit_progress() -> void:
	if _entries.is_empty():
		return
	var t := float(_entries[0].get("time_sec", 0.0))
	var elapsed := float(_entries[0].get("elapsed", 0.0))
	var prog := 1.0 if t <= 0.0 else clampf(elapsed / t, 0.0, 1.0)
	var remain := 0.0 if t <= 0.0 else maxf(t - elapsed, 0.0)
	progress_changed.emit(prog, remain)


func _process(delta: float) -> void:
	if _entries.is_empty():
		return
	var e: Dictionary = _entries[0]
	e["elapsed"] = float(e.get("elapsed", 0.0)) + delta
	_entries[0] = e
	var t := float(e.get("time_sec", 0.0))
	_progress_emit_accum += delta
	if _progress_emit_accum >= PROGRESS_EMIT_INTERVAL:
		_progress_emit_accum = 0.0
		_emit_progress()
	if float(e.get("elapsed", 0.0)) < t:
		return
	var uid := str(e.get("unit_id", ""))
	var site: Vector2 = e.get("site_wc3", Vector2.INF) as Vector2
	var o := int(e.get("owner", 0))
	_last_completed = e.duplicate(true)
	_entries.remove_at(0)
	training_completed.emit(uid, site, o)
	if _entries.is_empty():
		_state = STATE_IDLE
		set_process(false)
		state_changed.emit(_state)
		queue_changed.emit()
	else:
		_begin_active()
