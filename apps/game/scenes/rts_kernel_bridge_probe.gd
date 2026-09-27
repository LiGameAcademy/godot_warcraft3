extends Node2D

## M1 隔离验证入口：GDScript 只提交命令并绘制 C# 内核的只读位置镜像。
## 方向键改变速度，空格停止；内核固定 30 Hz，与绘制帧率解耦。

@onready var _bridge: Node = $RtsKernelBridge
@onready var _entity_visual: Polygon2D = $EntityVisual
@onready var _status: Label = $Status

var _accumulator := 0.0
var _sequence := 0
var _entity_id := 0


func _ready() -> void:
	_bridge.call("ResetMatch", 30, 0xC0FFEE)
	_submit_spawn(Vector2(320.0, 240.0))
	_bridge.call("Step", 1)
	_sync_view()


func _process(delta: float) -> void:
	_accumulator += delta
	var tick_seconds: float = 1.0 / float(_bridge.call("GetTickRate"))
	while _accumulator >= tick_seconds:
		_bridge.call("Step", 1)
		_accumulator -= tick_seconds
	_sync_view()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo or _entity_id <= 0:
		return
	var velocity := Vector2.ZERO
	match event.keycode:
		KEY_LEFT:
			velocity = Vector2(-120.0, 0.0)
		KEY_RIGHT:
			velocity = Vector2(120.0, 0.0)
		KEY_UP:
			velocity = Vector2(0.0, -120.0)
		KEY_DOWN:
			velocity = Vector2(0.0, 120.0)
		KEY_SPACE:
			_submit_stop()
			return
		_:
			return
	_submit_velocity(velocity)


func _submit_spawn(position: Vector2) -> void:
	var frame: int = int(_bridge.call("GetFrame")) + 1
	_bridge.call("SubmitSpawn", frame, 0, _next_sequence(), position)


func _submit_velocity(velocity: Vector2) -> void:
	var frame: int = int(_bridge.call("GetFrame")) + 1
	_bridge.call("SubmitVelocity", frame, 0, _next_sequence(), _entity_id, velocity)


func _submit_stop() -> void:
	var frame: int = int(_bridge.call("GetFrame")) + 1
	_bridge.call("SubmitStop", frame, 0, _next_sequence(), _entity_id)


func _next_sequence() -> int:
	var current := _sequence
	_sequence += 1
	return current


func _sync_view() -> void:
	var views: Array = _bridge.call("ReadEntityViews")
	if views.is_empty():
		return
	var view: Dictionary = views[0]
	_entity_id = int(view["id"])
	_entity_visual.position = view["position"] as Vector2
	_status.text = "frame=%d  entity=%d  hash=%s" % [
		int(_bridge.call("GetFrame")),
		_entity_id,
		str(_bridge.call("GetStateHash")).substr(0, 12),
	]
