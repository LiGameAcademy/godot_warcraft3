extends Node2D

## 隔离验证入口：地面从左向右升高，Godot 只提交命令并显示内核位置/朝向。
@export var move_speed: float = 120.0
@export var turn_rate: float = 0.5
@onready var _bridge: Node = $RtsKernelBridge
@onready var _visual: Polygon2D = $EntityVisual
@onready var _status: Label = $Status

const GRID_SIZE: Vector2i = Vector2i(24, 16)
const CELL_SIZE: float = 32.0
var _wall: Rect2i = Rect2i(12, 0, 1, 10)
var _accumulator: float = 0.0
var _sequence: int = 1
var _snapshot: String = ""
var _aim: Vector2 = Vector2.ZERO


func _ready() -> void:
	var flags: PackedByteArray = PackedByteArray()
	flags.resize(GRID_SIZE.x * GRID_SIZE.y)
	for y: int in range(_wall.position.y, _wall.end.y):
		for x: int in range(_wall.position.x, _wall.end.x):
			flags[y * GRID_SIZE.x + x] = 2
	var heights: PackedFloat64Array = PackedFloat64Array()
	heights.resize((GRID_SIZE.x + 1) * (GRID_SIZE.y + 1))
	for index: int in range(heights.size()):
		heights[index] = float(index % (GRID_SIZE.x + 1)) * CELL_SIZE
	if not bool(_bridge.call("ResetTerrainMatch", GRID_SIZE.x, GRID_SIZE.y, CELL_SIZE, Vector2.ZERO, flags,
		GRID_SIZE.x + 1, GRID_SIZE.y + 1, CELL_SIZE, Vector2.ZERO, heights, 30, 7)):
		_status.text = str(_bridge.call("GetLastError"))
		set_process(false)
		return
	_bridge.call("SubmitSpawn", 1, 0, 0, Vector2(80, 80))
	_bridge.call("Step", 1)
	_sync_view()


func _process(delta: float) -> void:
	_accumulator += delta
	var tick: float = 1.0 / float(_bridge.call("GetTickRate"))
	while _accumulator >= tick:
		_bridge.call("Step", 1)
		_accumulator -= tick
	_sync_view()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			var cell: Vector2 = (mouse.position / CELL_SIZE).floor()
			_aim = (cell + Vector2(0.5, 0.5)) * CELL_SIZE
			var frame: int = int(_bridge.call("GetFrame")) + 1
			_bridge.call("SubmitMotionMoveTo", frame, 0, _sequence, 1, _aim, move_speed, 0, turn_rate, true)
			_sequence += 1
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_SPACE:
				_bridge.call("SubmitStop", int(_bridge.call("GetFrame")) + 1, 0, _sequence, 1)
				_sequence += 1
			KEY_S:
				_snapshot = str(_bridge.call("CaptureSnapshotJson"))
			KEY_R:
				if not _snapshot.is_empty() and bool(_bridge.call("RestoreSnapshotJson", _snapshot)):
					_accumulator = 0.0


func _draw() -> void:
	for column: int in range(GRID_SIZE.x):
		var shade: float = 0.05 + 0.12 * float(column) / float(GRID_SIZE.x - 1)
		draw_rect(Rect2(column * CELL_SIZE, 0, CELL_SIZE, GRID_SIZE.y * CELL_SIZE), Color(shade, shade + 0.02, shade + 0.04))
	for x: int in range(GRID_SIZE.x + 1):
		draw_line(Vector2(x * CELL_SIZE, 0), Vector2(x * CELL_SIZE, GRID_SIZE.y * CELL_SIZE), Color(0.14, 0.18, 0.22))
	for y: int in range(GRID_SIZE.y + 1):
		draw_line(Vector2(0, y * CELL_SIZE), Vector2(GRID_SIZE.x * CELL_SIZE, y * CELL_SIZE), Color(0.14, 0.18, 0.22))
	draw_rect(Rect2(Vector2(_wall.position) * CELL_SIZE, Vector2(_wall.size) * CELL_SIZE), Color(0.5, 0.25, 0.2))
	if _aim != Vector2.ZERO:
		draw_circle(_aim, 5.0, Color(0.5, 1.0, 0.6))


func _sync_view() -> void:
	var views: Array = _bridge.call("ReadEntityViews")
	if views.is_empty():
		return
	var view: Dictionary = views[0]
	_visual.position = view["position"] as Vector2
	_visual.rotation = float(view["facing"])
	_status.text = "Ground rises right | Click move | Space stop | S save | R restore\nframe=%d moving=%s  %s" % [
		int(_bridge.call("GetFrame")), str(view["moving"]), str(_bridge.call("GetLastError"))]
	queue_redraw()
