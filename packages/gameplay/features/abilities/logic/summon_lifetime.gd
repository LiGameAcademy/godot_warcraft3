class_name SummonLifetime
extends Node

## 召唤物寿命：到期经 kill_cb 走死亡管线（默认 queue_free 兜底）。

var _left: float = 0.0
var _total: float = 0.0
var _kill_cb: Callable = Callable()


func configure(duration_sec: float, kill_cb: Callable = Callable()) -> void:
	_total = maxf(duration_sec, 0.0)
	_left = _total
	_kill_cb = kill_cb
	set_process(_left > 0.0)


func remaining_sec() -> float:
	return maxf(_left, 0.0)


func total_sec() -> float:
	return maxf(_total, 0.0)


func progress_ratio() -> float:
	if _total <= 0.0:
		return 0.0
	return clampf(_left / _total, 0.0, 1.0)


func _process(delta: float) -> void:
	_tick(delta)


## 单测 / 确定性推进：不依赖引擎 process 帧。
func tick(delta: float) -> void:
	_tick(delta)


func _tick(delta: float) -> void:
	if _left <= 0.0:
		set_process(false)
		return
	_left -= delta
	if _left > 0.0:
		return
	_expire()


func _expire() -> void:
	_left = 0.0
	set_process(false)
	var host := get_parent() as Node3D
	if host == null or not is_instance_valid(host):
		return
	if _host_already_dead(host):
		return
	if _kill_cb.is_valid():
		_kill_cb.call(host)
	elif is_instance_valid(host):
		host.queue_free()


static func _host_already_dead(host: Node3D) -> bool:
	if host == null or not is_instance_valid(host):
		return true
	if not host.has_meta("life"):
		return false
	return float(host.get_meta("life", 0.0)) <= 0.0
