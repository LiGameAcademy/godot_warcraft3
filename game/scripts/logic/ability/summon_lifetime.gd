class_name SummonLifetime
extends Node

## 召唤物寿命：到期 queue_free 宿主单位。

var _left: float = 0.0


func configure(duration_sec: float) -> void:
	_left = maxf(duration_sec, 0.0)
	set_process(_left > 0.0)


func _process(delta: float) -> void:
	if _left <= 0.0:
		set_process(false)
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = 0.0
	set_process(false)
	var host := get_parent()
	if host != null and is_instance_valid(host):
		host.queue_free()
