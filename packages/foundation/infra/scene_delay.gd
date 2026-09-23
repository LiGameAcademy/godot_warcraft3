extends RefCounted

## 延迟归属于宿主节点：随宿主暂停/冻结，宿主销毁时一起取消。
## 与 SceneTreeTimer 不同，不在已结束或已卸载的对局之外继续计时。
static func create_timer(host: Node, seconds: float) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(seconds, 0.001)
	timer.autostart = true
	timer.timeout.connect(timer.queue_free)
	host.add_child(timer)
	return timer
