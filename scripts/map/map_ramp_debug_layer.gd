class_name MapRampDebugLayer
extends Node3D
## 斜坡调试层（蓝菱形）。feature/ramp-rebuild：已清空，待逐步重做。


@export var enabled: bool = false

var last_count: int = 0


func build(_ctx) -> void:
	_clear()
	last_count = 0


func _clear() -> void:
	for c in get_children():
		c.queue_free()
